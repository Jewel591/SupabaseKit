//
//  OTPService.swift
//  SupabaseKit
//
//  邮箱验证码 (OTP) 登录服务
//

import Foundation
import Supabase
import OSLog

/// OTP 错误类型
public enum OTPError: LocalizedError {
    case invalidEmail
    case tooManyAttempts
    case expiredCode
    case invalidCode
    case networkError(Error)
    case rateLimitExceeded

    public var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "邮箱格式无效"
        case .tooManyAttempts:
            return "尝试次数过多，请稍后再试"
        case .expiredCode:
            return "验证码已过期"
        case .invalidCode:
            return "验证码错误"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "请求过于频繁，请稍后再试"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidEmail:
            return "请检查邮箱地址是否正确"
        case .tooManyAttempts:
            return "请等待 5 分钟后重试"
        case .expiredCode:
            return "请重新发送验证码"
        case .invalidCode:
            return "请检查验证码是否输入正确"
        case .networkError:
            return "请检查网络连接"
        case .rateLimitExceeded:
            return "请等待 60 秒后重新发送"
        }
    }
}

/// OTP 登录服务
@MainActor
@Observable
public final class OTPService {

    // MARK: - Properties

    public static let shared = OTPService()

    private let logger = Logger(
        subsystem: "com.supabasekit",
        category: "OTPService"
    )

    /// 用户输入的邮箱
    public var email: String = ""

    /// 用户输入的验证码
    public var otp: String = ""

    /// 是否正在加载
    public var isLoading: Bool = false

    /// 倒计时秒数（0 表示可以重新发送）
    public var countdown: Int = 0

    /// 错误信息
    public var error: OTPError?

    /// 是否显示验证码输入界面
    public var showOTPInput: Bool = false

    /// 倒计时定时器
    private var countdownTimer: Timer?

    /// 倒计时结束时间
    private var countdownEndTime: Date?

    /// 最后发送时间
    private var lastSentTime: Date?

    /// 发送次数
    private var attemptCount: Int = 0

    /// 最后重置时间
    private var lastResetTime: Date = Date()

    // MARK: - Constants

    private let resendInterval: TimeInterval = 60
    private let maxAttemptsPerHour: Int = 10
    private let otpValidityMinutes: Int = 10

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 请求发送 OTP
    public func requestOTP(email: String) async throws {
        error = nil

        guard EmailValidator.isValid(email) else {
            error = .invalidEmail
            throw OTPError.invalidEmail
        }

        try checkRateLimit()

        isLoading = true
        defer { isLoading = false }

        do {
            logger.info("发送 OTP 到邮箱: \(email)")

            try await SupabaseConfig.client.auth.signInWithOTP(
                email: email,
                shouldCreateUser: true
            )

            self.email = email
            showOTPInput = true
            lastSentTime = Date()
            attemptCount += 1
            startCountdown()

            logger.info("OTP 发送成功")
        } catch {
            logger.error("OTP 发送失败: \(error)")
            self.error = .networkError(error)
            throw OTPError.networkError(error)
        }
    }

    /// 验证 OTP
    @discardableResult
    public func verifyOTP(email: String, token: String) async throws -> Session {
        error = nil

        guard !email.isEmpty, !token.isEmpty else {
            error = .invalidCode
            throw OTPError.invalidCode
        }

        guard token.count == 6, token.allSatisfy(\.isNumber) else {
            error = .invalidCode
            throw OTPError.invalidCode
        }

        isLoading = true
        defer { isLoading = false }

        do {
            logger.info("验证 OTP: \(email)")

            let response = try await SupabaseConfig.client.auth.verifyOTP(
                email: email,
                token: token,
                type: .email
            )

            guard let session = response.session else {
                throw OTPError.invalidCode
            }

            self.email = ""
            self.otp = ""
            showOTPInput = false
            stopCountdown()

            logger.info("OTP 验证成功")
            return session
        } catch {
            logger.error("OTP 验证失败: \(error)")

            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("expired") {
                self.error = .expiredCode
                throw OTPError.expiredCode
            } else if errorMessage.contains("invalid") {
                self.error = .invalidCode
                throw OTPError.invalidCode
            } else {
                self.error = .networkError(error)
                throw OTPError.networkError(error)
            }
        }
    }

    /// 重新发送 OTP
    public func resendOTP() async throws {
        guard !email.isEmpty else {
            error = .invalidEmail
            throw OTPError.invalidEmail
        }

        try await requestOTP(email: email)
    }

    /// 重置状态
    public func reset() {
        email = ""
        otp = ""
        showOTPInput = false
        error = nil
        stopCountdown()
        logger.info("OTP 服务已重置")
    }

    // MARK: - Private Methods

    private func checkRateLimit() throws {
        if Date().timeIntervalSince(lastResetTime) > 3600 {
            attemptCount = 0
            lastResetTime = Date()
        }

        if attemptCount >= maxAttemptsPerHour {
            logger.warning("达到每小时发送限制")
            throw OTPError.tooManyAttempts
        }

        if let lastSent = lastSentTime {
            let timeSinceLastSent = Date().timeIntervalSince(lastSent)
            if timeSinceLastSent < resendInterval {
                logger.warning("发送间隔太短: \(timeSinceLastSent)秒")
                throw OTPError.rateLimitExceeded
            }
        }
    }

    private func startCountdown() {
        stopCountdown()
        countdownEndTime = Date().addingTimeInterval(resendInterval)
        countdown = Int(resendInterval)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self,
                      let endTime = self.countdownEndTime else { return }

                let remaining = endTime.timeIntervalSinceNow
                if remaining > 0 {
                    self.countdown = Int(ceil(remaining))
                } else {
                    self.stopCountdown()
                }
            }
        }

        logger.debug("开始倒计时: \(self.countdown)秒")
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownEndTime = nil
        countdown = 0
    }

    /// 格式化倒计时显示
    public var countdownText: String {
        if self.countdown > 0 {
            return "重新发送 (\(self.countdown)秒)"
        } else {
            return "重新发送验证码"
        }
    }

    /// 是否可以重新发送
    public var canResend: Bool {
        countdown == 0 && !isLoading
    }
}

// MARK: - Email Validator

/// 邮箱验证工具
public struct EmailValidator {
    public static func isValid(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    public static func validationError(for email: String) -> String? {
        if email.isEmpty {
            return "请输入邮箱地址"
        }
        if !email.contains("@") {
            return "邮箱地址需要包含 @"
        }
        if !isValid(email) {
            return "请输入有效的邮箱地址"
        }
        return nil
    }
}
