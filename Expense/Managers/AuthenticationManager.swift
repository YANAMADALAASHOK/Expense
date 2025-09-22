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
        let firstName: String?
        let lastName: String?
        let mobileNumber: String?
        let dateOfBirth: Date?
        let isGuest: Bool
        
        var fullName: String {
            let first = firstName ?? ""
            let last = lastName ?? ""
            return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        }
        
        // Legacy name property for backward compatibility
        var name: String? {
            return fullName.isEmpty ? nil : fullName
        }
    }
    
    private init() {
        // Check if user is already signed in
        if let user = Auth.auth().currentUser {
            self.isAuthenticated = true
            // Load user profile from Firestore
            loadUserProfile(userId: user.uid) { userProfile in
                DispatchQueue.main.async {
                    self.currentUser = userProfile ?? User(
                        id: user.uid,
                        email: user.email,
                        firstName: user.displayName,
                        lastName: nil,
                        mobileNumber: nil,
                        dateOfBirth: nil,
                        isGuest: false
                    )
                }
            }
        }
        
        // Listen for auth state changes
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] (_, user) in
            DispatchQueue.main.async {
                if let firebaseUser = user {
                    self?.isAuthenticated = true
                    // Load user profile from Firestore
                    self?.loadUserProfile(userId: firebaseUser.uid) { userProfile in
                        DispatchQueue.main.async {
                            self?.currentUser = userProfile ?? User(
                                id: firebaseUser.uid,
                                email: firebaseUser.email,
                                firstName: firebaseUser.displayName,
                                lastName: nil,
                                mobileNumber: nil,
                                dateOfBirth: nil,
                                isGuest: false
                            )
                        }
                    }
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
                // Load user profile from Firestore
                self.loadUserProfile(userId: result.user.uid) { userProfile in
                    DispatchQueue.main.async {
                        self.currentUser = userProfile ?? User(
                            id: result.user.uid,
                            email: result.user.email,
                            firstName: result.user.displayName,
                            lastName: nil,
                            mobileNumber: nil,
                            dateOfBirth: nil,
                            isGuest: false
                        )
                    }
                }
            }
        } catch {
            throw error
        }
    }
    
    func createAccount(email: String, password: String, firstName: String, lastName: String, mobileNumber: String, dateOfBirth: Date) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            let newUser = User(
                id: result.user.uid,
                email: result.user.email,
                firstName: firstName,
                lastName: lastName,
                mobileNumber: mobileNumber,
                dateOfBirth: dateOfBirth,
                isGuest: false
            )
            
            // Save user profile to Firestore
            try await saveUserProfile(user: newUser)
            
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.currentUser = newUser
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
                firstName: "Guest",
                lastName: nil,
                mobileNumber: nil,
                dateOfBirth: nil,
                isGuest: true
            )
        }
    }
    
    // MARK: - Firestore Methods
    
    private func saveUserProfile(user: User) async throws {
        let userData: [String: Any] = [
            "email": user.email ?? "",
            "firstName": user.firstName ?? "",
            "lastName": user.lastName ?? "",
            "mobileNumber": user.mobileNumber ?? "",
            "dateOfBirth": user.dateOfBirth ?? Date(),
            "createdAt": Date(),
            "updatedAt": Date()
        ]
        
        try await db.collection("users").document(user.id).setData(userData)
    }
    
    private func loadUserProfile(userId: String, completion: @escaping (User?) -> Void) {
        db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                print("Error loading user profile: \(error)")
                completion(nil)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data() else {
                completion(nil)
                return
            }
            
            let user = User(
                id: userId,
                email: data["email"] as? String,
                firstName: data["firstName"] as? String,
                lastName: data["lastName"] as? String,
                mobileNumber: data["mobileNumber"] as? String,
                dateOfBirth: (data["dateOfBirth"] as? Timestamp)?.dateValue(),
                isGuest: false
            )
            
            completion(user)
        }
    }
    
    func updateUserProfile(firstName: String, lastName: String, mobileNumber: String, dateOfBirth: Date) async throws {
        guard let currentUser = currentUser, !currentUser.isGuest else {
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let updatedUser = User(
            id: currentUser.id,
            email: currentUser.email,
            firstName: firstName,
            lastName: lastName,
            mobileNumber: mobileNumber,
            dateOfBirth: dateOfBirth,
            isGuest: false
        )
        
        try await saveUserProfile(user: updatedUser)
        
        DispatchQueue.main.async {
            self.currentUser = updatedUser
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