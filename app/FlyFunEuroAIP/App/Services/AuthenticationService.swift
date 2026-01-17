import Foundation
import AuthenticationServices
import OSLog
import Observation

/// Service for handling Sign in with Apple authentication
@MainActor
@Observable
final class AuthenticationService: NSObject {
    
    // MARK: - Observable Properties
    
    private(set) var isAuthenticated = false
    private(set) var currentUser: AppleUser?
    private(set) var authError: String?
    private(set) var isLoading = false
    
    // MARK: - Configuration
    
    private let backendURL: String
    private let logger = Logger(subsystem: "net.ro-z.FlyFunEuroAIP", category: "AuthenticationService")
    
    // Keychain keys
    private let keychainServiceToken = "net.ro-z.FlyFunEuroAIP.authToken"
    private let keychainServiceUser = "net.ro-z.FlyFunEuroAIP.appleUser"
    
    // Continuation for async/await
    private var signInContinuation: CheckedContinuation<AppleUser, Error>?
    
    // MARK: - Initialization
    
    init(backendURL: String = SecretsManager.shared.authURL) {
        self.backendURL = backendURL
        super.init()
        
        // Check for existing session on init
        Task {
            await checkExistingSession()
        }
    }
    
    // MARK: - Public Methods
    
    /// Initiate Sign in with Apple flow
    func signInWithApple() async throws -> AppleUser {
        isLoading = true
        authError = nil
        
        defer { isLoading = false }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    
    /// Handle an existing authorization from SignInWithAppleButton
    /// This is called when using SwiftUI's SignInWithAppleButton which handles the flow itself
    func handleAuthorization(_ authorization: ASAuthorization) async throws {
        isLoading = true
        authError = nil
        
        defer { isLoading = false }
        
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }
        
        let userId = credential.user
        let email = credential.email  // Only provided first time
        let firstName = credential.fullName?.givenName
        let lastName = credential.fullName?.familyName
        
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.missingToken
        }
        
        let authorizationCode: String?
        if let codeData = credential.authorizationCode {
            authorizationCode = String(data: codeData, encoding: .utf8)
        } else {
            authorizationCode = nil
        }
        
        // Create user object
        var user = AppleUser(
            userId: userId,
            email: email,
            firstName: firstName,
            lastName: lastName
        )
        
        // If this is a returning user, try to load stored user data
        if email == nil, let storedData = loadFromKeychain(service: keychainServiceUser, account: "appleUser"),
           let storedUser = try? JSONDecoder().decode(AppleUser.self, from: storedData) {
            user = AppleUser(
                userId: userId,
                email: storedUser.email,
                firstName: storedUser.firstName ?? firstName,
                lastName: storedUser.lastName ?? lastName
            )
        }
        
        logger.info("Apple Sign-In successful for user ID: \(userId)")
        
        // Store user data
        if let userData = try? JSONEncoder().encode(user) {
            saveToKeychain(service: keychainServiceUser, account: "appleUser", data: userData)
        }
        
        // Exchange with backend
        if let code = authorizationCode {
            do {
                try await exchangeTokenWithBackend(
                    identityToken: identityToken,
                    authorizationCode: code,
                    user: user
                )
            } catch {
                logger.warning("Backend token exchange failed: \(error.localizedDescription)")
                // Continue anyway - user is authenticated with Apple
            }
        }
        
        currentUser = user
        isAuthenticated = true
    }
    
    /// Sign out and clear stored credentials
    func signOut() {
        logger.info("Signing out user")
        
        // Clear stored data
        deleteFromKeychain(service: keychainServiceToken, account: "sessionToken")
        deleteFromKeychain(service: keychainServiceUser, account: "appleUser")
        
        currentUser = nil
        isAuthenticated = false
        authError = nil
        
        // Optionally notify backend
        Task {
            await notifyBackendSignOut()
        }
    }
    
    /// Check if user's Apple ID credentials are still valid
    func checkCredentialState() async {
        guard let userId = currentUser?.userId else { return }
        
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userId)
            switch state {
            case .authorized:
                logger.debug("Apple ID credential is valid")
            case .revoked, .notFound:
                logger.warning("Apple ID credential revoked or not found, signing out")
                signOut()
            case .transferred:
                logger.info("Apple ID credential transferred")
            @unknown default:
                break
            }
        } catch {
            logger.error("Failed to check credential state: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Check for existing session on app launch
    private func checkExistingSession() async {
        // Try to load stored user
        if let userData = loadFromKeychain(service: keychainServiceUser, account: "appleUser"),
           let user = try? JSONDecoder().decode(AppleUser.self, from: userData) {
            self.currentUser = user
            self.isAuthenticated = true
            logger.info("Restored existing session for user")
            
            // Verify credential is still valid with Apple
            await checkCredentialState()
        }
    }
    
    /// Exchange Apple authorization code with backend
    private func exchangeTokenWithBackend(
        identityToken: String,
        authorizationCode: String,
        user: AppleUser
    ) async throws {
        guard let url = URL(string: "\(backendURL)/api/auth/apple/token") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode,
            "user": [
                "user_id": user.userId,
                "email": user.email as Any,
                "first_name": user.firstName as Any,
                "last_name": user.lastName as Any
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            logger.error("Backend auth failed with status: \(httpResponse.statusCode)")
            throw AuthError.backendError(httpResponse.statusCode)
        }
        
        // Parse response for session token
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["session_token"] as? String {
            saveToKeychain(service: keychainServiceToken, account: "sessionToken", data: Data(token.utf8))
        }
        
        logger.info("Successfully exchanged token with backend")
    }
    
    /// Notify backend of sign out
    private func notifyBackendSignOut() async {
        guard let url = URL(string: "\(backendURL)/api/auth/logout") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Add session token if available
        if let tokenData = loadFromKeychain(service: keychainServiceToken, account: "sessionToken"),
           let token = String(data: tokenData, encoding: .utf8) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let _ = try await URLSession.shared.data(for: request)
            logger.debug("Backend notified of sign out")
        } catch {
            logger.warning("Failed to notify backend of sign out: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Keychain Helpers
    
    private func saveToKeychain(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.warning("Failed to save to keychain: \(status)")
        }
    }
    
    private func loadFromKeychain(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    private func deleteFromKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationService: ASAuthorizationControllerDelegate {
    
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInContinuation?.resume(throwing: AuthError.invalidCredential)
                signInContinuation = nil
                return
            }
            
            let userId = credential.user
            let email = credential.email  // Only provided first time
            let firstName = credential.fullName?.givenName
            let lastName = credential.fullName?.familyName
            
            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                signInContinuation?.resume(throwing: AuthError.missingToken)
                signInContinuation = nil
                return
            }
            
            let authorizationCode: String?
            if let codeData = credential.authorizationCode {
                authorizationCode = String(data: codeData, encoding: .utf8)
            } else {
                authorizationCode = nil
            }
            
            // Create user object
            var user = AppleUser(
                userId: userId,
                email: email,
                firstName: firstName,
                lastName: lastName
            )
            
            // If this is a returning user, try to load stored user data
            if email == nil, let storedData = loadFromKeychain(service: keychainServiceUser, account: "appleUser"),
               let storedUser = try? JSONDecoder().decode(AppleUser.self, from: storedData) {
                user = AppleUser(
                    userId: userId,
                    email: storedUser.email,
                    firstName: storedUser.firstName ?? firstName,
                    lastName: storedUser.lastName ?? lastName
                )
            }
            
            logger.info("Apple Sign-In successful for user ID: \(userId)")
            
            // Store user data
            if let userData = try? JSONEncoder().encode(user) {
                saveToKeychain(service: keychainServiceUser, account: "appleUser", data: userData)
            }
            
            // Exchange with backend
            if let code = authorizationCode {
                do {
                    try await exchangeTokenWithBackend(
                        identityToken: identityToken,
                        authorizationCode: code,
                        user: user
                    )
                } catch {
                    logger.warning("Backend token exchange failed: \(error.localizedDescription)")
                    // Continue anyway - user is authenticated with Apple
                }
            }
            
            currentUser = user
            isAuthenticated = true
            
            signInContinuation?.resume(returning: user)
            signInContinuation = nil
        }
    }
    
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            logger.error("Apple Sign-In failed: \(error.localizedDescription)")
            
            let asError = error as? ASAuthorizationError
            let errorMessage: String
            
            switch asError?.code {
            case .canceled:
                errorMessage = "Sign in was canceled"
            case .failed:
                errorMessage = "Sign in failed"
            case .invalidResponse:
                errorMessage = "Invalid response from Apple"
            case .notHandled:
                errorMessage = "Sign in not handled"
            case .notInteractive:
                errorMessage = "Sign in requires interaction"
            case .unknown:
                errorMessage = "Unknown error occurred"
            default:
                errorMessage = error.localizedDescription
            }
            
            authError = errorMessage
            signInContinuation?.resume(throwing: AuthError.appleSignInFailed(errorMessage))
            signInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the key window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Supporting Types

/// User data from Apple Sign-In
struct AppleUser: Codable, Equatable {
    let userId: String
    let email: String?
    let firstName: String?
    let lastName: String?
    
    var displayName: String {
        if let first = firstName, let last = lastName {
            return "\(first) \(last)"
        } else if let first = firstName {
            return first
        } else if let email = email {
            return email
        } else {
            return "Apple User"
        }
    }
}

/// Authentication errors
enum AuthError: LocalizedError {
    case invalidCredential
    case missingToken
    case invalidURL
    case invalidResponse
    case backendError(Int)
    case appleSignInFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple credential"
        case .missingToken:
            return "Missing identity token"
        case .invalidURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid backend response"
        case .backendError(let code):
            return "Backend error: \(code)"
        case .appleSignInFailed(let message):
            return message
        }
    }
}
