//
//  UserProfile.swift
//  SupabaseKit
//

import Foundation

// MARK: - User Profile

/// 用户公开资料
/// 存储在 Supabase 中，用于社交功能
public struct UserProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { userId }

    /// 用户唯一标识（Supabase Auth User ID）
    public let userId: UUID

    /// 用户昵称
    public var displayName: String

    /// 个人简介
    public var bio: String?

    /// 是否公开所有记录到发现页
    public var isPublic: Bool

    /// 创建时间
    public let createdAt: Date

    /// 头像 URL（Supabase Storage 公开 URL）
    public var avatarURL: String?

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case userId
        case displayName
        case bio
        case isPublic
        case createdAt
        case avatarURL
    }

    // MARK: - Initialization

    public init(
        userId: UUID,
        displayName: String,
        bio: String? = nil,
        isPublic: Bool = true,
        createdAt: Date = Date(),
        avatarURL: String? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.bio = bio
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.avatarURL = avatarURL
    }
}

// MARK: - Display Properties

extension UserProfile {
    public var displayBio: String {
        bio ?? ""
    }

    /// 是否有自定义头像
    public var hasAvatar: Bool {
        avatarURL != nil && !avatarURL!.isEmpty
    }

    /// 获取用户名首字母（用于默认头像）
    public var initials: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "U"
        }

        // 获取第一个字符
        let firstChar = String(name.prefix(1)).uppercased()
        return firstChar
    }
}
