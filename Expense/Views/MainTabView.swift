//
//  ContentView.swift
//  Expense
//
//  Created by Ashok Naidu on 20/12/24.
//

import SwiftUI
import CoreData
import UIKit

struct MainTabView: View {
    @Environment(\.managedObjectContext) var context
    @ObservedObject var viewModel: ExpenseViewModel // CHANGED: Now receives viewModel from parent
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var hasLoadedFromCloud = false
    
    // PERFORMANCE FIX: Removed init that created new ExpenseViewModel
    // Now MainTabView receives viewModel from ExpenseApp (singleton pattern)
    
    var body: some View {
        TabView {
            EnhancedDashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "house")
                }
            
            AccountsView(viewModel: viewModel)
                .tabItem {
                    Label("Accounts", systemImage: "banknote")
                }

            TransactionView(viewModel: viewModel)
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet")
                }
            
            ReportsView(viewModel: viewModel)
                .tabItem {
                    Label("Reports", systemImage: "chart.pie")
                }
            
            BudgetsView(viewModel: viewModel)
                .tabItem {
                    Label("Budgets", systemImage: "creditcard")
                }
            
            PendingTransactionsView(viewModel: viewModel)
                .tabItem {
                    Label("Pending", systemImage: "doc.plaintext")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(viewModel)
        .environmentObject(authManager)
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                viewModel.clearAllData()
            } else if !authManager.currentUser!.isGuest {
                NotificationCenter.default.post(name: .loadDataFromCloud, object: nil)
            }
        }
        .onAppear {
            // Auto-load from cloud on first launch after login (if local data is empty)
            if !hasLoadedFromCloud && viewModel.accounts.isEmpty {
                // Wait a moment for authentication to fully initialize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let userId = authManager.currentUser?.id else {
                        print("⚠️ Auto-restore skipped - user not fully authenticated")
                        print("⚠️ User should sign out and sign in again")
                        return
                    }
                    
                    print("🔄 First launch detected - auto-loading from cloud...")
                    print("🔐 User ID: \(userId)")
                    hasLoadedFromCloud = true
                    
                    viewModel.loadFromCloud { success in
                        if success {
                            print("✅ Auto-restore from cloud completed successfully!")
                        } else {
                            print("⚠️ Auto-restore failed or no cloud data found")
                            print("💡 Tip: Sign out and sign in again to restore data")
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.updateMutualFundNAVs()
            
            // Process recurring transactions
            let recurringManager = RecurringTransactionManager()
            recurringManager.processRecurringTransactions(context: context)
            
            // Calculate interest for loans
            viewModel.calculateInterestForAllLoans()
            
            // Process due insurance premiums
            let insuranceManager = InsuranceManager.shared
            insuranceManager.processInsurancePremiums(context: context, accounts: viewModel.accounts)
            
            // Ingest emails into Pending (Outlook + Gmail) without duplicates
            viewModel.ingestEmailsToPending()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let viewModel = ExpenseViewModel(context: context)
        return MainTabView(viewModel: viewModel)
            .environment(\.managedObjectContext, context)
    }
}
