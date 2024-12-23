//
//  ExpenseApp.swift
//  Expense
//
//  Created by Ashok Naidu on 20/12/24.
//

import SwiftUI

@main
struct ExpenseApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                MainTabView(context: persistenceController.container.viewContext)
            } else {
                LoginView()
            }
        }
    }
}
