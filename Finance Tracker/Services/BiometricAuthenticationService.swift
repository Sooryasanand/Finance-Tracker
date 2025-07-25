import LocalAuthentication
import Foundation

class BiometricAuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authenticationError: String?
    
    enum BiometricType {
        case none
        case touchID
        case faceID
        case opticID
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .opticID: return "Optic ID"
            }
        }
    }
    
    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        switch context.biometryType {
        case .none:
            return .none
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        @unknown default:
            return .none
        }
    }
    
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func authenticateWithBiometrics(reason: String = "Authenticate to access your financial data") async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            await MainActor.run {
                self.authenticationError = error?.localizedDescription ?? "Biometric authentication not available"
            }
            return false
        }
        
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            await MainActor.run {
                self.isAuthenticated = success
                self.authenticationError = nil
            }
            return success
        } catch {
            await MainActor.run {
                self.authenticationError = error.localizedDescription
                self.isAuthenticated = false
            }
            return false
        }
    }
    
    func authenticateWithPasscode(reason: String = "Authenticate to access your financial data") async -> Bool {
        let context = LAContext()
        
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            await MainActor.run {
                self.isAuthenticated = success
                self.authenticationError = nil
            }
            return success
        } catch {
            await MainActor.run {
                self.authenticationError = error.localizedDescription
                self.isAuthenticated = false
            }
            return false
        }
    }
    
    func logout() {
        isAuthenticated = false
        authenticationError = nil
    }
    
    // Check if app should require authentication (e.g., after app becomes inactive)
    func shouldRequireAuthentication() -> Bool {
        // You can implement logic here to determine if authentication is required
        // For example, check if app was backgrounded for more than X minutes
        return !isAuthenticated
    }
}