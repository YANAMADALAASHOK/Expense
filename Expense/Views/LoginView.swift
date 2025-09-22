import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignup = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "indianrupeesign.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
            
            Text("Expense Tracker")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Track your expenses and investments")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(spacing: 15) {
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.password)
                
                Button(action: signIn) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        Text(isLoading ? "Signing In..." : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundColor(.white)
                    .background(isFormValid ? Color.blue : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(!isFormValid || isLoading)
                
                Button(action: {
                    showingSignup = true
                }) {
                    Text("Don't have an account? Sign Up")
                        .foregroundColor(.blue)
                }
                
                Button(action: {
                    authManager.signInAsGuest()
                }) {
                    HStack {
                        Image(systemName: "person.fill")
                        Text("Continue as Guest")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            
            Text("Guest mode data will only be stored locally")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingSignup) {
            SignupView()
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }
    
    private func signIn() {
        guard isFormValid else { return }
        
        isLoading = true
        
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                }
            }
        }
    }
} 