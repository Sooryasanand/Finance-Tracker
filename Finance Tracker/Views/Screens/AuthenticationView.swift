import SwiftUI
import LocalAuthentication

struct AuthenticationView: View {
    @StateObject private var authService = BiometricAuthenticationService()
    @State private var showingManualAuth = false
    
    let onAuthenticated: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App Icon/Logo
            VStack(spacing: 16) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Finance Tracker")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Secure access to your financial data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Authentication Section
            VStack(spacing: 20) {
                if authService.isBiometricAvailable {
                    // Biometric Authentication Button
                    Button(action: authenticateWithBiometrics) {
                        HStack(spacing: 12) {
                            Image(systemName: biometricIcon)
                                .font(.title2)
                            
                            Text("Unlock with \(authService.biometricType.displayName)")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    // Alternative Authentication
                    Button("Use Passcode Instead") {
                        showingManualAuth = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                } else {
                    // Passcode Only
                    Button(action: authenticateWithPasscode) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(.title2)
                            
                            Text("Unlock with Passcode")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                }
                
                // Error Message
                if let error = authService.authenticationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Privacy Note
            Text("Your data is protected with device security")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            // Auto-trigger biometric authentication when view appears
            if authService.isBiometricAvailable {
                authenticateWithBiometrics()
            }
        }
        .onChange(of: authService.isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                onAuthenticated()
            }
        }
        .actionSheet(isPresented: $showingManualAuth) {
            ActionSheet(
                title: Text("Choose Authentication Method"),
                buttons: [
                    .default(Text("Use Passcode")) {
                        authenticateWithPasscode()
                    },
                    .default(Text("Use \(authService.biometricType.displayName)")) {
                        authenticateWithBiometrics()
                    },
                    .cancel()
                ]
            )
        }
    }
    
    private var biometricIcon: String {
        switch authService.biometricType {
        case .faceID, .opticID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .none:
            return "lock.fill"
        }
    }
    
    private func authenticateWithBiometrics() {
        Task {
            await authService.authenticateWithBiometrics()
        }
    }
    
    private func authenticateWithPasscode() {
        Task {
            await authService.authenticateWithPasscode()
        }
    }
}

#Preview {
    AuthenticationView {
        print("Authenticated!")
    }
}