import SwiftUI
import AuthenticationServices

/// View for Sign in with Apple button and user account display
struct SignInView: View {
    @Environment(AuthenticationService.self) private var authService
    @State private var showingError = false
    
    var body: some View {
        VStack(spacing: 16) {
            if authService.isAuthenticated, let user = authService.currentUser {
                // Signed in state
                authenticatedView(user: user)
            } else {
                // Sign in button
                signInButton
            }
        }
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authService.authError ?? "Unknown error")
        }
        .onChange(of: authService.authError) { _, error in
            if error != nil {
                showingError = true
            }
        }
    }
    
    // MARK: - Sign In Button
    
    private var signInButton: some View {
        VStack(spacing: 12) {
            Text("Sign in to sync your preferences")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            SignInWithAppleButton(.signIn, onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            }, onCompletion: { result in
                handleSignInResult(result)
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .frame(maxWidth: 280)
            .cornerRadius(8)
            .disabled(authService.isLoading)
            
            if authService.isLoading {
                ProgressView()
                    .padding(.top, 8)
            }
        }
        .padding()
    }
    
    // MARK: - Authenticated View
    
    private func authenticatedView(user: AppleUser) -> some View {
        VStack(spacing: 16) {
            // User avatar placeholder
            Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            // User name
            Text(user.displayName)
                .font(.headline)
            
            // Email if available
            if let email = user.email {
                Text(email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Sign out button
            Button(role: .destructive) {
                authService.signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding()
    }
    
    // MARK: - Handle Sign In Result
    
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            handleAuthorization(authorization)
        case .failure(let error):
            // Error handled by AuthenticationService
            print("Sign in failed: \(error.localizedDescription)")
        }
    }
    
    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        
        Task {
            do {
                let _ = try await authService.signInWithApple()
            } catch {
                // Error handled by AuthenticationService
                print("Sign in processing failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Compact Sign In Button (for embedding in other views)

struct CompactSignInButton: View {
    @Environment(AuthenticationService.self) private var authService
    
    var body: some View {
        if authService.isAuthenticated, let user = authService.currentUser {
            // Show user info button
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.accentColor)
                Text(user.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        } else {
            // Show sign in button
            Button {
                Task {
                    do {
                        let _ = try await authService.signInWithApple()
                    } catch {
                        // Error handled by service
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "apple.logo")
                    Text("Sign In")
                        .font(.subheadline.weight(.medium))
                }
            }
            .disabled(authService.isLoading)
        }
    }
}

// MARK: - Preview

#Preview("Signed Out") {
    SignInView()
        .environment(AuthenticationService())
}

#Preview("Signed In") {
    let service = AuthenticationService()
    // Note: Can't easily mock authenticated state in preview
    return SignInView()
        .environment(service)
}
