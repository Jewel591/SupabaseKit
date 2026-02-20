//
//  AuthState.swift
//  SupabaseKit
//

import Foundation

/// 认证状态枚举
public enum AuthState: Equatable, Sendable {
    /// 初始状态，正在检查会话
    case unknown
    /// 访客模式，未登录
    case guest
    /// 已认证，包含 Supabase 用户 ID
    case authenticated(userId: String)

    /// 是否已登录（非访客）
    public var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    /// 是否为访客模式
    public var isGuest: Bool {
        self == .guest
    }

    /// 获取用户 ID（仅在已认证时有值）
    public var userId: String? {
        if case .authenticated(let userId) = self {
            return userId
        }
        return nil
    }
}
