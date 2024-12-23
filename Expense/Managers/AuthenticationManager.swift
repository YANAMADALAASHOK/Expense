import SwiftUI
import AuthenticationServices

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @AppStorage("userId") private var userId: String?
    @AppStorage("userEmail") private var userEmail: String?
    @AppStorage("userName") private var userName: String?
    @AppStorage("isGuestMode") private var isGuestMode: Bool = false
    
    init() {
        checkAuthenticationState()
    }
    
    struct User {
        let id: String
        let email: String?
        let name: String?
        let isGuest: Bool
    }
    
    func signInAsGuest() {
        let guestId = UUID().uuidString
        self.userId = guestId
        self.userName = "Guest"
        self.isGuestMode = true
        self.currentUser = User(id: guestId, email: nil, name: "Guest", isGuest: true)
        self.isAuthenticated = true
    }
    
    func signInWithApple() async throws {
        print("Starting Apple Sign In...")
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        
        print("Creating authorization controller...")
        let result = try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = SignInDelegate(continuation: continuation)
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            print("Performing authorization request...")
            controller.performRequests()
        }
        
        print("Authorization completed, processing credential...")
        guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential else {
            print("Invalid credential received")
            throw AuthError.invalidCredential
        }
        
        print("Processing user data...")
        let userId = appleIDCredential.user
        let email = appleIDCredential.email ?? userEmail
        let name = [
            appleIDCredential.fullName?.givenName,
            appleIDCredential.fullName?.familyName
        ].compactMap { $0 }.joined(separator: " ")
        
        print("Saving user data...")
        self.userId = userId
        self.userEmail = email
        self.userName = name.isEmpty ? userName : name
        
        self.currentUser = User(id: userId, email: email, name: self.userName, isGuest: false)
        self.isAuthenticated = true
        
        print("Sign in completed successfully")
        PersistenceController.shared.backupData()
    }
    
    func signOut() {
        PersistenceController.shared.backupData()
        
        userId = nil
        userEmail = nil
        userName = nil
        isGuestMode = false
        currentUser = nil
        isAuthenticated = false
    }
    
    func checkAuthenticationState() {
        if isGuestMode, let userId = userId {
            currentUser = User(id: userId, email: nil, name: "Guest", isGuest: true)
            isAuthenticated = true
        } else if let userId = userId {
            currentUser = User(id: userId, email: userEmail, name: userName, isGuest: false)
            isAuthenticated = true
        } else {
            isAuthenticated = false
        }
    }
}

// MARK: - Supporting Types
enum AuthError: Error {
    case invalidCredential
    case signInFailed
    case noUserData
}

private class SignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let continuation: CheckedContinuation<ASAuthorization, Error>
    
    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window found")
        }
        return window
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization)
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
} 