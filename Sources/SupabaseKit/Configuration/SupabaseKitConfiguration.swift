//
//  SupabaseKitConfiguration.swift
//  SupabaseKit
//
//  Supabase 配置注入，由宿主 App 提供配置参数
//

import Foundation
import Supabase
import OSLog

/// Supabase 配置结构体
/// 项目只需要创建这个结构体的实例并传递给 SupabaseKit
public struct SupabaseKitConfiguration: Sendable {
    /// Supabase 项目 URL
    public let supabaseURL: String
    /// Supabase 匿名密钥
    public let supabaseAnonKey: String
    /// Storage bucket 名称（头像上传用）
    public let avatarBucket: String

    public init(
        supabaseURL: String,
        supabaseAnonKey: String,
        avatarBucket: String = "avatars"
    ) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.avatarBucket = avatarBucket
    }
}

// MARK: - 预设配置

extension SupabaseKitConfiguration {
    /// 开发环境的默认配置
    public static var dev: SupabaseKitConfiguration {
        return SupabaseKitConfiguration(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "dev_example_anon_key",
            avatarBucket: "avatars"
        )
    }
}

// MARK: - Supabase Config (Internal)

/// Supabase 配置管理（内部使用）
/// 替代原来从 Info.plist 读取的方式，改为由宿主 App 注入
public enum SupabaseConfig {

    private static let logger = Logger(
        subsystem: "com.supabasekit",
        category: "SupabaseConfig"
    )

    /// 当前配置
    nonisolated(unsafe) static var currentConfig: SupabaseKitConfiguration?

    /// Supabase 客户端单例
    nonisolated(unsafe) public private(set) static var client: SupabaseClient!

    /// 配置 SupabaseKit
    /// - Parameter config: 配置参数
    public static func configure(config: SupabaseKitConfiguration) {
        currentConfig = config

        guard let url = URL(string: config.supabaseURL) else {
            logger.error("无效的 Supabase URL: \(config.supabaseURL)")
            fatalError("无效的 Supabase URL: \(config.supabaseURL)")
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: config.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    flowType: .pkce
                )
            )
        )

        logger.info("SupabaseKit 配置完成")
    }

    /// 获取头像 bucket 名称
    static var avatarBucket: String {
        currentConfig?.avatarBucket ?? "avatars"
    }
}
