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
        
        // Start timer for automatic interest calculation
        startInterestCalculationTimer()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startInterestCalculationTimer() {
        // Check every hour if we need to calculate interest
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkAndCalculateInterest()
        }
    }
    
    private func checkAndCalculateInterest() {
        let calendar = Calendar.current
        let now = Date()
        
        // Only proceed if it's the 30th day of the month
        guard calendar.component(.day, from: now) == 30 else { return }
        
        // Get all loans
        let loans = accounts.filter { $0.accountType == AccountType.loan.rawValue }
        
        for loan in loans {
            guard let metadata = loan.metadata,
                  let rateString = metadata["interestRate"],
                  let rate = Double(rateString),
                  let lastInterestDateString = metadata["lastInterestDate"],
                  let lastInterestDate = ISO8601DateFormatter().date(from: lastInterestDateString) else {
                continue
            }
            
            // Check if we already calculated interest this month
            let lastInterestMonth = calendar.component(.month, from: lastInterestDate)
            let currentMonth = calendar.component(.month, from: now)
            
            if lastInterestMonth != currentMonth {
                // Calculate and add interest
                let balance = loan.balance
                let monthlyRate = rate / 12.0 / 100.0  // Convert annual rate to monthly decimal
                let interest = balance * monthlyRate
                
                // Add interest transaction
                addTransaction(
                    amount: interest,
                    category: .interest,
                    isCredit: false,  // Debit because it increases the loan amount
                    account: loan,
                    notes: "Monthly Interest @ \(rate)% per annum",
                    date: now
                )
                
                // Update last interest date
                var updatedMetadata = metadata
                updatedMetadata["lastInterestDate"] = now.ISO8601Format()
                loan.metadata = updatedMetadata
                
                saveContext()
            }
        }
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
    func addAccount(
        name: String,
        type: AccountType,
        balance: Double,
        creditLimit: Double? = nil,
        metadata: [String: String]? = nil
    ) {
        let account = CDAccount(context: viewContext)
        account.id = UUID()
        account.accountName = name
        account.accountType = type.rawValue
        account.balance = balance
        account.creditLimit = creditLimit ?? 0.0
        account.metadata = metadata
        
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
        
        // For credit cards:
        // - When spending (isCredit = false), increase the balance
        // - When paying bill (isCredit = true), decrease the balance
        if account.accountType == AccountType.creditCard.rawValue {
            account.balance += isCredit ? -amount : amount
        } else {
            // For all other accounts:
            // - Credit transactions increase the balance
            // - Debit transactions decrease the balance
            account.balance += isCredit ? amount : -amount
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
    
    // MARK: - Core Data Operations
    func saveContext() {
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
    
    // MARK: - Data Import/Export
    struct ExportData: Codable {
        struct AccountData: Codable {
            let id: UUID
            let name: String
            let type: String
            let balance: Double
            let creditLimit: Double
            let metadata: [String: String]?
        }
        
        struct TransactionData: Codable {
            let id: UUID
            let amount: Double
            let category: String
            let isCredit: Bool
            let notes: String?
            let date: Date
            let accountID: UUID
        }
        
        let accounts: [AccountData]
        let transactions: [TransactionData]
        let customCategories: [String]
    }
    
    func exportData() throws -> Data {
        let accountsData = accounts.map { account in
            ExportData.AccountData(
                id: account.id ?? UUID(),
                name: account.accountName ?? "",
                type: account.accountType ?? "",
                balance: account.balance,
                creditLimit: account.creditLimit,
                metadata: account.metadata
            )
        }
        
        let transactionsData = recentTransactions.map { transaction in
            ExportData.TransactionData(
                id: transaction.id ?? UUID(),
                amount: transaction.amount,
                category: transaction.category ?? "",
                isCredit: transaction.isCredit,
                notes: transaction.notes,
                date: transaction.date ?? Date(),
                accountID: transaction.account?.id ?? UUID()
            )
        }
        
        let exportData = ExportData(
            accounts: accountsData,
            transactions: transactionsData,
            customCategories: customCategories
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportData)
    }
    
    func importData(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importData = try decoder.decode(ExportData.self, from: data)
        
        viewContext.performAndWait {
            // Clear existing data
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Account")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try? viewContext.execute(deleteRequest)
            
            let transactionsFetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Transaction")
            let deleteTransactionsRequest = NSBatchDeleteRequest(fetchRequest: transactionsFetchRequest)
            try? viewContext.execute(deleteTransactionsRequest)
            
            // Create accounts dictionary for lookup
            var accountsDict: [UUID: CDAccount] = [:]
            
            // Import accounts
            for accountData in importData.accounts {
                let account = CDAccount(context: viewContext)
                account.id = accountData.id
                account.accountName = accountData.name
                account.accountType = accountData.type
                account.balance = accountData.balance
                account.creditLimit = accountData.creditLimit
                account.metadata = accountData.metadata
                accountsDict[accountData.id] = account
            }
            
            // Import transactions
            for transactionData in importData.transactions {
                let transaction = CDTransaction(context: viewContext)
                transaction.id = transactionData.id
                transaction.amount = transactionData.amount
                transaction.category = transactionData.category
                transaction.isCredit = transactionData.isCredit
                transaction.notes = transactionData.notes
                transaction.date = transactionData.date
                transaction.account = accountsDict[transactionData.accountID]
            }
            
            // Import custom categories
            customCategories = importData.customCategories
            UserDefaults.standard.set(customCategories, forKey: "CustomCategories")
            
            // Save changes
            try? viewContext.save()
            
            // Refresh data
            fetchAccounts()
            fetchRecentTransactions()
            objectWillChange.send()
        }
    }
} 