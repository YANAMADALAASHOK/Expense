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

    // Backup functionality
    func backupData() {
        guard let userId = AuthenticationManager.shared.currentUser?.id else { return }
        
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let backupFolderPath = documentsPath.appendingPathComponent("Backups").appendingPathComponent(userId)
        
        do {
            try fileManager.createDirectory(at: backupFolderPath, withIntermediateDirectories: true)
            
            // Get the store file URL
            guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }
            
            // Create backup file URL
            let backupURL = backupFolderPath.appendingPathComponent("expense_backup.sqlite")
            
            // Remove existing backup if exists
            try? fileManager.removeItem(at: backupURL)
            
            // Copy current store to backup location
            try fileManager.copyItem(at: storeURL, to: backupURL)
            
            print("Backup created successfully at: \(backupURL.path)")
        } catch {
            print("Backup failed: \(error.localizedDescription)")
        }
    }

    func restoreData() {
        guard let userId = AuthenticationManager.shared.currentUser?.id else { return }
        
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let backupURL = documentsPath
            .appendingPathComponent("Backups")
            .appendingPathComponent(userId)
            .appendingPathComponent("expense_backup.sqlite")
        
        guard fileManager.fileExists(atPath: backupURL.path) else { return }
        
        do {
            // Get the store file URL
            guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }
            
            // Remove existing store
            try fileManager.removeItem(at: storeURL)
            
            // Copy backup to store location
            try fileManager.copyItem(at: backupURL, to: storeURL)
            
            // Reset the container
            container.loadPersistentStores { _, error in
                if let error = error {
                    print("Restore failed: \(error.localizedDescription)")
                }
            }
            
            print("Data restored successfully")
        } catch {
            print("Restore failed: \(error.localizedDescription)")
        }
    }
}
