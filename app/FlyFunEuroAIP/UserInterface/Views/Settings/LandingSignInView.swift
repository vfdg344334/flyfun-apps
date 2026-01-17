import SwiftUI
import AuthenticationServices

/// Full-screen landing sign-in view (mandatory before app access)
/// No dismiss button - user must sign in to continue
struct LandingSignInView: View {
    @Environment(AuthenticationService.self) private var authService
    @State private var showingError = false
    
    // Theme colors - icon uses #7AC4F0 so gradient should blend
    private let skyBlueTop = Color(red: 0.48, green: 0.77, blue: 0.94)     // #7AC4F0 - matches icon
    private let skyBlueBottom = Color(red: 0.40, green: 0.68, blue: 0.88) // Slightly deeper
    
    var body: some View {
        ZStack {
            // Solid sky blue background - exact same color as icon background #7AC4F0
            Color(red: 0.48, green: 0.77, blue: 0.94)
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                signInContent
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
    
    // MARK: - Sign In Content
    
    private var signInContent: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // App logo - sky blue background blends with gradient
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180, height: 180)
            
            // Title and subtitle
            VStack(spacing: 12) {
                Text("FlyFun Aviation")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                
                Text("Your friendly aviation assistant")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            Spacer()
            
            // Sign in button section
            VStack(spacing: 16) {
                SignInWithAppleButton(.continue, onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                }, onCompletion: { result in
                    handleSignInResult(result)
                })
                .signInWithAppleButtonStyle(.black)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                if authService.isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 36)
            
            Spacer()
            
            // Bottom padding
            Spacer()
                .frame(height: 44)
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task {
                do {
                    try await authService.handleAuthorization(authorization)
                } catch {
                    // Error handled by AuthenticationService
                }
            }
        case .failure(let error):
            if let asError = error as? ASAuthorizationError,
               asError.code == .canceled {
                return
            }
        }
    }
}

// MARK: - Decorative Clouds

struct CloudsView: View {
    var body: some View {
        GeometryReader { geometry in
            // Top left cloud - partially off screen
            Image("Cloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180)
                .position(x: 50, y: 80)
            
            // Top right cloud
            Image("Cloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 140)
                .position(x: geometry.size.width - 40, y: 100)
            
            // Middle left cloud
            Image("Cloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160)
                .position(x: 40, y: geometry.size.height * 0.50)
            
            // Middle right cloud
            Image("Cloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150)
                .position(x: geometry.size.width - 30, y: geometry.size.height * 0.55)
            
            // Bottom left cloud - above footer
            Image("Cloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200)
                .position(x: 60, y: geometry.size.height - 150)
            
            // Bottom right cloud - above footer
            Image("Cloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 170)
                .position(x: geometry.size.width - 50, y: geometry.size.height - 130)
        }
    }
}

// MARK: - Preview

#Preview {
    LandingSignInView()
        .environment(AuthenticationService())
}
