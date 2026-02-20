//
//  AuthService.swift
//  SupabaseKit
//

import AuthenticationServices
import Foundation
import OSLog
import Supabase
import UIKit

/// 登出通知名称
extension Notification.Name {
    /// 用户登出时发送的通知，宿主 App 可监听此通知清理缓存
    public static let supabaseKitDidSignOut = Notification.Name("supabaseKitDidSignOut")
}

/// 认证服务
/// 负责管理用户认证状态、Apple 登录、Google 登录、邮箱 OTP 登录、访客模式
@Observable
@MainActor
public final class AuthService {
    // MARK: - Singleton

    public static let shared = AuthService()

    // MARK: - Properties

    private let logger = Logger(
        subsystem: "com.supabasekit",
        category: "AuthService"
    )

    /// 当前认证状态
    public var authState: AuthState = .unknown

    /// Supabase 用户 ID
    public var supabaseUserId: String?

    /// 是否显示登录弹窗（用于延迟登录）
    public var showLoginSheet = false

    /// 登录成功后的回调
    public var onLoginSuccess: (() -> Void)?

    // UserDefaults 键
    private let isGuestModeKey = "com.supabasekit.isGuestMode"

    // MARK: - Initialization

    private init() {
        Task {
            await checkCurrentSession()
        }
    }

    // MARK: - Session Management

    /// 检查当前会话状态
    public func checkCurrentSession() async {
        logger.debug("检查当前会话状态...")

        // 1. 检查是否有访客模式标记
        if UserDefaults.standard.bool(forKey: isGuestModeKey) {
            logger.debug("检测到访客模式")
            authState = .guest
            return
        }

        // 2. 检查 Supabase 会话
        do {
            let session = try await SupabaseConfig.client.auth.session

            // 检查会话是否过期
            if session.isExpired {
                logger.debug("会话已过期，设置为访客模式")
                authState = .guest
                return
            }

            supabaseUserId = session.user.id.uuidString
            authState = .authenticated(userId: session.user.id.uuidString)
            logger.info("已有有效会话: \(session.user.id.uuidString)")
        } catch {
            logger.debug("无有效会话: \(error.localizedDescription)")
            authState = .guest
        }
    }

    // MARK: - Apple Sign In

    /// 使用已有的 Apple 授权登录（从 SignInWithAppleButton 获得）
    public func signInWithAppleAuthorization(_ authorization: ASAuthorization) async throws {
        logger.info("开始处理 Apple 授权...")

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8)
        else {
            throw AuthError.invalidCredential
        }

        logger.debug("获取到 Apple ID Token")

        let session = try await SupabaseConfig.client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idTokenString
            )
        )

        supabaseUserId = session.user.id.uuidString
        authState = .authenticated(userId: session.user.id.uuidString)
        UserDefaults.standard.set(false, forKey: isGuestModeKey)

        logger.info("Apple 登录成功: \(session.user.id.uuidString)")
    }

    // MARK: - Google Sign In

    /// 使用 Google 登录
    public func signInWithGoogle(presentingViewController: UIViewController) async throws {
        logger.info("开始 Google 登录...")

        do {
            let session = try await GoogleSignInService.shared.signIn(
                presentingViewController: presentingViewController
            )

            supabaseUserId = session.user.id.uuidString
            authState = .authenticated(userId: session.user.id.uuidString)
            UserDefaults.standard.set(false, forKey: isGuestModeKey)

            logger.info("Google 登录成功: \(session.user.id.uuidString)")
        } catch {
            logger.error("Google 登录失败: \(error)")
            throw AuthError.signInFailed(error)
        }
    }

    /// 处理 Google 登录回调 URL
    public func handleGoogleSignInURL(_ url: URL) -> Bool {
        return GoogleSignInService.shared.handleOpenURL(url)
    }

    // MARK: - Email OTP

    /// 发送邮箱验证码
    public func requestEmailOTP(email: String) async throws {
        logger.info("请求发送邮箱验证码...")

        do {
            try await OTPService.shared.requestOTP(email: email)
            logger.info("验证码发送成功")
        } catch {
            logger.error("验证码发送失败: \(error)")
            throw AuthError.signInFailed(error)
        }
    }

    /// 验证邮箱验证码并登录
    public func verifyEmailOTP(email: String, otp: String) async throws {
        logger.info("验证邮箱验证码...")

        do {
            let session = try await OTPService.shared.verifyOTP(email: email, token: otp)

            supabaseUserId = session.user.id.uuidString
            authState = .authenticated(userId: session.user.id.uuidString)
            UserDefaults.standard.set(false, forKey: isGuestModeKey)

            logger.info("邮箱验证码登录成功: \(session.user.id.uuidString)")
        } catch {
            logger.error("验证码验证失败: \(error)")
            throw AuthError.signInFailed(error)
        }
    }

    /// 重新发送邮箱验证码
    public func resendEmailOTP() async throws {
        logger.info("重新发送邮箱验证码...")

        do {
            try await OTPService.shared.resendOTP()
            logger.info("验证码重新发送成功")
        } catch {
            logger.error("验证码重新发送失败: \(error)")
            throw AuthError.signInFailed(error)
        }
    }

    // MARK: - Guest Mode

    /// 以访客身份继续
    public func continueAsGuest() {
        logger.info("进入访客模式")
        authState = .guest
        UserDefaults.standard.set(true, forKey: isGuestModeKey)
    }

    // MARK: - Require Login

    /// 检查是否需要登录，如果未登录则弹出登录弹窗
    @discardableResult
    public func requireLogin(onSuccess action: (() -> Void)? = nil) -> Bool {
        if authState.isAuthenticated {
            action?()
            return true
        }

        logger.info("需要登录，显示登录弹窗")
        onLoginSuccess = action
        showLoginSheet = true
        return false
    }

    /// 登录成功后调用，执行回调并关闭弹窗
    public func handleLoginSuccess() {
        logger.info("登录成功，执行回调")
        showLoginSheet = false
        onLoginSuccess?()
        onLoginSuccess = nil
    }

    /// 取消登录弹窗
    public func dismissLoginSheet() {
        showLoginSheet = false
        onLoginSuccess = nil
    }

    // MARK: - Sign Out

    /// 退出登录
    public func signOut() async throws {
        logger.info("退出登录...")

        try await SupabaseConfig.client.auth.signOut()

        // 清除状态
        supabaseUserId = nil
        authState = .unknown

        // 清除访客模式标记
        UserDefaults.standard.set(false, forKey: isGuestModeKey)

        // 清除用户资料缓存
        UserProfileViewModel.shared.clearCache()

        // 发送登出通知，宿主 App 可监听此通知执行额外清理
        NotificationCenter.default.post(name: .supabaseKitDidSignOut, object: nil)

        logger.info("已退出登录")
    }
}

// MARK: - Auth Errors

public enum AuthError: LocalizedError {
    case invalidCredential
    case signInFailed(Error)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "无效的认证凭据"
        case .signInFailed(let error):
            return "登录失败: \(error.localizedDescription)"
        case .notAuthenticated:
            return "用户未登录"
        }
    }
}
