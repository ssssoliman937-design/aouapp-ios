import AOUHubCore
import LocalAuthentication

/// Face ID only. Touch ID devices report `.noHardware`, and the policy is
/// biometrics-only, so the system never offers the passcode instead.
struct FaceIDAuthenticator: BiometricAuthenticator {
    func status() -> BiometricStatus {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        guard context.biometryType == .faceID else { return .noHardware }
        if canEvaluate { return .available }
        switch (error as? LAError)?.code {
        case .biometryNotEnrolled: return .notEnrolled
        case .biometryNotAvailable: return .unavailable
        default: return .unavailable
        }
    }

    func authenticate(reason: String) async -> BiometricOutcome {
        guard status() == .available else { return outcomeForStatus() }
        let context = LAContext()
        context.localizedFallbackTitle = "" // hides "Enter Password"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return ok ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: return .cancelled
            case .biometryLockout: return .lockout
            case .biometryNotEnrolled: return .notEnrolled
            case .biometryNotAvailable: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    private func outcomeForStatus() -> BiometricOutcome {
        status() == .notEnrolled ? .notEnrolled : .unavailable
    }
}
