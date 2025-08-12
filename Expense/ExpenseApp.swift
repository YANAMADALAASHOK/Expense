//
//  ExpenseApp.swift
//  Expense
//
//  Created by Ashok Naidu on 20/12/24.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import UserNotifications

@main
struct ExpenseApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    let persistenceController = PersistenceController.shared
    
    init() {
        FirebaseApp.configure()
        setupNotifications()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView(context: persistenceController.container.viewContext)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                } else {
                    LoginView()
                }
            }
            .environmentObject(authManager)
            .environmentObject(notificationManager)
        }
    }
    
    private func setupNotifications() {
        // Setup notification actions first
        NotificationManager.shared.setupNotificationActions()
        
        // Request notification permissions
        Task {
            await NotificationManager.shared.requestNotificationPermission()
        }
    }
}
