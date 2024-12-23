import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @StateObject private var authManager = AuthenticationManager.shared
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
                SignInWithAppleButton { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        Task {
                            do {
                                try await authManager.signInWithApple()
                            } catch {
                                showingError = true
                                errorMessage = error.localizedDescription
                            }
                        }
                    case .failure(let error):
                        showingError = true
                        errorMessage = error.localizedDescription
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                
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
        .alert("Sign In Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
} 