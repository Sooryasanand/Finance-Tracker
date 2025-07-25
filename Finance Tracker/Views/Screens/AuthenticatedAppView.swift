import SwiftUI

struct AuthenticatedAppView: View {
    @StateObject private var authService = BiometricAuthenticationService()
    @State private var showingAuthentication = true
    
    var body: some View {
        Group {
            if showingAuthentication && !authService.isAuthenticated {
                AuthenticationView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingAuthentication = false
                    }
                }
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // App entered background - may need to show authentication when returning
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // App entering foreground - check if authentication is needed
            if authService.shouldRequireAuthentication() {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingAuthentication = true
                    authService.logout()
                }
            }
        }
    }
}