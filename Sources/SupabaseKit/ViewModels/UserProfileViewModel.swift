//
//  UserProfileViewModel.swift
//  SupabaseKit
//

import Foundation
import OSLog
import UIKit

// MARK: - User Profile ViewModel Errors

public enum UserProfileViewModelError: LocalizedError {
    case profileNotCreated
    case profileNotFound
    case userNotAuthenticated
    case createFailed(Error)
    case updateFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .profileNotCreated:
            return "资料未创建"
        case .profileNotFound:
            return "资料未找到"
        case .userNotAuthenticated:
            return "用户未登录"
        case .createFailed(let error):
            return "创建失败: \(error.localizedDescription)"
        case .updateFailed(let error):
            return "更新失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - User Profile ViewModel

/// 用户资料视图模型
/// 负责用户资料的创建、查询、更新和本地缓存
@Observable
@MainActor
public final class UserProfileViewModel {
    // MARK: - Singleton

    public static let shared = UserProfileViewModel()

    // MARK: - Properties

    private let supabaseService = SupabaseProfileService.shared
    private let avatarService = SupabaseAvatarService.shared
    private let logger = Logger(
        subsystem: "com.supabasekit",
        category: "UserProfileViewModel"
    )

    /// 当前用户资料
    public var currentProfile: UserProfile?

    /// 正在上传头像
    public var isUploadingAvatar = false

    /// 上传错误信息
    public var uploadError: String?

    /// 保存错误信息
    public var saveError: String?

    // UserDefaults 键
    private let profileCacheKey = "com.supabasekit.cachedUserProfile"

    // MARK: - Initialization

    private init() {
        loadCachedProfile()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard await self.supabaseService.isAuthenticated() else { return }
            do {
                _ = try await self.getCurrentUserProfile()
                self.logger.debug("后台预加载用户资料完成")
            } catch {
                self.logger.error("后台预加载失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Profile Check

    /// 检查用户资料是否已创建
    public func hasUserProfile() async -> Bool {
        if currentProfile != nil {
            logger.debug("内存缓存中存在用户资料")
            return true
        }

        if loadCachedProfile() != nil {
            logger.debug("本地缓存中存在用户资料")
            return true
        }

        do {
            let profile = try await supabaseService.fetchCurrentUserProfile()
            if let profile = profile {
                saveToCache(profile)
                logger.debug("Supabase 中存在用户资料")
                return true
            }
        } catch {
            logger.error("查询用户资料失败: \(error.localizedDescription)")
        }

        logger.debug("用户资料不存在")
        return false
    }

    /// 确保用户资料存在，如果不存在则自动创建
    public func ensureUserProfileExists(defaultDisplayName: String = "User") async throws -> UserProfile {
        if let cached = currentProfile {
            logger.debug("从缓存返回用户资料")
            return cached
        }

        if let profile = try await supabaseService.fetchCurrentUserProfile() {
            saveToCache(profile)
            logger.debug("从 Supabase 返回用户资料")
            return profile
        }

        logger.info("Supabase 中未找到用户资料，将自动创建")

        let newProfile = try await createUserProfile(
            displayName: defaultDisplayName,
            bio: nil
        )

        logger.info("已自动创建用户资料: \(defaultDisplayName)")
        return newProfile
    }

    // MARK: - Profile CRUD

    /// 创建用户资料
    public func createUserProfile(
        displayName: String,
        bio: String? = nil
    ) async throws -> UserProfile {
        do {
            let profile = try await supabaseService.createUserProfile(
                displayName: displayName,
                bio: bio
            )

            saveToCache(profile)
            logger.info("用户资料创建成功: \(displayName)")

            return profile
        } catch {
            logger.error("创建用户资料失败: \(error.localizedDescription)")
            throw UserProfileViewModelError.createFailed(error)
        }
    }

    /// 创建用户资料并上传头像照片
    public func createUserProfileWithPhoto(
        displayName: String,
        photoData: Data
    ) async throws -> UserProfile {
        var profile = try await createUserProfile(displayName: displayName)

        guard let image = UIImage(data: photoData) else {
            logger.error("无法从 Data 创建 UIImage")
            return profile
        }

        let avatarURL = try await avatarService.uploadAvatar(image)

        profile.avatarURL = avatarURL
        let updatedProfile = try await updateUserProfile(profile)

        logger.info("用户资料创建成功（含照片头像）: \(displayName)")
        return updatedProfile
    }

    /// 创建用户资料并设置预设头像 URL
    public func createUserProfileWithAvatarURL(
        displayName: String,
        avatarURL: String
    ) async throws -> UserProfile {
        var profile = try await createUserProfile(displayName: displayName)

        profile.avatarURL = avatarURL

        let updatedProfile = try await updateUserProfile(profile)
        logger.info("用户资料创建成功（含预设头像）: \(displayName)")

        return updatedProfile
    }

    /// 获取缓存的用户资料（同步方法，仅用于 UI 快速显示）
    public func getCachedProfileForDisplay() -> UserProfile? {
        return currentProfile
    }

    /// 获取当前用户资料
    public func getCurrentUserProfile() async throws -> UserProfile {
        if let cached = currentProfile {
            logger.debug("从缓存返回用户资料")
            return cached
        }

        logger.debug("从 Supabase 查询用户资料")
        guard let profile = try await supabaseService.fetchCurrentUserProfile() else {
            throw UserProfileViewModelError.profileNotFound
        }

        saveToCache(profile)
        logger.debug("从 Supabase 返回用户资料")

        return profile
    }

    /// 更新用户资料
    public func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
        saveError = nil

        do {
            let updatedProfile = try await supabaseService.updateUserProfile(profile)
            saveToCache(updatedProfile)
            logger.info("用户资料更新成功")

            return updatedProfile
        } catch {
            saveError = error.localizedDescription
            logger.error("更新用户资料失败: \(error.localizedDescription)")
            throw UserProfileViewModelError.updateFailed(error)
        }
    }

    /// 切换隐私状态
    public func togglePublicStatus() async throws {
        guard var profile = currentProfile else {
            throw UserProfileViewModelError.profileNotFound
        }

        let newStatus = !profile.isPublic
        profile.isPublic = newStatus

        logger.info("切换隐私状态: \(newStatus ? "公开" : "私密")")

        let updatedProfile = try await updateUserProfile(profile)
        currentProfile = updatedProfile

        logger.info("隐私状态切换完成: \(newStatus ? "公开" : "私密")")
    }

    /// 刷新用户资料（从 Supabase 重新获取）
    public func refreshUserProfile() async throws -> UserProfile {
        guard let profile = try await supabaseService.fetchCurrentUserProfile() else {
            throw UserProfileViewModelError.profileNotFound
        }

        saveToCache(profile)
        logger.info("用户资料刷新成功")

        return profile
    }

    // MARK: - Avatar Upload

    /// 上传用户头像
    public func uploadAvatar(_ image: UIImage) async throws -> UserProfile {
        logger.info("开始上传头像...")

        isUploadingAvatar = true
        uploadError = nil

        do {
            let avatarURL = try await avatarService.uploadAvatar(image)

            var profile = try await getCurrentUserProfile()

            profile.avatarURL = avatarURL

            let updatedProfile = try await updateUserProfile(profile)

            isUploadingAvatar = false
            logger.info("头像上传并更新成功")
            return updatedProfile
        } catch {
            isUploadingAvatar = false
            uploadError = error.localizedDescription
            logger.error("头像上传失败: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Cache Management

    private func saveToCache(_ profile: UserProfile) {
        currentProfile = profile

        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: profileCacheKey)
            logger.debug("用户资料已保存到本地缓存")
        }
    }

    @discardableResult
    private func loadCachedProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileCacheKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else {
            return nil
        }

        currentProfile = profile
        logger.debug("从本地缓存加载用户资料")

        return profile
    }

    /// 清除缓存
    public func clearCache() {
        currentProfile = nil
        UserDefaults.standard.removeObject(forKey: profileCacheKey)
        logger.debug("用户资料缓存已清除")
    }
}
