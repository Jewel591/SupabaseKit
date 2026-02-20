//
//  GoogleSignInService.swift
//  SupabaseKit
//
//  Google 社交登录服务
//

import Foundation
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import Supabase
import OSLog

/// Google 登录错误类型
public enum GoogleSignInError: LocalizedError {
    case userCancelled
    case noIdToken
    case networkError(Error)
    case invalidConfiguration
    case supabaseExchangeFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "登录已取消"
        case .noIdToken:
            return "无法获取认证信息"
        case .networkError(let error):
            return "网络连接失败: \(error.localizedDescription)"
        case .invalidConfiguration:
            return "Google 登录配置错误"
        case .supabaseExchangeFailed(let error):
            return "账号关联失败: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .userCancelled:
            return "请重新尝试登录"
        case .noIdToken, .invalidConfiguration:
            return "请联系客服支持"
        case .networkError:
            return "请检查网络连接后重试"
        case .supabaseExchangeFailed:
            return "请稍后重试或使用其他登录方式"
        }
    }
}

/// Google 登录服务
@MainActor
@Observable
public final class GoogleSignInService {

    // MARK: - Properties

    public static let shared = GoogleSignInService()

    private let logger = Logger(
        subsystem: "com.supabasekit",
        category: "GoogleSignIn"
    )

    /// 登录状态
    public private(set) var isSigningIn = false

    /// 错误信息
    public private(set) var error: GoogleSignInError?

    // MARK: - Initialization

    private init() {
        configureGoogleSignIn()
    }

    // MARK: - Configuration

    private func configureGoogleSignIn() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            logger.error("无法加载 GoogleService-Info.plist")
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        logger.info("Google Sign-In 配置成功")
    }

    // MARK: - Public Methods

    /// 执行 Google 登录
    @discardableResult
    public func signIn(presentingViewController: UIViewController) async throws -> Session {
        error = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            logger.info("开始 Google 登录流程")

            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController
            )

            guard let idToken = result.user.idToken?.tokenString else {
                logger.error("无法获取 Google ID Token")
                throw GoogleSignInError.noIdToken
            }

            let user = result.user
            let profile = user.profile

            logger.info("Google 登录成功，用户: \(profile?.email ?? "未知")")

            let session = try await exchangeGoogleTokenForSupabase(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                userInfo: GoogleUserInfo(
                    email: profile?.email,
                    name: profile?.name,
                    givenName: profile?.givenName,
                    familyName: profile?.familyName,
                    imageUrl: profile?.imageURL(withDimension: 512)?.absoluteString
                )
            )

            logger.info("成功创建 Supabase 会话")
            return session

        } catch let error as NSError where error.domain == "com.google.GIDSignIn" {
            let GIDSignInErrorCanceled = -5
            if error.code == GIDSignInErrorCanceled {
                logger.info("用户取消了 Google 登录")
                self.error = .userCancelled
                throw GoogleSignInError.userCancelled
            } else {
                logger.error("Google 登录失败: \(error)")
                self.error = .networkError(error)
                throw GoogleSignInError.networkError(error)
            }
        } catch let error as GoogleSignInError {
            self.error = error
            throw error
        } catch {
            logger.error("未知错误: \(error)")
            self.error = .networkError(error)
            throw GoogleSignInError.networkError(error)
        }
    }

    /// 处理应用 URL 回调
    public func handleOpenURL(_ url: URL) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    /// 恢复之前的登录状态
    public func restorePreviousSignIn() async throws {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            logger.info("恢复 Google 登录成功: \(user.profile?.email ?? "未知")")
        } catch {
            logger.info("没有之前的 Google 登录状态")
            throw error
        }
    }

    /// 退出 Google 登录
    public func signOut() {
        GIDSignIn.sharedInstance.signOut()
        logger.info("已退出 Google 登录")
    }

    /// 断开 Google 账号连接
    public func disconnect() async throws {
        try await GIDSignIn.sharedInstance.disconnect()
        logger.info("已断开 Google 账号连接")
    }

    // MARK: - Private Methods

    private func exchangeGoogleTokenForSupabase(
        idToken: String,
        accessToken: String,
        userInfo: GoogleUserInfo
    ) async throws -> Session {
        do {
            let session = try await SupabaseConfig.client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )

            if let email = userInfo.email {
                await updateUserProfile(
                    userId: session.user.id,
                    email: email,
                    name: userInfo.name,
                    avatarUrl: userInfo.imageUrl
                )
            }

            return session
        } catch {
            logger.error("Supabase Token 交换失败: \(error)")
            throw GoogleSignInError.supabaseExchangeFailed(error)
        }
    }

    private func updateUserProfile(
        userId: UUID,
        email: String,
        name: String?,
        avatarUrl: String?
    ) async {
        do {
            let existingProfile: UserProfile? = try await SupabaseConfig.client
                .from("profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            if existingProfile == nil {
                let newProfile = UserProfile(
                    userId: userId,
                    displayName: name ?? email.components(separatedBy: "@").first ?? "用户",
                    bio: nil,
                    isPublic: false,
                    createdAt: Date(),
                    avatarURL: avatarUrl
                )

                try await SupabaseConfig.client
                    .from("profiles")
                    .insert(newProfile)
                    .execute()

                logger.info("创建新用户资料成功")
            } else {
                logger.info("用户资料已存在，跳过创建")
            }
        } catch {
            logger.error("更新用户资料失败: \(error)")
        }
    }
}

// MARK: - Supporting Types

struct GoogleUserInfo {
    let email: String?
    let name: String?
    let givenName: String?
    let familyName: String?
    let imageUrl: String?
}
