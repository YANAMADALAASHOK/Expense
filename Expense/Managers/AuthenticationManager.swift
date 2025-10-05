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
            loadUserProfile(userId: user.uid) { [weak self] userProfile in
                DispatchQueue.main.async {
                    if let profile = userProfile {
                        self?.currentUser = profile
                    } else {
                        // Fallback to UserDefaults if Firestore fails
                        print("DEBUG: Firestore profile not found, loading from UserDefaults...")
                        self?.currentUser = self?.loadUserProfileLocally(userId: user.uid, email: user.email) ?? User(
                            id: user.uid,
                            email: user.email,
                            firstName: user.displayName,
                            lastName: nil,
                            mobileNumber: nil,
                            dateOfBirth: nil,
                            isGuest: false
                        )
                        if self?.currentUser?.firstName != nil {
                            print("DEBUG: Successfully loaded profile from UserDefaults")
                        }
                    }
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
                            if let profile = userProfile {
                                self?.currentUser = profile
                            } else {
                                // Fallback to UserDefaults if Firestore fails
                                print("DEBUG: Firestore profile not found, loading from UserDefaults...")
                                self?.currentUser = self?.loadUserProfileLocally(userId: firebaseUser.uid, email: firebaseUser.email) ?? User(
                                    id: firebaseUser.uid,
                                    email: firebaseUser.email,
                                    firstName: firebaseUser.displayName,
                                    lastName: nil,
                                    mobileNumber: nil,
                                    dateOfBirth: nil,
                                    isGuest: false
                                )
                                if self?.currentUser?.firstName != nil {
                                    print("DEBUG: Successfully loaded profile from UserDefaults")
                                }
                            }
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
            
            // Save user profile to Firestore and locally
            try await saveUserProfile(user: newUser)
            saveUserProfileLocally(user: newUser)
            
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
                // Clear local profile data
                self.clearUserProfileLocally()
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
        print("DEBUG: 💾 Saving profile to Firestore...")
        print("DEBUG:    User ID: \(user.id)")
        print("DEBUG:    First Name: \(user.firstName ?? "nil")")
        print("DEBUG:    Last Name: \(user.lastName ?? "nil")")
        print("DEBUG:    DOB: \(user.dateOfBirth?.description ?? "nil")")
        
        let userData: [String: Any] = [
            "email": user.email ?? "",
            "firstName": user.firstName ?? "",
            "lastName": user.lastName ?? "",
            "mobileNumber": user.mobileNumber ?? "",
            "dateOfBirth": user.dateOfBirth ?? Date(),
            "createdAt": Date(),
            "updatedAt": Date()
        ]
        
        do {
            // CRITICAL: Use merge:true to preserve expense data!
            try await db.collection("users").document(user.id).setData(userData, merge: true)
            print("DEBUG: ✅ Successfully saved profile to Firestore (expense data preserved)")
        } catch {
            print("DEBUG: ❌ Failed to save profile to Firestore: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func loadUserProfile(userId: String, completion: @escaping (User?) -> Void) {
        db.collection("users").document(userId).getDocument { [weak self] document, error in
            if let error = error {
                print("Error loading user profile from Firestore: \(error)")
                // Try loading from local backup
                if let localUser = self?.loadUserProfileLocally(userId: userId, email: nil) {
                    print("DEBUG: Loaded profile from local backup")
                    completion(localUser)
                } else {
                    completion(nil)
                }
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data() else {
                print("DEBUG: No Firestore profile found, trying local backup")
                // Try loading from local backup
                if let localUser = self?.loadUserProfileLocally(userId: userId, email: nil) {
                    print("DEBUG: Loaded profile from local backup")
                    completion(localUser)
                } else {
                    completion(nil)
                }
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
            
            // Only save to local backup if profile has valid data
            // This prevents overwriting good backup with empty Firestore data
            if user.firstName != nil && user.dateOfBirth != nil {
                self?.saveUserProfileLocally(user: user)
                print("DEBUG: Loaded profile from Firestore - Name: \(user.firstName ?? "nil"), DOB: \(user.dateOfBirth?.description ?? "nil")")
                print("DEBUG: Saved valid profile to local backup")
                completion(user)
            } else {
                print("DEBUG: Firestore profile incomplete (Name: \(user.firstName ?? "nil"), DOB: \(user.dateOfBirth?.description ?? "nil"))")
                print("DEBUG: Loading from UserDefaults backup instead...")
                // Try loading from local backup instead of using incomplete Firestore data
                if let localUser = self?.loadUserProfileLocally(userId: userId, email: data["email"] as? String) {
                    print("DEBUG: Successfully loaded complete profile from UserDefaults")
                    completion(localUser)
                } else {
                    print("DEBUG: No valid backup found, using incomplete profile")
                    completion(user)
                }
            }
        }
    }
    
    func updateUserProfile(firstName: String, lastName: String, mobileNumber: String, dateOfBirth: Date) async throws {
        print("DEBUG: 📝 updateUserProfile called")
        print("DEBUG:    First Name: \(firstName)")
        print("DEBUG:    Last Name: \(lastName)")
        print("DEBUG:    Mobile: \(mobileNumber)")
        print("DEBUG:    DOB: \(dateOfBirth)")
        
        guard let currentUser = currentUser, !currentUser.isGuest else {
            print("DEBUG: ❌ No authenticated user or user is guest")
            throw NSError(domain: "AuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        print("DEBUG: ✅ Current user verified: \(currentUser.id)")
        
        let updatedUser = User(
            id: currentUser.id,
            email: currentUser.email,
            firstName: firstName,
            lastName: lastName,
            mobileNumber: mobileNumber,
            dateOfBirth: dateOfBirth,
            isGuest: false
        )
        
        // Save to Firestore
        print("DEBUG: 📤 Attempting to save to Firestore...")
        do {
            try await saveUserProfile(user: updatedUser)
            print("DEBUG: ✅ Firestore save successful")
        } catch {
            print("DEBUG: ❌ Firestore save failed: \(error)")
            // Continue to save locally even if Firestore fails
        }
        
        // Also save to UserDefaults as backup
        print("DEBUG: 💾 Saving to UserDefaults backup...")
        saveUserProfileLocally(user: updatedUser)
        
        DispatchQueue.main.async {
            self.currentUser = updatedUser
            print("DEBUG: ✅ Current user updated in memory")
        }
        
        print("DEBUG: 🎉 Profile update complete - Name: \(firstName), DOB: \(dateOfBirth)")
    }
    
    // MARK: - Local Storage (UserDefaults Backup)
    
    private func saveUserProfileLocally(user: User) {
        let defaults = UserDefaults.standard
        defaults.set(user.firstName, forKey: "user_firstName")
        defaults.set(user.lastName, forKey: "user_lastName")
        defaults.set(user.mobileNumber, forKey: "user_mobileNumber")
        defaults.set(user.dateOfBirth, forKey: "user_dateOfBirth")
        defaults.set(user.email, forKey: "user_email")
        defaults.synchronize()
        print("DEBUG: Profile saved locally to UserDefaults")
    }
    
    private func loadUserProfileLocally(userId: String, email: String?) -> User? {
        let defaults = UserDefaults.standard
        guard let firstName = defaults.string(forKey: "user_firstName") else {
            return nil
        }
        
        return User(
            id: userId,
            email: email ?? defaults.string(forKey: "user_email"),
            firstName: firstName,
            lastName: defaults.string(forKey: "user_lastName"),
            mobileNumber: defaults.string(forKey: "user_mobileNumber"),
            dateOfBirth: defaults.object(forKey: "user_dateOfBirth") as? Date,
            isGuest: false
        )
    }
    
    private func clearUserProfileLocally() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "user_firstName")
        defaults.removeObject(forKey: "user_lastName")
        defaults.removeObject(forKey: "user_mobileNumber")
        defaults.removeObject(forKey: "user_dateOfBirth")
        defaults.removeObject(forKey: "user_email")
        defaults.synchronize()
        print("DEBUG: Cleared local profile data")
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