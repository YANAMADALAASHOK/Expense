//
//  ContentView.swift
//  Expense
//
//  Created by Ashok Naidu on 20/12/24.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: ExpenseViewModel
    @State private var selectedTab = 0
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            AccountsView(viewModel: viewModel)
                .tabItem {
                    Label("Accounts", systemImage: "banknote")
                }
                .tag(0)
            
            TransactionView(viewModel: viewModel)
                .tabItem {
                    Label("Transactions", systemImage: "arrow.left.arrow.right")
                }
                .tag(1)
            
            ReportsView(viewModel: viewModel)
                .tabItem {
                    Label("Reports", systemImage: "chart.bar")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
