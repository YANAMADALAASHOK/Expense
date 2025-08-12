import Foundation
import FirebaseAuth
import FirebaseFirestore

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    private let db = Firestore.firestore()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    struct User {
        let id: String
        let email: String?
        let name: String?
        let isGuest: Bool
    }
    
    private init() {
        // Check if user is already signed in
        if let user = Auth.auth().currentUser {
            self.isAuthenticated = true
            self.currentUser = User(
                id: user.uid,
                email: user.email,
                name: user.displayName,
                isGuest: false
            )
        }
        
        // Listen for auth state changes
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] (_, user) in
            DispatchQueue.main.async {
                if let firebaseUser = user {
                    self?.isAuthenticated = true
                    self?.currentUser = User(
                        id: firebaseUser.uid,
                        email: firebaseUser.email,
                        name: firebaseUser.displayName,
                        isGuest: false
                    )
                } else {
                    self?.isAuthenticated = false
                    self?.currentUser = nil
                }
            }
        }
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.currentUser = User(
                    id: result.user.uid,
                    email: result.user.email,
                    name: result.user.displayName,
                    isGuest: false
                )
            }
        } catch {
            throw error
        }
    }
    
    func createAccount(email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.currentUser = User(
                    id: result.user.uid,
                    email: result.user.email,
                    name: result.user.displayName,
                    isGuest: false
                )
            }
        } catch {
            throw error
        }
    }
    
    func signOut() {
        // Sync data before signing out
        if let userId = currentUser?.id, !currentUser!.isGuest {
            NotificationCenter.default.post(name: .syncDataToCloud, object: nil)
        }
        
        do {
            try Auth.auth().signOut()
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.currentUser = nil
                // Clear local data after sign out
                PersistenceController.shared.clearAllData()
            }
        } catch {
            print("Error signing out: \(error)")
        }
    }
    
    func signInAsGuest() {
        DispatchQueue.main.async {
            self.isAuthenticated = true
            self.currentUser = User(
                id: UUID().uuidString,
                email: nil,
                name: "Guest",
                isGuest: true
            )
        }
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

extension Notification.Name {
    static let syncDataToCloud = Notification.Name("syncDataToCloud")
    static let loadDataFromCloud = Notification.Name("loadDataFromCloud")
} 