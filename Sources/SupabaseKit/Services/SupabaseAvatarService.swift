//
//  SupabaseAvatarService.swift
//  SupabaseKit
//

import Foundation
import OSLog
import Supabase
import UIKit

// MARK: - Supabase Avatar Upload Errors

public enum SupabaseAvatarError: LocalizedError {
    case compressionFailed
    case saveFailed
    case uploadFailed(Error)
    case invalidImage
    case userNotAuthenticated
    case deleteFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "图片压缩失败"
        case .saveFailed:
            return "图片保存失败"
        case .uploadFailed(let error):
            return "上传失败: \(error.localizedDescription)"
        case .invalidImage:
            return "无效的图片格式"
        case .userNotAuthenticated:
            return "用户未登录"
        case .deleteFailed(let error):
            return "删除失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supabase Avatar Service

/// Supabase 头像上传服务
@MainActor
public final class SupabaseAvatarService {
    // MARK: - Singleton

    public static let shared = SupabaseAvatarService()

    // MARK: - Properties

    private var client: SupabaseClient { SupabaseConfig.client }
    private var bucketName: String { SupabaseConfig.avatarBucket }
    private let logger = Logger(
        subsystem: "com.supabasekit",
        category: "SupabaseAvatarService"
    )

    // 图片压缩配置
    private let targetSize: CGSize = CGSize(width: 512, height: 512)
    private let compressionQuality: CGFloat = 0.75
    private let maxFileSize: Int = 250_000 // 250KB

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 上传头像到 Supabase Storage
    public func uploadAvatar(_ image: UIImage) async throws -> String {
        logger.info("开始上传头像到 Supabase Storage...")

        guard let session = try? await client.auth.session else {
            throw SupabaseAvatarError.userNotAuthenticated
        }
        let userId = session.user.id

        guard let compressedData = compressImage(image) else {
            logger.error("图片压缩失败")
            throw SupabaseAvatarError.compressionFailed
        }

        logger.debug("图片压缩完成，大小: \(compressedData.count / 1024) KB")

        let filePath = "\(userId.uuidString)/avatar.jpg"

        do {
            _ = try? await client.storage
                .from(bucketName)
                .remove(paths: [filePath])

            _ = try await client.storage
                .from(bucketName)
                .upload(
                    filePath,
                    data: compressedData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )

            logger.info("头像上传成功到 Supabase Storage")

            let publicURL = try client.storage
                .from(bucketName)
                .getPublicURL(path: filePath)

            logger.debug("头像公开 URL: \(publicURL.absoluteString)")
            return publicURL.absoluteString
        } catch {
            logger.error("上传头像失败: \(error.localizedDescription)")
            throw SupabaseAvatarError.uploadFailed(error)
        }
    }

    /// 删除用户头像
    public func deleteAvatar(for userId: UUID) async throws {
        let filePath = "\(userId.uuidString)/avatar.jpg"

        do {
            try await client.storage
                .from(bucketName)
                .remove(paths: [filePath])

            logger.info("头像删除成功")
        } catch {
            logger.error("删除头像失败: \(error.localizedDescription)")
            throw SupabaseAvatarError.deleteFailed(error)
        }
    }

    /// 获取头像公开 URL
    public func getAvatarURL(for userId: UUID) -> String {
        let filePath = "\(userId.uuidString)/avatar.jpg"

        do {
            let publicURL = try client.storage
                .from(bucketName)
                .getPublicURL(path: filePath)
            return publicURL.absoluteString
        } catch {
            logger.error("获取头像 URL 失败: \(error.localizedDescription)")
            return ""
        }
    }

    // MARK: - Private Methods

    private func compressImage(_ image: UIImage) -> Data? {
        let resizedImage = resizeImage(image, to: targetSize)

        guard var imageData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
            logger.error("无法转换为 JPEG 格式")
            return nil
        }

        var quality = compressionQuality
        while imageData.count > maxFileSize && quality > 0.3 {
            quality -= 0.1
            if let compressedData = resizedImage.jpegData(compressionQuality: quality) {
                imageData = compressedData
            } else {
                break
            }
        }

        logger.debug("最终压缩质量: \(quality), 文件大小: \(imageData.count / 1024) KB")
        return imageData
    }

    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
