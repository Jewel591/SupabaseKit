//
//  SupabaseProfileService.swift
//  SupabaseKit
//

import Foundation
import OSLog
import Supabase

// MARK: - Supabase Profile Service Errors

public enum SupabaseProfileError: LocalizedError {
    case userNotAuthenticated
    case profileNotFound
    case saveFailed(Error)
    case queryFailed(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "用户未登录"
        case .profileNotFound:
            return "用户资料未找到"
        case .saveFailed(let error):
            return "保存失败: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "查询失败: \(error.localizedDescription)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supabase DTOs

/// Supabase profiles 表 DTO
public struct SupabaseProfile: Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var bio: String?
    public var avatarUrl: String?
    public var isPublic: Bool
    public let createdAt: Date
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// 用于插入新 profile 的 DTO
struct InsertProfile: Codable {
    let id: UUID
    let displayName: String
    let bio: String?
    let avatarUrl: String?
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case isPublic = "is_public"
    }
}

/// 用于更新 profile 的 DTO
struct UpdateProfile: Codable {
    var displayName: String?
    var bio: String?
    var avatarUrl: String?
    var isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case isPublic = "is_public"
    }
}

// MARK: - Supabase Profile Service

/// Supabase 用户资料管理服务
@MainActor
public final class SupabaseProfileService {
    // MARK: - Singleton

    public static let shared = SupabaseProfileService()

    // MARK: - Properties

    private var client: SupabaseClient { SupabaseConfig.client }
    private let logger = Logger(
        subsystem: "com.supabasekit",
        category: "SupabaseProfileService"
    )

    // MARK: - Initialization

    private init() {}

    // MARK: - Helper Methods

    private func getCurrentUserId() async throws -> UUID {
        guard let session = try? await client.auth.session else {
            throw SupabaseProfileError.userNotAuthenticated
        }
        return session.user.id
    }

    /// 检查用户是否已登录
    public func isAuthenticated() async -> Bool {
        do {
            _ = try await getCurrentUserId()
            return true
        } catch {
            return false
        }
    }

    // MARK: - User Profile Operations

    /// 创建用户资料
    public func createUserProfile(displayName: String, bio: String? = nil) async throws -> UserProfile {
        let userId = try await getCurrentUserId()

        let insertData = InsertProfile(
            id: userId,
            displayName: displayName,
            bio: bio,
            avatarUrl: nil,
            isPublic: true
        )

        do {
            let response: SupabaseProfile = try await client
                .from("profiles")
                .insert(insertData)
                .select()
                .single()
                .execute()
                .value

            logger.info("用户资料创建成功: \(displayName)")
            return response.toUserProfile()
        } catch {
            logger.error("创建用户资料失败: \(error.localizedDescription)")
            throw SupabaseProfileError.saveFailed(error)
        }
    }

    /// 查询用户资料（通过 userId）
    public func fetchUserProfile(for userId: UUID) async throws -> UserProfile? {
        do {
            let response: SupabaseProfile? = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            if let profile = response {
                logger.debug("查询用户资料成功: \(userId)")
                return profile.toUserProfile()
            }
            return nil
        } catch {
            logger.debug("未找到用户资料: \(userId)")
            return nil
        }
    }

    /// 查询当前用户的资料
    public func fetchCurrentUserProfile() async throws -> UserProfile? {
        let userId = try await getCurrentUserId()
        return try await fetchUserProfile(for: userId)
    }

    /// 更新用户资料
    public func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
        let userId = try await getCurrentUserId()

        let updateData = UpdateProfile(
            displayName: profile.displayName,
            bio: profile.bio,
            avatarUrl: profile.avatarURL,
            isPublic: profile.isPublic
        )

        do {
            let response: SupabaseProfile = try await client
                .from("profiles")
                .update(updateData)
                .eq("id", value: userId)
                .select()
                .single()
                .execute()
                .value

            logger.info("用户资料更新成功")
            return response.toUserProfile()
        } catch {
            logger.error("更新用户资料失败: \(error.localizedDescription)")
            throw SupabaseProfileError.saveFailed(error)
        }
    }

    // MARK: - Batch User Profile Fetch

    /// 批量查询用户资料
    public func fetchUserProfiles(for userIds: [UUID]) async throws -> [UUID: UserProfile] {
        guard !userIds.isEmpty else { return [:] }

        do {
            let response: [SupabaseProfile] = try await client
                .from("profiles")
                .select()
                .in("id", values: userIds)
                .execute()
                .value

            var profiles: [UUID: UserProfile] = [:]
            for supabaseProfile in response {
                profiles[supabaseProfile.id] = supabaseProfile.toUserProfile()
            }

            logger.debug("批量查询用户资料完成，成功 \(profiles.count)/\(userIds.count)")
            return profiles
        } catch {
            logger.error("批量查询用户资料失败: \(error.localizedDescription)")
            throw SupabaseProfileError.queryFailed(error)
        }
    }
}

// MARK: - DTO Conversions

extension SupabaseProfile {
    public func toUserProfile() -> UserProfile {
        UserProfile(
            userId: id,
            displayName: displayName,
            bio: bio,
            isPublic: isPublic,
            createdAt: createdAt,
            avatarURL: avatarUrl
        )
    }
}
