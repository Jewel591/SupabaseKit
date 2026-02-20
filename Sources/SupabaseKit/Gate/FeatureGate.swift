//
//  FeatureGate.swift
//  SupabaseKit
//

import Foundation

/// 功能访问控制
/// 提供基于认证状态的功能门控
public enum FeatureGate {
    /// 检查当前是否为访客模式
    public static var isGuestMode: Bool {
        AuthService.shared.authState.isGuest
    }

    /// 检查当前是否已登录
    public static var isAuthenticated: Bool {
        AuthService.shared.authState.isAuthenticated
    }

    /// 需要登录才能执行的操作
    /// - Parameters:
    ///   - action: 登录成功后执行的操作
    /// - Returns: 如果已登录返回 true
    @discardableResult
    public static func requireLogin(onSuccess action: (() -> Void)? = nil) -> Bool {
        return AuthService.shared.requireLogin(onSuccess: action)
    }
}
