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
    
    var body: some Scene {
        WindowGroup {
            MainTabView(context: persistenceController.container.viewContext)
        }
    }
}
