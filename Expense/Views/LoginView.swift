import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
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
                
                Button(action: {
                    Task {
                        do {
                            if isSignUp {
                                try await authManager.createAccount(email: email, password: password)
                            } else {
                                try await authManager.signIn(email: email, password: password)
                            }
                        } catch {
                            showingError = true
                            errorMessage = error.localizedDescription
                        }
                    }
                }) {
                    Text(isSignUp ? "Sign Up" : "Sign In")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    isSignUp.toggle()
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
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
    }
} 