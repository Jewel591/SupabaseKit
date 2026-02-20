//
//  PresetAvatarService.swift
//  SupabaseKit
//
//  预设头像服务 - 从 Supabase Storage 获取预设头像
//

import Foundation
import OSLog
import Supabase

// MARK: - 预设头像模型

public struct PresetAvatar: Identifiable, Sendable {
    public let id: String
    public let type: String
    public let filename: String
    public let url: String

    public init(id: String, type: String, filename: String, url: String) {
        self.id = id
        self.type = type
        self.filename = filename
        self.url = url
    }
}

// MARK: - 预设头像服务

/// 预设头像服务
/// 从 Supabase Storage 的 preset-avatars bucket 获取头像
@MainActor
public final class PresetAvatarService {
    // MARK: - 单例

    public static let shared = PresetAvatarService()

    // MARK: - 配置

    private let bucketName = "preset-avatars"

    private let logger = Logger(
        subsystem: "com.supabasekit",
        category: "PresetAvatarService"
    )

    private var cachedAvatars: [PresetAvatar]?

    // MARK: - 初始化

    private init() {}

    // MARK: - 公共方法

    /// 获取头像完整 URL
    public func getAvatarURL(filename: String) -> String {
        do {
            let url = try SupabaseConfig.client.storage
                .from(bucketName)
                .getPublicURL(path: filename)
            return url.absoluteString
        } catch {
            logger.error("获取头像 URL 失败: \(error.localizedDescription)")
            return ""
        }
    }

    /// 获取所有预设头像
    public func fetchAvatars() async throws -> [PresetAvatar] {
        if let cached = cachedAvatars {
            logger.debug("返回缓存的预设头像列表，共 \(cached.count) 个")
            return cached
        }

        let files = try await SupabaseConfig.client.storage
            .from(bucketName)
            .list()

        let avatars = files
            .filter { $0.name.hasSuffix(".png") }
            .map { file -> PresetAvatar in
                let filename = file.name
                let id = String(filename.dropLast(4))
                let type = parseType(from: filename)
                let url = getAvatarURL(filename: filename)

                return PresetAvatar(
                    id: id,
                    type: type,
                    filename: filename,
                    url: url
                )
            }
            .sorted { $0.id < $1.id }

        cachedAvatars = avatars

        logger.info("成功从 Supabase Storage 加载 \(avatars.count) 个预设头像")
        return avatars
    }

    /// 按类型筛选头像
    public func fetchAvatars(type: PresetAvatarType) async throws -> [PresetAvatar] {
        let allAvatars = try await fetchAvatars()

        guard type != .all else {
            return allAvatars
        }

        let filtered = allAvatars.filter { $0.type == type.rawValue }
        logger.debug("筛选类型 \(type.displayName)，共 \(filtered.count) 个")
        return filtered
    }

    /// 清除缓存
    public func clearCache() {
        cachedAvatars = nil
        logger.debug("缓存已清除")
    }

    // MARK: - 私有方法

    private func parseType(from filename: String) -> String {
        let name = String(filename.dropLast(4))
        let parts = name.split(separator: "-")
        guard parts.count >= 2 else { return "unknown" }
        let typeParts = parts.dropLast()
        return typeParts.joined(separator: "-")
    }
}

// MARK: - 头像类型枚举

public enum PresetAvatarType: String, CaseIterable, Sendable {
    case all = "all"
    case boy = "boy"
    case girl = "girl"
    case man = "man"
    case woman = "woman"
    case oldMan = "old-man"
    case oldWoman = "oldwoman"
    case youngMan = "youngman"
    case cat = "cat"
    case flat = "flat"

    public nonisolated var displayName: String {
        switch self {
        case .all: return "全部"
        case .boy: return "男孩"
        case .girl: return "女孩"
        case .man: return "男性"
        case .woman: return "女性"
        case .oldMan: return "老年男性"
        case .oldWoman: return "老年女性"
        case .youngMan: return "年轻男性"
        case .cat: return "猫咪"
        case .flat: return "扁平风格"
        }
    }
}

// MARK: - 错误类型

public enum PresetAvatarError: LocalizedError {
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
