//
//  ExpenseApp.swift
//  Expense
//
//  Created by Ashok Naidu on 20/12/24.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

@main
struct ExpenseApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    let persistenceController = PersistenceController.shared
    
    // PERFORMANCE FIX: Create ExpenseViewModel once at app level
    // This prevents creating multiple instances and multiple Firestore connections
    @StateObject private var viewModel: ExpenseViewModel
    
    init() {
        FirebaseApp.configure()
        
        // NOTE: Firestore now using default persistent cache (optimized with smart batching)
        // Memory-only cache was causing data loss - now using disk-based cache with batching
        print("✅ Firestore configured with optimized persistent cache")
        
        // Initialize viewModel FIRST (before calling any instance methods)
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
        
        // Check for fresh install - if auth token exists but no local data, sign out
        detectFreshInstallAndSignOut()
        
        // Then setup notifications
        setupNotifications()
    }
    
    private func detectFreshInstallAndSignOut() {
        // Check if this is first launch after fresh install
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let isAuthenticated = AuthenticationManager.shared.isAuthenticated
        
        if !hasLaunchedBefore && isAuthenticated {
            // Fresh install but auth token exists (from Keychain)
            print("⚠️ Fresh install detected with existing auth token - forcing sign out")
            Task {
                try? await AuthenticationManager.shared.signOut()
            }
        }
        
        // Mark that we've launched
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView(viewModel: viewModel)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                } else {
                    LoginView()
                }
            }
            .environmentObject(authManager)
            .environmentObject(notificationManager)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // App going to background - sync pending changes
                print("📱 App going to background - syncing pending changes")
                viewModel.forceSyncPendingSaves()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // App became active - optional: sync from cloud
                print("📱 App became active")
            }
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
