import SwiftUI
import CoreData

class ExpenseViewModel: ObservableObject {
    private let viewContext: NSManagedObjectContext
    
    @Published var accounts: [CDAccount] = []
    @Published var recentTransactions: [CDTransaction] = []
    @Published var customCategories: [String] = []
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        loadCustomCategories()
        fetchAccounts()
        fetchRecentTransactions()
        
        // Add observer for Core Data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(managedObjectContextObjectsDidChange),
            name: NSManagedObjectContext.didChangeObjectsNotification,
            object: context)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func managedObjectContextObjectsDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.fetchAccounts()
            self?.fetchRecentTransactions()
        }
    }
    
    // MARK: - Category Management
    private func loadCustomCategories() {
        if let savedCategories = UserDefaults.standard.stringArray(forKey: "CustomCategories") {
            customCategories = savedCategories
        }
    }
    
    func addCustomCategory(_ category: String) {
        customCategories.append(category)
        UserDefaults.standard.set(customCategories, forKey: "CustomCategories")
        objectWillChange.send()
    }
    
    func removeCustomCategory(at index: Int) {
        customCategories.remove(at: index)
        UserDefaults.standard.set(customCategories, forKey: "CustomCategories")
        objectWillChange.send()
    }
    
    var allCategories: [String] {
        let defaultCategories = TransactionCategory.allCases.map { $0.rawValue }
        return defaultCategories + customCategories
    }
    
    // MARK: - Account Operations
    func addAccount(name: String, type: AccountType, balance: Double, creditLimit: Double? = nil) {
        let account = CDAccount(context: viewContext)
        account.id = UUID()
        account.accountName = name
        account.accountType = type.rawValue
        account.balance = balance
        account.creditLimit = creditLimit ?? 0.0
        
        saveContext()
    }
    
    func deleteAccount(_ account: CDAccount) {
        viewContext.delete(account)
        saveContext()
    }
    
    func updateAccount(_ account: CDAccount, name: String, balance: Double, creditLimit: Double?) {
        account.accountName = name
        account.balance = balance
        if let limit = creditLimit {
            account.creditLimit = limit
        }
        
        saveContext()
    }
    
    // MARK: - Transaction Operations
    func addTransaction(
        amount: Double,
        category: TransactionCategory,
        isCredit: Bool,
        account: CDAccount,
        notes: String?,
        date: Date = Date()
    ) {
        let transaction = CDTransaction(context: viewContext)
        transaction.id = UUID()
        transaction.amount = amount
        transaction.category = category.rawValue
        transaction.isCredit = isCredit
        transaction.account = account
        transaction.notes = notes
        transaction.date = date
        
        if isCredit {
            account.balance += amount
        } else {
            account.balance -= amount
        }
        
        saveContext()
    }
    
    func deleteTransaction(_ transaction: CDTransaction) {
        viewContext.performAndWait {
            // Revert the balance change immediately
            if let account = transaction.account {
                if transaction.isCredit {
                    account.balance -= transaction.amount
                } else {
                    if account.accountType == AccountType.creditCard.rawValue {
                        account.balance -= transaction.amount
                    } else {
                        account.balance += transaction.amount
                    }
                }
            }
            
            viewContext.delete(transaction)
            
            do {
                try viewContext.save()
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                }
            } catch {
                print("Error deleting transaction: \(error)")
            }
        }
    }
    
    func updateTransaction(_ transaction: CDTransaction, amount: Double, category: TransactionCategory, isCredit: Bool, notes: String?) {
        viewContext.performAndWait {
            // First revert the old balance change
            if let account = transaction.account {
                if transaction.isCredit {
                    account.balance -= transaction.amount
                } else {
                    if account.accountType == AccountType.creditCard.rawValue {
                        account.balance -= transaction.amount
                    } else {
                        account.balance += transaction.amount
                    }
                }
                
                // Apply the new balance change
                if isCredit {
                    account.balance += amount
                } else {
                    if account.accountType == AccountType.creditCard.rawValue {
                        account.balance += amount
                    } else {
                        account.balance -= amount
                    }
                }
            }
            
            transaction.amount = amount
            transaction.category = category.rawValue
            transaction.isCredit = isCredit
            transaction.notes = notes
            
            do {
                try viewContext.save()
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                }
            } catch {
                print("Error updating transaction: \(error)")
            }
        }
    }
    
    func getTransactionsSummary(for period: DateComponents) -> [TransactionCategory: Double] {
        // Implementation for getting transactions summary by category for a specific period
        // To be implemented
        return [:]
    }
    
    private func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
                viewContext.reset() // Reset the context to ensure fresh data
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                }
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
    
    private func fetchAccounts() {
        let request = NSFetchRequest<CDAccount>(entityName: "Account")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDAccount.accountName, ascending: true)]
        
        do {
            accounts = try viewContext.fetch(request)
            objectWillChange.send()
        } catch {
            print("Error fetching accounts: \(error)")
        }
    }
    
    private func fetchRecentTransactions() {
        let request = NSFetchRequest<CDTransaction>(entityName: "Transaction")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTransaction.date, ascending: false)]
        request.fetchLimit = 50
        
        do {
            recentTransactions = try viewContext.fetch(request)
            objectWillChange.send()
        } catch {
            print("Error fetching transactions: \(error)")
        }
    }
    
    func refreshData() {
        viewContext.reset()
        fetchAccounts()
        fetchRecentTransactions()
        objectWillChange.send()
    }
} 