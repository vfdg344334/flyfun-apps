import SwiftUI
import AuthenticationServices

/// Account view for user sign-in and profile management
/// Similar design to https://flyfun.downle.eu.org/login.html
struct AccountView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.10, blue: 0.20),
                        Color(red: 0.10, green: 0.15, blue: 0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if authService.isAuthenticated, let user = authService.currentUser {
                        // Authenticated state
                        authenticatedContent(user: user)
                    } else {
                        // Sign-in state
                        signInContent
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.title2)
                    }
                }
            }
            .alert("Sign In Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(authService.authError ?? "Unknown error occurred")
            }
            .onChange(of: authService.authError) { _, error in
                if error != nil {
                    showingError = true
                }
            }
        }
    }
    
    // MARK: - Sign In Content
    
    private var signInContent: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App logo/icon
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Title
            VStack(spacing: 8) {
                Text("FlyFun Aviation")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                
                Text("Sign in to continue to your aviation assistant")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // Sign in buttons
            VStack(spacing: 16) {
                // Sign in with Apple
                SignInWithAppleButton(.continue, onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                }, onCompletion: { result in
                    handleSignInResult(result)
                })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .cornerRadius(12)
                
                if authService.isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Terms and Privacy
            VStack(spacing: 8) {
                Text("By continuing, you agree to our")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 4) {
                    Button("Terms of Service") {
                        openURL("https://flyfun.downle.eu.org/terms.html")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                    
                    Text("and")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Button("Privacy Policy") {
                        openURL("https://flyfun.downle.eu.org/privacy.html")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Authenticated Content
    
    private func authenticatedContent(user: AppleUser) -> some View {
        VStack(spacing: 32) {
            Spacer()
            
            // User avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Text(user.initials)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // User info
            VStack(spacing: 8) {
                Text(user.displayName)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                if let email = user.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Account options
            VStack(spacing: 12) {
                // Account info card
                accountInfoCard
                
                // Sign out button
                Button {
                    authService.signOut()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.headline)
                .foregroundColor(.white)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.white.opacity(0.7))
                Text("Signed in with Apple")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Image(systemName: "apple.logo")
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Text("Account verified")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Helper Methods
    
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            Task {
                do {
                    let _ = try await authService.signInWithApple()
                } catch {
                    // Error handled by AuthenticationService
                }
            }
        case .failure(let error):
            if let asError = error as? ASAuthorizationError,
               asError.code == .canceled {
                // User canceled, don't show error
                return
            }
            // Other errors handled by service
        }
    }
    
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}

// MARK: - AppleUser Extensions

extension AppleUser {
    var initials: String {
        var result = ""
        if let first = firstName?.first {
            result.append(first)
        }
        if let last = lastName?.first {
            result.append(last)
        }
        if result.isEmpty, let emailFirst = email?.first {
            result.append(emailFirst)
        }
        return result.uppercased().isEmpty ? "?" : result.uppercased()
    }
}

// MARK: - Account Button (for toolbar/navigation)

struct AccountButton: View {
    @Environment(AuthenticationService.self) private var authService
    @State private var showingAccount = false
    
    var body: some View {
        Button {
            showingAccount = true
        } label: {
            if authService.isAuthenticated, let user = authService.currentUser {
                // Show user avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Text(user.initials)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            } else {
                // Show sign in icon
                Image(systemName: "person.circle")
                    .font(.title2)
            }
        }
        .sheet(isPresented: $showingAccount) {
            AccountView()
        }
    }
}

// MARK: - Preview

#Preview("Signed Out") {
    AccountView()
        .environment(AuthenticationService())
}

#Preview("Account Button") {
    AccountButton()
        .environment(AuthenticationService())
        .padding()
}
