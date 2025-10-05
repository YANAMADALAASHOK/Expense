import SwiftUI

struct UserProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var mobileNumber = ""
    @State private var dateOfBirth = Date()
    @State private var isEditing = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    VStack(spacing: 16) {
                        // Profile Picture
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 120, height: 120)
                            
                            Text(initials)
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(spacing: 4) {
                            Text(authManager.currentUser?.fullName ?? "User")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(authManager.currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top)
                    
                    // Profile Information
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Profile Information")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 16) {
                            if isEditing {
                                // Editable Fields
                                ProfileEditField(title: "First Name", text: $firstName)
                                ProfileEditField(title: "Last Name", text: $lastName)
                                ProfileEditField(title: "Mobile Number", text: $mobileNumber)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Date of Birth")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            } else {
                                // Display Fields
                                ProfileDisplayField(title: "First Name", value: authManager.currentUser?.firstName ?? "Not set")
                                ProfileDisplayField(title: "Last Name", value: authManager.currentUser?.lastName ?? "Not set")
                                ProfileDisplayField(title: "Mobile Number", value: authManager.currentUser?.mobileNumber ?? "Not set")
                                ProfileDisplayField(title: "Date of Birth", value: formatDate(authManager.currentUser?.dateOfBirth))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        if isEditing {
                            Button(action: saveProfile) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .foregroundColor(.white)
                                    }
                                    Text(isLoading ? "Saving..." : "Save Changes")
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            .disabled(isLoading)
                            
                            Button(action: cancelEditing) {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .foregroundColor(.blue)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                        } else {
                            Button(action: startEditing) {
                                Text("Edit Profile")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .foregroundColor(.white)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                        
                        if !(authManager.currentUser?.isGuest ?? true) {
                            Button(action: {
                                authManager.signOut()
                                dismiss()
                            }) {
                                Text("Sign Out")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .foregroundColor(.red)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
        .onAppear {
            loadUserData()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var initials: String {
        let first = authManager.currentUser?.firstName?.first?.uppercased() ?? ""
        let last = authManager.currentUser?.lastName?.first?.uppercased() ?? ""
        return first + last
    }
    
    private func loadUserData() {
        guard let user = authManager.currentUser else { return }
        firstName = user.firstName ?? ""
        lastName = user.lastName ?? ""
        mobileNumber = user.mobileNumber ?? ""
        dateOfBirth = user.dateOfBirth ?? Date()
    }
    
    private func startEditing() {
        isEditing = true
        loadUserData()
    }
    
    private func cancelEditing() {
        isEditing = false
        loadUserData()
    }
    
    private func saveProfile() {
        print("DEBUG: 💾 UserProfileView.saveProfile() called")
        
        guard !(authManager.currentUser?.isGuest ?? true) else {
            print("DEBUG: ❌ User is guest, cannot save profile")
            return
        }
        
        print("DEBUG: 📋 Profile data to save:")
        print("DEBUG:    First Name: \(firstName)")
        print("DEBUG:    Last Name: \(lastName)")
        print("DEBUG:    Mobile: \(mobileNumber)")
        print("DEBUG:    DOB: \(dateOfBirth)")
        
        isLoading = true
        
        Task {
            do {
                print("DEBUG: 🚀 Calling authManager.updateUserProfile...")
                try await authManager.updateUserProfile(
                    firstName: firstName,
                    lastName: lastName,
                    mobileNumber: mobileNumber,
                    dateOfBirth: dateOfBirth
                )
                
                print("DEBUG: ✅ Profile save completed successfully")
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isEditing = false
                    print("DEBUG: ✅ UI updated - editing mode disabled")
                }
            } catch {
                print("DEBUG: ❌ Profile save failed with error: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    print("DEBUG: ❌ Showing error to user: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Not set" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

struct ProfileDisplayField: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ProfileEditField: View {
    let title: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextField(title, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    UserProfileView()
        .environmentObject(AuthenticationManager.shared)
}
