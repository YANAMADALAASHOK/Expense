//
//  Persistence.swift
//  Expense
//
//  Created by Ashok Naidu on 20/12/24.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Add sample data for preview
        let sampleAccount = CDAccount(context: viewContext)
        sampleAccount.id = UUID()
        sampleAccount.accountName = "Sample Bank Account"
        sampleAccount.accountType = AccountType.bankAccount.rawValue
        sampleAccount.balance = 1000.0
        sampleAccount.creditLimit = 0.0
        
        let sampleTransaction = CDTransaction(context: viewContext)
        sampleTransaction.id = UUID()
        sampleTransaction.amount = 50.0
        sampleTransaction.category = TransactionCategory.food.rawValue
        sampleTransaction.date = Date()
        sampleTransaction.isCredit = false
        sampleTransaction.account = sampleAccount
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Expense")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
