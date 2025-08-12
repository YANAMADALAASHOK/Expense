//
//  Persistence.swift
//  Expense
//
//  Created by Ashok Naidu on 20/12/24.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Expense")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
        
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
    
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    func clearAllData() {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "CDAccount")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        let transactionsFetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "CDTransaction")
        let deleteTransactionsRequest = NSBatchDeleteRequest(fetchRequest: transactionsFetchRequest)
        
        do {
            try context.execute(deleteRequest)
            try context.execute(deleteTransactionsRequest)
            try context.save()
        } catch {
            print("Error clearing data: \(error)")
        }
    }
}
