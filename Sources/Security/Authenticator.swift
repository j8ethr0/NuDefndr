// NuDefndr - nudefndr.com
// Transparency Repository - App Lock authentication and grace rule (v2.6.8)

import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
class Authenticator: ObservableObject {
    @Published var isUnlocked = false
    @Published var canUseBiometrics = false
    @Published var biometryType: LABiometryType = .none
    @Published var authError: Error?
    @Published private(set) var isEvaluating = false
    private var leftUnlockedAt: ContinuousClock.Instant?
    private let gracePeriod: Duration = .seconds(60)
    private var lockGeneration = 0
    private var evaluatingContext: LAContext?

    var isWithinGracePeriod: Bool {
        guard let leftUnlockedAt else { return false }
        return ContinuousClock.now - leftUnlockedAt < gracePeriod
    }

    init() {
        checkPolicy()
        isUnlocked = false
        AppLogger.security.debug("Authenticator initialized with isUnlocked = false (secure default)")
    }

    func checkPolicy() {
        let context = LAContext()
        var error: NSError?
        self.canUseBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        if self.canUseBiometrics {
            self.biometryType = context.biometryType
            AppLogger.security.debug("Biometric policy check: Can evaluate. Type: \(self.biometryType.description, privacy: .public)")
        } else {
            self.biometryType = .none
            AppLogger.security.debug("Biometric policy check: Cannot evaluate")
             if let checkError = error {
                 AppLogger.security.error("Error checking policy: \(checkError.localizedDescription, privacy: .public) (Code: \(checkError.code, privacy: .public))")
                 if checkError.domain == LAErrorDomain && checkError.code == LAError.Code.passcodeNotSet.rawValue {
                      AppLogger.security.warning("Passcode is not set on the device")
                 }
             }
        }
    }

    func authenticate() {
        AppLogger.security.debug("authenticate() called")

        if isUnlocked {
            AppLogger.security.debug("Already unlocked, skipping authentication")
            return
        }

        guard !isEvaluating else {
            AppLogger.security.debug("Authentication already in progress")
            return
        }

        if unlockIfWithinGracePeriod() { return }

        let context = LAContext()
        var errorCheck: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &errorCheck) else {
            AppLogger.security.error("Policy check failed just before evaluation. Authentication not possible/configured")
            isUnlocked = false
             let specificError = errorCheck ?? NSError(domain: LAErrorDomain, code: LAError.Code.biometryNotAvailable.rawValue, userInfo: nil)
            authError = NSError(
                domain: "AuthenticatorError",
                code: specificError.code,
                userInfo: [NSLocalizedDescriptionKey: "Device authentication not possible. Please check FaceID/TouchID/Passcode settings."]
            )
            canUseBiometrics = false
            self.biometryType = context.biometryType
            isEvaluating = false
            return
        }

         self.canUseBiometrics = true
         self.biometryType = context.biometryType
         AppLogger.security.debug("Policy check OK before evaluation. Type: \(self.biometryType.description, privacy: .public)")

        isEvaluating = true
        authError = nil
        evaluatingContext = context
        let generation = lockGeneration
        let reason = String(localized: "APPLOCK_AUTH_REASON", defaultValue: "Please authenticate to access NUDEFNDR.", comment: "Face ID prompt reason when unlocking the app with App Lock")

        BiometricPrompt.evaluate(context, reason: reason) { [weak self] success, authenticationError in
            guard let self else { return }
            self.isEvaluating = false
            if self.evaluatingContext === context { self.evaluatingContext = nil }

            if generation != self.lockGeneration {
                AppLogger.security.info("Authentication ended after Instant Lock - result discarded")
                self.isUnlocked = false
                self.authError = nil
            } else if success {
                AppLogger.security.info("Authentication successful")
                self.isUnlocked = true
                self.authError = nil
            } else {
                AppLogger.security.warning("Authentication failed")
                self.isUnlocked = false
                self.authError = authenticationError ?? LAError(.authenticationFailed)

                if let error = authenticationError as? LAError {
                    AppLogger.security.error("LAError: Code \(error.code.rawValue, privacy: .public) - \(self.errorMessage(for: error.code), privacy: .public)")
                } else if let authenticationError {
                    AppLogger.security.error("Non-LAError during authentication: \(authenticationError.localizedDescription, privacy: .public)")
                } else {
                    AppLogger.security.error("Authentication returned false but authenticationError parameter was nil")
                }
            }
        }
    }

    @discardableResult
    func unlockIfWithinGracePeriod() -> Bool {
        guard !isUnlocked, isWithinGracePeriod, let leftUnlockedAt else { return false }
        let away = ContinuousClock.now - leftUnlockedAt
        AppLogger.security.info("Within grace period (\(away.components.seconds, privacy: .public)s since leaving), auto-unlocking")
        isUnlocked = true
        authError = nil
        self.leftUnlockedAt = nil
        return true
    }

    func lock() {
        if isUnlocked {
            leftUnlockedAt = .now
            AppLogger.security.info("App locked - grace period started")
        }
        isUnlocked = false
        authError = nil
    }

    func panicLock() {
        isUnlocked = false
        authError = nil
        leftUnlockedAt = nil
        lockGeneration &+= 1
        evaluatingContext?.invalidate()
        AppLogger.security.info("Panic lock engaged - grace period voided")
    }

    private func errorMessage(for code: LAError.Code) -> String {
        switch code {
        case .authenticationFailed: return "Authentication failed. Please try again."
        case .userCancel: return "Authentication cancelled."
        case .userFallback: return "Passcode fallback requested."
        case .passcodeNotSet: return "Please set a device passcode to use App Lock."
        case .biometryNotAvailable: return "FaceID / TouchID is not available on this device."
        case .biometryNotEnrolled: return "Please enroll FaceID / TouchID in device Settings."
        case .biometryLockout: return "Too many failed attempts. Please use your passcode or try again later."
        default: return "An unexpected authentication error occurred. (\(code.rawValue))"
        }
    }
}

extension LABiometryType {
    var description: String {
        switch self {
        case .none: return "None"
        case .touchID: return "TouchID"
        case .faceID: return "FaceID"
        case .opticID: return "Optic ID"
        @unknown default: return "Unknown"
        }
    }
}
