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
    @StateObject private var viewModel: ExpenseViewModel
    @StateObject private var authManager = AuthenticationManager.shared
    
    init(context: NSManagedObjectContext) {
        let viewModel = ExpenseViewModel(context: context)
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
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

            ReportsView(viewModel: viewModel)
                .tabItem {
                    Label("Reports", systemImage: "chart.pie")
                }
            
            TransactionView(viewModel: viewModel)
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet")
                }
            
            BudgetsView(viewModel: viewModel)
                .tabItem {
                    Label("Budgets", systemImage: "creditcard")
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.updateMutualFundNAVs()
            
            // Process recurring transactions
            let recurringManager = RecurringTransactionManager()
            recurringManager.processRecurringTransactions(context: context)
            
            // Calculate interest for loans
            viewModel.calculateInterestForAllLoans()
            
            // Ingest emails into Pending (Outlook + Gmail) without duplicates
            viewModel.ingestEmailsToPending()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView(context: PersistenceController.preview.container.viewContext)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
