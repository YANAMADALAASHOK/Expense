import SwiftUI
import CoreData
import FirebaseFirestore

class ExpenseViewModel: ObservableObject {
    let viewContext: NSManagedObjectContext
    private let db = Firestore.firestore()
    private var isDeletingAccount = false
    @Published var deletionStatus: String = ""
    @Published var isDeletingFromCloud = false
    
    // Rate limiting for Firestore writes
    private var lastFirestoreWrite: Date = Date.distantPast
    private let firestoreWriteDelay: TimeInterval = 0.5 // 500ms between writes
    private let firestoreQueue = DispatchQueue(label: "firestore.writes", qos: .background)
    private var cloudSyncDisabledUntil: Date?
    
    // Rate-limited Firestore write helper
    private func performRateLimitedFirestoreWrite<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let now = Date()
        let timeSinceLastWrite = now.timeIntervalSince(lastFirestoreWrite)
        
        if timeSinceLastWrite < firestoreWriteDelay {
            let delayNeeded = firestoreWriteDelay - timeSinceLastWrite
            print("DEBUG: Rate limiting Firestore write, waiting \(Int(delayNeeded * 1000))ms")
            try await Task.sleep(nanoseconds: UInt64(delayNeeded * 1_000_000_000))
        }
        
        lastFirestoreWrite = Date()
        
        // Retry logic for resource exhaustion
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            do {
                return try await operation()
            } catch {
                let errorString = error.localizedDescription
                if errorString.contains("Resource exhausted") || errorString.contains("Write stream exhausted") {
                    retryCount += 1
                    let backoffDelay = Double(retryCount) * 2.0 // Exponential backoff: 2s, 4s, 6s
                    print("DEBUG: Firestore resource exhausted, retry \(retryCount)/\(maxRetries) after \(backoffDelay)s")
                    
                    if retryCount < maxRetries {
                        try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                        continue
                    }
                }
                throw error
            }
        }
        
        fatalError("Should not reach here")
    }
    
    // Batch Core Data saves to reduce Firestore sync frequency
    private var pendingCoreDataSaves = 0
    private let maxPendingSaves = 5 // Batch up to 5 saves before syncing
    
    func performBatchedSave() throws {
        try viewContext.save()
        pendingCoreDataSaves += 1
        
        // Only sync to cloud after accumulating several saves
        if pendingCoreDataSaves >= maxPendingSaves {
            pendingCoreDataSaves = 0
            syncToCloud() // This will be rate-limited
        }
    }
    
    func forceSyncPendingSaves() {
        if pendingCoreDataSaves > 0 {
            pendingCoreDataSaves = 0
            syncToCloud()
        }
    }
    
    @Published var accounts: [CDAccount] = []
    @Published var recentTransactions: [CDTransaction] = []
    @Published var customCategories: [String] = []
    @Published var lastSyncTime: Date?
    @Published var budgets: [Budget] = []
    @Published var amfiFundList: [(code: String, name: String)] = []
    @Published var pendingTransactions: [PendingTransactionItem] = []
    @Published private(set) var processedEmailMessageIds: Set<String> = []
    @Published var lastEmailReceivedAt: Date?
    @Published var fetchedEmails: [OutlookMessage] = []
    @Published private(set) var excludedTransactionIds: Set<UUID> = []
    @Published var subcategoriesByParent: [String: [String]] = [:]
    @Published var lastNAVUpdateAt: Date? = UserDefaults.standard.object(forKey: "LastNAVUpdateAt") as? Date
    
    // MARK: - Insurance Policies
    @Published var insurancePolicies: [InsurancePolicy] = []
    private let insurancePoliciesKey = "InsurancePoliciesStore"
    
    // Preferred accounts for banks (persisted in UserDefaults)
    private let preferredAxisKey = "PreferredAccount_axis"
    private let preferredICICIKey = "PreferredAccount_icici"
    
    init(context: NSManagedObjectContext) {
        print("🔄 DEBUG: ExpenseViewModel init called - \(Date()) - Thread: \(Thread.current)")
        print("🔄 DEBUG: Call stack: \(Thread.callStackSymbols.prefix(5))")
        self.viewContext = context
        loadCustomCategories()
        loadSubcategories()
        loadInsurancePolicies()
        loadExcludedTransactions()
        loadPendingTransactions()
        loadEmailIngestionState()
        
        // Load last sync time from UserDefaults
        if let savedDate = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date {
            self.lastSyncTime = savedDate
        }

        // Add observer for Core Data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(managedObjectContextObjectsDidChange),
            name: NSManagedObjectContext.didChangeObjectsNotification,
            object: context)
        
        // Add observers for cloud sync
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncToCloud),
            name: .syncDataToCloud,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoadFromCloud),
            name: .loadDataFromCloud,
            object: nil)
        
            // Start timer for automatic interest calculation
    startInterestCalculationTimer()
    
    // Load initial data
    fetchAccounts()
    fetchRecentTransactions()
    fetchBudgets()
    
    // Train AI categorization with existing data
    AICategorizationManager.shared.trainWithUserData(transactions: recentTransactions)
        
        // If user is authenticated and not a guest, load data from cloud
        // Only load if we don't have local data to avoid overwriting recent changes
        if let user = AuthenticationManager.shared.currentUser,
           !user.isGuest {
            // Check if we have local data first and cloud sync is not disabled
            if accounts.isEmpty && recentTransactions.isEmpty {
                // Don't load from cloud if temporarily disabled (e.g., after account deletion)
                if let disabledUntil = cloudSyncDisabledUntil, Date() < disabledUntil {
                    print("Skipping initial cloud load - temporarily disabled until \(disabledUntil)")
                } else {
                    loadFromCloud { _ in }
                }
            }
        }
    }

    // MARK: - Preferred Accounts (Axis/ICICI) by key
    // bankKey should be "axis" or "icici"
    func setPreferredAccount(bankKey: String, account: CDAccount?) {
        let key = (bankKey.lowercased() == "axis") ? preferredAxisKey : preferredICICIKey
        if let acc = account {
            if let id = acc.id {
                UserDefaults.standard.set(id.uuidString, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
                print("[PreferredAccount] Attempted to save account without UUID for bankKey=\(bankKey)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    func preferredAccountId(bankKey: String) -> UUID? {
        let key = (bankKey.lowercased() == "axis") ? preferredAxisKey : preferredICICIKey
        guard let idStr = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: idStr) else { return nil }
        return uuid
    }
    func getPreferredAccount(bankKey: String) -> CDAccount? {
        guard let id = preferredAccountId(bankKey: bankKey) else { return nil }
        return accounts.first { acct in
            if let aid = acct.id { return aid == id }
            return false
        }
    }
    
    // MARK: - Insurance Policies Persistence (moved inside class)
    private var hasLoadedInsurancePolicies = false
    
    func loadInsurancePolicies() {
        // Avoid repeated loading if already loaded
        if hasLoadedInsurancePolicies {
            print("DEBUG: ExpenseViewModel - Insurance policies already loaded, skipping")
            return
        }
        
        print("DEBUG: ExpenseViewModel - Loading insurance policies from key: \(insurancePoliciesKey)")
        if let data = UserDefaults.standard.data(forKey: insurancePoliciesKey),
           let items = try? JSONDecoder().decode([InsurancePolicy].self, from: data) {
            insurancePolicies = items
            print("DEBUG: ExpenseViewModel - Loaded \(items.count) insurance policies")
            for policy in items {
                print("DEBUG: ExpenseViewModel - Policy: \(policy.name), Amount: ₹\(policy.premiumAmount), Active: \(policy.isActive)")
            }
        } else {
            print("DEBUG: ExpenseViewModel - No insurance policies found in UserDefaults")
            insurancePolicies = []
        }
        hasLoadedInsurancePolicies = true
    }
    func saveInsurancePolicies() {
        if let data = try? JSONEncoder().encode(insurancePolicies) {
            UserDefaults.standard.set(data, forKey: insurancePoliciesKey)
            print("DEBUG: ExpenseViewModel - Saved \(insurancePolicies.count) insurance policies to UserDefaults")
        } else {
            print("DEBUG: ExpenseViewModel - Failed to encode insurance policies for saving")
        }
    }
    func addInsurancePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.append(policy)
        saveInsurancePolicies()
        objectWillChange.send()
    }
    func updateInsurancePolicy(_ policy: InsurancePolicy) {
        if let idx = insurancePolicies.firstIndex(where: { $0.id == policy.id }) {
            insurancePolicies[idx] = policy
            saveInsurancePolicies()
            objectWillChange.send()
        }
    }
    func deleteInsurancePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.removeAll { $0.id == policy.id }
        saveInsurancePolicies()
        objectWillChange.send()
    }
    /// Debits due insurance premiums today and records Utilities transactions
    func processDueInsurancePremiums(on date: Date = Date()) {
        let calendar = Calendar.current
        let todayDay = calendar.component(.day, from: date)
        let currentMonth = calendar.component(.month, from: date)
        let currentYear = calendar.component(.year, from: date)
        var changed = false
        for i in insurancePolicies.indices {
            guard insurancePolicies[i].isActive else { continue }
            let p = insurancePolicies[i]
            guard p.dayOfMonth == todayDay else { continue }
            if let last = p.lastPaidAt {
                let m = calendar.component(.month, from: last)
                let y = calendar.component(.year, from: last)
                if m == currentMonth && y == currentYear { continue }
            }
            guard let acc = accounts.first(where: { $0.id == p.accountId }) else { continue }
            addTransaction(amount: p.premiumAmount, category: .utilities, isCredit: false, account: acc, notes: "Insurance: \(p.name)", date: date)
            insurancePolicies[i].lastPaidAt = date
            changed = true
        }
        if changed { saveInsurancePolicies() }
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
            let metadata = loan.metadataDictionary
            guard let rateString = metadata["interestRate"],
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
                updatedMetadata["lastInterestDate"] = ISO8601DateFormatter().string(from: now)
                loan.metadataDictionary = updatedMetadata
                
                saveContext()
            }
        }
    }

    // MARK: - Excluded Transactions (Dashboard)
    private var hasLoadedExcludedTransactions = false
    
    private func loadExcludedTransactions() {
        if hasLoadedExcludedTransactions {
            return
        }
        if let raw = UserDefaults.standard.array(forKey: "ExcludedTransactions") as? [String] {
            let ids = raw.compactMap { UUID(uuidString: $0) }
            excludedTransactionIds = Set(ids)
        }
        hasLoadedExcludedTransactions = true
    }

    private func saveExcludedTransactions() {
        let raw = excludedTransactionIds.map { $0.uuidString }
        UserDefaults.standard.set(raw, forKey: "ExcludedTransactions")
    }

    func isTransactionExcluded(_ transaction: CDTransaction) -> Bool {
        guard let id = transaction.id else { return false }
        return excludedTransactionIds.contains(id)
    }

    func setExcluded(for transaction: CDTransaction, excluded: Bool) {
        guard let id = transaction.id else { return }
        if excluded { excludedTransactionIds.insert(id) } else { excludedTransactionIds.remove(id) }
        saveExcludedTransactions()
        objectWillChange.send()
    }

    func toggleExcludeTransaction(_ transaction: CDTransaction) {
        setExcluded(for: transaction, excluded: !isTransactionExcluded(transaction))
    }

    var dashboardTransactions: [CDTransaction] {
        recentTransactions.filter { txn in
            guard let id = txn.id else { return true }
            return !excludedTransactionIds.contains(id)
        }
    }
    
    @objc private func managedObjectContextObjectsDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.fetchAccounts()
            self?.fetchRecentTransactions()
        }
    }
    
    // MARK: - Category Management
    private var hasLoadedCustomCategories = false
    private var hasLoadedSubcategories = false
    
    private func loadCustomCategories() {
        if hasLoadedCustomCategories {
            return
        }
        if let savedCategories = UserDefaults.standard.stringArray(forKey: "CustomCategories") {
            customCategories = savedCategories
        }
        hasLoadedCustomCategories = true
    }
    private func loadSubcategories() {
        if hasLoadedSubcategories {
            return
        }
        if let data = UserDefaults.standard.data(forKey: "SubcategoriesByParent"),
           let dict = try? JSONDecoder().decode([String: [String]].self, from: data) {
            subcategoriesByParent = dict
        }
        hasLoadedSubcategories = true
    }
    private func saveSubcategories() {
        if let data = try? JSONEncoder().encode(subcategoriesByParent) {
            UserDefaults.standard.set(data, forKey: "SubcategoriesByParent")
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
    
    func subcategories(for parent: String) -> [String] {
        let unique = Array(Set(subcategoriesByParent[parent] ?? [])).sorted()
        return unique
    }
    
    func addSubcategory(parent: String, subcategory: String) {
        guard !parent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !subcategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var list = subcategoriesByParent[parent] ?? []
        list.append(subcategory)
        subcategoriesByParent[parent] = Array(Set(list)).sorted()
        saveSubcategories()
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
        if let metadata = metadata {
            account.metadataDictionary = metadata
        }
        
        saveContext()
    }
    
    func deleteAccount(_ account: CDAccount) {
        isDeletingAccount = true
        isDeletingFromCloud = true
        
        let accountName = account.wrappedAccountName
        let accountId = account.id?.uuidString ?? "unknown"
        
        Task { @MainActor in
            // Step 1: Delete from cloud completely (both locations)
            deletionStatus = "🌩️ Deleting \(accountName) from cloud..."
            
            do {
                // Delete from accounts collection with rate limiting
                try await performRateLimitedFirestoreWrite {
                    try await self.db.collection("accounts").document(accountId).delete()
                }
                print("DEBUG: Deleted from accounts collection: \(accountName)")
                
                // Delete transactions from transactions collection with rate limiting
                let transactionQuery = self.db.collection("transactions").whereField("accountId", isEqualTo: accountId)
                let transactionSnapshot = try await transactionQuery.getDocuments()
                
                if !transactionSnapshot.documents.isEmpty {
                    try await performRateLimitedFirestoreWrite {
                        let batch = self.db.batch()
                        for document in transactionSnapshot.documents {
                            batch.deleteDocument(document.reference)
                        }
                        try await batch.commit()
                    }
                    print("DEBUG: Deleted \(transactionSnapshot.documents.count) transactions from Firestore")
                }
                
                // CRITICAL: Update user's backup data without the deleted account
                if let userId = AuthenticationManager.shared.currentUser?.id {
                    // First delete locally so export doesn't include deleted account
                    await withCheckedContinuation { continuation in
                        viewContext.performAndWait {
                            viewContext.delete(account)
                            try? viewContext.save()
                            continuation.resume()
                        }
                    }
                    
                    // Now export clean data and update user backup
                    let exportData = try self.exportData()
                    let jsonObject = try JSONSerialization.jsonObject(with: exportData) as? [String: Any]
                    
                    try await performRateLimitedFirestoreWrite {
                        let docRef = self.db.collection("users").document(userId)
                        let payload: [String: Any] = [
                            "data": jsonObject ?? [:],
                            "lastSynced": Date()
                        ]
                        
                        try await docRef.setData(payload)
                    }
                    print("DEBUG: Updated user backup without deleted account")
                }
                
                deletionStatus = "✅ Completely deleted from cloud and local"
                
            } catch {
                print("DEBUG: Error deleting from cloud: \(error)")
                deletionStatus = "⚠️ Cloud deletion failed - deleting locally only"
                
                // Delete locally even if cloud fails
                await withCheckedContinuation { continuation in
                    viewContext.performAndWait {
                        viewContext.delete(account)
                        try? viewContext.save()
                        continuation.resume()
                    }
                }
            }
            
            isDeletingFromCloud = false
            
            // Refresh UI and show completion
            print("DEBUG: Successfully deleted account: \(accountName)")
            
            // Disable cloud sync for 30 seconds to prevent re-syncing deleted accounts
            cloudSyncDisabledUntil = Date().addingTimeInterval(30)
            print("DEBUG: Cloud sync disabled until \(cloudSyncDisabledUntil!) to prevent account resurrection")
            
            // Also disable auto-fetch for credit card statements temporarily to prevent recreation
            if accountName.contains("Axis Bank") || accountName.contains("ICICI Bank") || accountName.contains("HDFC Bank") {
                // Use a separate key for temporary disable due to deletion
                let tempDisableKey = "tempDisableAutoFetchCreditCards"
                UserDefaults.standard.set(Date().addingTimeInterval(60), forKey: tempDisableKey)
                print("DEBUG: Auto-fetch temporarily disabled for credit card accounts (60 seconds)")
            }
            
            fetchAccounts()
            fetchRecentTransactions()
            objectWillChange.send()
            
            // Clear status after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.deletionStatus = ""
                self.isDeletingAccount = false
            }
        }
    }
    
    // Add a function to clean up corrupted accounts
    func cleanupCorruptedAccounts() {
        viewContext.performAndWait {
            do {
                let request = NSFetchRequest<CDAccount>(entityName: "CDAccount")
                let allAccounts = try viewContext.fetch(request)
                
                var deletedCount = 0
                for account in allAccounts {
                    // Delete accounts with nil or empty names, or invalid data
                    if account.accountName == nil || account.accountName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                        print("DEBUG: Deleting corrupted account with nil/empty name: \(account.id?.uuidString ?? "unknown")")
                        viewContext.delete(account)
                        deletedCount += 1
                    }
                }
                
                if deletedCount > 0 {
                    try viewContext.save()
                    print("DEBUG: Cleaned up \(deletedCount) corrupted accounts")
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.fetchAccounts()
                        self?.fetchRecentTransactions()
                        self?.objectWillChange.send()
                    }
                }
            } catch {
                print("Error cleaning up corrupted accounts: \(error)")
                viewContext.rollback()
            }
        }
    }
    
    func updateAccount(_ account: CDAccount, name: String, balance: Double, creditLimit: Double?, metadata: [String: String]? = nil) {
        viewContext.performAndWait {
            account.accountName = name
            account.balance = balance
            if let limit = creditLimit {
                account.creditLimit = limit
            }
            if let metadata = metadata {
                account.metadataDictionary = metadata
            }
            
            do {
                try viewContext.save()
                print("Successfully updated account: \(name)")
                
                // Refresh data on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                }
            } catch {
                print("Error updating account: \(error)")
                // Try to reset context and refresh
                viewContext.rollback()
                DispatchQueue.main.async { [weak self] in
                    self?.refreshData()
                }
            }
        }
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
        // Self transfers should be handled via transfer API, guard here to avoid mis-posting
        if category == .selfTransfer {
            print("[ExpenseViewModel] addTransaction called with selfTransfer - ignoring. Use transferBetweenAccounts().")
            return
        }
        let transaction = CDTransaction(context: viewContext)
        transaction.id = UUID()
        transaction.amount = amount
        transaction.category = category.rawValue
        transaction.isCredit = isCredit
        transaction.account = account
        transaction.notes = notes
        transaction.date = date
        
        // Auto-categorize if category is "Other"
        if category == .other {
            transaction.autoCategorize()
        }
        
        // Ensure the transaction is properly saved
        do {
            try viewContext.save()
        } catch {
            print("Error saving transaction: \(error)")
        }
        
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
        fetchRecentTransactions()
        
        // Retrain AI with new data
        AICategorizationManager.shared.trainWithUserData(transactions: recentTransactions)
        
        // Ensure UI updates
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Transfer funds between two of user's accounts without affecting income/expense totals.
    /// Creates two transactions: debit on source (Self Transfer) and credit on destination (Self Transfer).
    func transferBetweenAccounts(amount: Double, from: CDAccount, to: CDAccount, notes: String?, date: Date = Date()) {
        viewContext.performAndWait {
            // 1) Source debit
            let debit = CDTransaction(context: viewContext)
            debit.id = UUID()
            debit.amount = amount
            debit.category = TransactionCategory.selfTransfer.rawValue
            debit.isCredit = false
            debit.account = from
            debit.notes = notes
            debit.date = date

            // 2) Destination credit
            let credit = CDTransaction(context: viewContext)
            credit.id = UUID()
            credit.amount = amount
            credit.category = TransactionCategory.selfTransfer.rawValue
            credit.isCredit = true
            credit.account = to
            credit.notes = notes
            credit.date = date

            // Update balances according to account types
            // For credit cards: credit reduces balance; debit increases balance
            if from.accountType == AccountType.creditCard.rawValue {
                from.balance += amount // debit to CC increases due amount
            } else {
                from.balance -= amount
            }
            if to.accountType == AccountType.creditCard.rawValue {
                to.balance -= amount // credit to CC reduces due amount
            } else {
                to.balance += amount
            }

            saveContext()
            fetchRecentTransactions()
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    
    func processLoanPayment(
        amount: Double,
        fromAccount: CDAccount,
        toLoanAccount: CDAccount,
        notes: String,
        date: Date = Date()
    ) {
        viewContext.performAndWait {
            do {
                // 1. Create expense transaction from bank account (debit)
                let expenseTransaction = CDTransaction(context: viewContext)
                expenseTransaction.id = UUID()
                expenseTransaction.amount = amount
                expenseTransaction.category = TransactionCategory.emiPayment.rawValue
                expenseTransaction.isCredit = false  // Debit from bank account
                expenseTransaction.account = fromAccount
                expenseTransaction.notes = "Loan Payment to \(toLoanAccount.wrappedAccountName) - \(notes)"
                expenseTransaction.date = date
                
                // 2. Create payment transaction to loan account (credit - reduces loan balance)
                let paymentTransaction = CDTransaction(context: viewContext)
                paymentTransaction.id = UUID()
                paymentTransaction.amount = amount
                paymentTransaction.category = TransactionCategory.emiPayment.rawValue
                paymentTransaction.isCredit = true  // Credit to loan account (reduces balance)
                paymentTransaction.account = toLoanAccount
                paymentTransaction.notes = "Payment from \(fromAccount.wrappedAccountName) - \(notes)"
                paymentTransaction.date = date
                
                // 3. Update account balances
                // Bank account balance decreases
                fromAccount.balance -= amount
                
                // Loan account balance decreases (since it's a liability)
                toLoanAccount.balance -= amount
                
                // Save all changes
                try viewContext.save()
                
                print("Loan payment processed: \(amount) from \(fromAccount.wrappedAccountName) to \(toLoanAccount.wrappedAccountName)")
                
                // Refresh data on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                }
            } catch {
                print("Error processing loan payment: \(error)")
                // Try to reset context and refresh
                viewContext.rollback()
                DispatchQueue.main.async { [weak self] in
                    self?.refreshData()
                }
            }
        }
    }

    func processCreditCardPayment(
        amount: Double,
        fromAccount: CDAccount,
        toCreditCardAccount: CDAccount,
        notes: String,
        date: Date = Date()
    ) {
        viewContext.performAndWait {
            // Create ONE debit transaction from funding account, and directly adjust the card balance
            let debitTxn = CDTransaction(context: viewContext)
            debitTxn.id = UUID()
            debitTxn.amount = amount
            debitTxn.category = TransactionCategory.creditCardPayment.rawValue
            debitTxn.isCredit = false // debit from funding account reduces balance
            debitTxn.account = fromAccount
            debitTxn.notes = "Credit Card Payment to \(toCreditCardAccount.wrappedAccountName) - \(notes)"
            debitTxn.date = date

            // Update balances
            fromAccount.balance -= amount
            toCreditCardAccount.balance -= amount

            // Save and refresh
            do {
                try viewContext.save()
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                }
            } catch {
                print("Error processing credit card payment: \(error)")
            }
        }
    }

    func convertToCreditCardPayment(
        transaction: CDTransaction,
        amount: Double,
        paidCard: CDAccount,
        fundingAccount: CDAccount,
        notes: String,
        date: Date
    ) {
        viewContext.performAndWait {
            // Revert original balance effect
            if let originalAccount = transaction.account {
                if transaction.isCredit {
                    originalAccount.balance -= transaction.amount
                } else {
                    if originalAccount.accountType == AccountType.creditCard.rawValue {
                        originalAccount.balance -= transaction.amount
                    } else {
                        originalAccount.balance += transaction.amount
                    }
                }
            }

            // Remove original transaction
            viewContext.delete(transaction)

            // Create ONE debit transaction on funding account and adjust card outstanding directly
            let debitTxn = CDTransaction(context: viewContext)
            debitTxn.id = UUID()
            debitTxn.amount = amount
            debitTxn.category = TransactionCategory.creditCardPayment.rawValue
            debitTxn.isCredit = false
            debitTxn.account = fundingAccount
            debitTxn.notes = "Credit Card Payment to \(paidCard.wrappedAccountName) - \(notes)"
            debitTxn.date = date

            // Update balances
            fundingAccount.balance -= amount
            paidCard.balance -= amount

            do {
                try viewContext.save()
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                }
            } catch {
                print("Error converting to credit card payment: \(error)")
            }
        }
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
    
    func updateTransaction(_ transaction: CDTransaction, amount: Double, category: TransactionCategory, isCredit: Bool, notes: String?, date: Date? = nil, updateRules: Bool = false) {
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
            if let newDate = date {
                transaction.date = newDate
            }
            
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

    // MARK: - Axis Bank CSV Import
    // Handles common Axis layouts, e.g. columns like:
    //  - Date / Transaction Date, Narration/Description/Particulars, Ref No/Cheque No, Value Date, Withdrawal Amount/Debit, Deposit Amount/Credit, Closing Balance
    func importAxisBankCSV(from url: URL, into account: CDAccount? = nil, completion: @escaping (Result<Int, Error>) -> Void) {
        guard url.startAccessingSecurityScopedResource() else {
            completion(.failure(GrowwImportError.permissionDenied))
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            var lines = content.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { completion(.success(0)); return }

            // Find header line
            var headerLineIndex: Int?
            for (idx, line) in lines.enumerated() {
                let lc = line.lowercased()
                if lc.contains("date") && (lc.contains("debit") || lc.contains("withdrawal")) && (lc.contains("credit") || lc.contains("deposit")) {
                    headerLineIndex = idx
                    break
                }
                // Some Axis variants split headers into multiple lines; fallback: look for a line with many commas including date/narration
                if lc.contains("date") && (lc.contains("narration") || lc.contains("description") || lc.contains("particular")) {
                    headerLineIndex = idx
                    break
                }
            }
            guard let headerIdx = headerLineIndex else { completion(.failure(AxisImportError.invalidFormat)); return }

            let headerColumns = parseCSVLine(lines[headerIdx]).map { $0.trimmingCharacters(in: .whitespaces) }
            let lowerHeader = headerColumns.map { $0.lowercased() }

            func index(where predicate: (String) -> Bool) -> Int? {
                return lowerHeader.firstIndex(where: predicate)
            }

            let dateIndex = index { $0.contains("transaction date") || $0.contains("transactiondate") } ??
                             index { $0 == "date" || $0.hasSuffix(" date") || $0.contains("date") }
            let descIndex = index { $0.contains("narration") || $0.contains("description") || $0.contains("particular") || $0.contains("remarks") }
            let debitIndex = index { $0.contains("debit") || $0.contains("withdrawal") }
            let creditIndex = index { $0.contains("credit") || $0.contains("deposit") }
            // Balance is optional
            let balanceIndex = index { $0.contains("balance") }

            guard let dIdx = dateIndex, let xIdx = descIndex, let dbIdx = debitIndex, let crIdx = creditIndex else {
                completion(.failure(AxisImportError.invalidFormat))
                return
            }

            // Data lines after header
            var dataLines = Array(lines.suffix(from: headerIdx + 1))
            // Ensure oldest first if CSV is oldest-first or newest-first
            // If first line date > last line date, then it's newest-first; reverse to oldest-first
            let dfCheck = DateFormatter()
            dfCheck.locale = Locale(identifier: "en_IN")
            dfCheck.dateFormat = "dd-MM-yyyy"
            func parseAny(_ s: String) -> Date? {
                for fmt in ["dd/MM/yyyy","dd-MM-yyyy","dd-MMM-yyyy","dd-MMM-yy","yyyy-MM-dd","MM/dd/yyyy","dd/MM/yy","d/M/yyyy"] {
                    dfCheck.dateFormat = fmt
                    if let d = dfCheck.date(from: s) { return d }
                }
                return nil
            }
            if let firstData = dataLines.first, let lastData = dataLines.last {
                let firstCols = parseCSVLine(firstData)
                let lastCols = parseCSVLine(lastData)
                if firstCols.count > 0 && lastCols.count > 0 {
                    let firstDateStr = firstCols[dIdx].trimmingCharacters(in: .whitespaces)
                    let lastDateStr = lastCols[dIdx].trimmingCharacters(in: .whitespaces)
                    if let f = parseAny(firstDateStr), let l = parseAny(lastDateStr), f > l {
                        dataLines.reverse()
                    }
                }
            }

            var imported = 0
            var lastKnownBalance: Double?
            let dateFormats = [
                "dd/MM/yyyy",
                "dd-MMM-yyyy",
                "dd-MMM-yy",
                "yyyy-MM-dd",
                "dd-MM-yyyy",
                "MM/dd/yyyy",
                "dd/MM/yy",
                "d/M/yyyy"
            ]
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_IN")

            let targetAccount: CDAccount = account ?? accounts.first { $0.wrappedAccountType == .bankAccount } ?? {
                let acc = CDAccount(context: viewContext)
                acc.id = UUID()
                acc.accountName = "Axis Bank"
                acc.accountType = AccountType.bankAccount.rawValue
                acc.balance = 0
                return acc
            }()

            for line in dataLines {
                // Handle CSV fields with commas inside quotes
                let columns = parseCSVLine(line)
                guard columns.count >= max(dIdx, xIdx, dbIdx, crIdx, balanceIndex ?? 0) + 1 else { continue }

                let dateString = columns[dIdx].trimmingCharacters(in: .whitespaces)
                let description = columns[xIdx].trimmingCharacters(in: .whitespaces)
                let debitString = columns[dbIdx].replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                let creditString = columns[crIdx].replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)

                var parsedDate: Date? = nil
                for fmt in dateFormats {
                    dateFormatter.dateFormat = fmt
                    if let d = dateFormatter.date(from: dateString) {
                        parsedDate = d
                        break
                    }
                }
                guard let date = parsedDate else { continue }
                let debit = parseAmount(debitString) ?? 0
                let credit = parseAmount(creditString) ?? 0
                if debit == 0 && credit == 0 { continue }

                // Determine category using rules and heuristics (credits are NOT auto-classed as income)
                let isCredit = credit > 0
                let amount = isCredit ? credit : debit
                let inferredCategoryString = inferCategory(from: description, amount: amount, isCredit: isCredit)
                let category = TransactionCategory(rawValue: inferredCategoryString)

                // Create transaction in the same context without saving/resetting per row
                let transaction = CDTransaction(context: viewContext)
                transaction.id = UUID()
                transaction.amount = amount
                transaction.category = category.rawValue
                transaction.isCredit = isCredit
                transaction.account = targetAccount
                transaction.notes = description
                transaction.date = date
                imported += 1
                if let bIdx = balanceIndex, columns.count > bIdx {
                    lastKnownBalance = parseAmount(columns[bIdx])
                }
            }

            // Save once after batch to avoid context resets during import
            try viewContext.save()

            // Update selected account balance to the latest balance in CSV if provided
            if let bal = lastKnownBalance {
                targetAccount.balance = bal
                try? viewContext.save()
            }
            DispatchQueue.main.async { [weak self] in
                self?.fetchAccounts()
                self?.fetchRecentTransactions()
                self?.objectWillChange.send()
            }
            if imported == 0 {
                completion(.failure(AxisImportError.noTransactionsFound))
            } else {
                completion(.success(imported))
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    private func inferCategory(from description: String, amount: Double, isCredit: Bool) -> String {
        let text = description.lowercased()
        // Priority: user rules
        if let matched = AICategorizationManager.shared.userRules.first(where: { 
            switch $0.scope {
            case .all: break
            case .creditOnly: if !isCredit { return false }
            case .debitOnly: if isCredit { return false }
            }
            return text.contains($0.pattern.lowercased()) 
        }) {
            return matched.category
        }
        // Specific heuristics for Axis Bank statements
        if isCredit {
            // Credits are not assumed to be income unless explicitly matched by rules or keywords
            if text.contains("salary") || text.contains("payroll") || text.contains("cognizant") {
                return TransactionCategory.salary.rawValue
            }
            if text.contains("groww") || text.contains("bse") || text.contains("nse") || text.contains("amc") || text.contains("mf") || text.contains("redeem") || text.contains("payout") {
                return TransactionCategory.investment.rawValue
            }
            if text.range(of: "\\b(cred|credit card|cc bill|card payment)\\b", options: .regularExpression) != nil { return TransactionCategory.creditCardPayment.rawValue }
            if text.contains("amazon") || text.contains("flipkart") { return TransactionCategory.shopping.rawValue }
            // Otherwise leave as Other or use AI for non-income credit signals
            return TransactionCategory.other.rawValue
        } else {
            if text.range(of: "\\b(cred|credit card|cc bill|card payment)\\b", options: .regularExpression) != nil {
                return TransactionCategory.creditCardPayment.rawValue
            }
            if text.contains("groww") || text.contains("bse") || text.contains("nse") || text.contains("mf") || text.contains("sip") {
                return TransactionCategory.investment.rawValue
            }
            if text.contains("amazon") || text.contains("flipkart") {
                return TransactionCategory.shopping.rawValue
            }
            if text.contains("emi") || text.contains("loan") {
                return TransactionCategory.emiPayment.rawValue
            }
            // For debits, avoid classifying as Salary/Income by AI; prefer Other if no match
            return TransactionCategory.other.rawValue
        }
    }

    private func parseAmount(_ string: String) -> Double? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return 0 }
        // Handle parentheses for negatives
        var isNegative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            isNegative = true
            s = String(s.dropFirst().dropLast())
        }
        // Remove currency and labels
        let removals: [String] = [",", "₹", "INR", " ", "CR", "DR", "+"]
        for r in removals { s = s.replacingOccurrences(of: r, with: "") }
        // Replace localized minus signs if any
        s = s.replacingOccurrences(of: "−", with: "-")
        // Empty after cleaning means zero
        guard !s.isEmpty else { return 0 }
        var value = Double(s)
        if value == nil {
            // Try with dot/comma swap if localized
            let swapped = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            value = Double(swapped)
        }
        if var v = value {
            if isNegative { v = -v }
            // Some statements mark DR as debit (negative)
            if string.uppercased().contains("DR") { v = abs(v) }
            if string.uppercased().contains("CR") { v = abs(v) }
            return v
        }
        return nil
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
                    self?.autoSync() // Auto-sync after saving
                }
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
    
    func fetchAccounts() {
        let request = NSFetchRequest<CDAccount>(entityName: "CDAccount")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDAccount.accountName, ascending: true)]
        // Filter out accounts with nil or empty names
        request.predicate = NSPredicate(format: "accountName != nil AND accountName != ''")
        
        do {
            let fetchedAccounts = try viewContext.fetch(request)
            
            // Additional filtering to ensure data integrity
            accounts = fetchedAccounts.filter { account in
                guard let name = account.accountName,
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("DEBUG: Filtering out account with invalid name: \(account.id?.uuidString ?? "unknown")")
                    return false
                }
                return true
            }
            
            objectWillChange.send()
        } catch {
            print("Error fetching accounts: \(error)")
        }
    }
    
    private func fetchRecentTransactions() {
        let request = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTransaction.date, ascending: false)]
        // Show all transactions in the app (no limit)
        
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
    
    // MARK: - Email Ingestion State
    private var hasLoadedEmailIngestionState = false
    
    private func loadEmailIngestionState() {
        if hasLoadedEmailIngestionState {
            return
        }
        if let arr = UserDefaults.standard.array(forKey: "ProcessedEmailMessageIds") as? [String] {
            processedEmailMessageIds = Set(arr)
        }
        if let ts = UserDefaults.standard.object(forKey: "LastEmailReceivedAt") as? Date {
            lastEmailReceivedAt = ts
        }
        hasLoadedEmailIngestionState = true
    }
    func persistEmailIngestionState() {
        UserDefaults.standard.set(Array(processedEmailMessageIds), forKey: "ProcessedEmailMessageIds")
        if let ts = lastEmailReceivedAt {
            UserDefaults.standard.set(ts, forKey: "LastEmailReceivedAt")
        }
    }
    
    /// Reset deduplication state for email ingestion so older emails can be reprocessed.
    /// This clears the processed message IDs and the last-received timestamp.
    func resetEmailIngestionState() {
        processedEmailMessageIds.removeAll()
        lastEmailReceivedAt = nil
        UserDefaults.standard.removeObject(forKey: "ProcessedEmailMessageIds")
        UserDefaults.standard.removeObject(forKey: "LastEmailReceivedAt")
        print("[EmailIngestion] Reset processed IDs and last received timestamp")
    }
    func markEmailProcessed(messageId: String, receivedAt: Date) {
        processedEmailMessageIds.insert(messageId)
        if let last = lastEmailReceivedAt {
            if receivedAt > last { lastEmailReceivedAt = receivedAt }
        } else {
            lastEmailReceivedAt = receivedAt
        }
        persistEmailIngestionState()
    }
    
    // MARK: - Automatic Email → Pending ingestion
    /// Ingest Outlook and Gmail messages, parse transactions, and add to pending list without duplicates.
    func ingestEmailsToPending(completion: ((Int) -> Void)? = nil) {
        var added = 0
        let group = DispatchGroup()
        // Outlook (Axis Bank alerts only)
        group.enter()
        OutlookService.shared.fetchRecentMessages(since: lastEmailReceivedAt, sender: "alerts@axisbank.com") { [weak self] result in
            defer { group.leave() }
            guard let self = self else { return }
            if case .success(let msgs) = result {
                for msg in msgs {
                    guard !self.processedEmailMessageIds.contains(msg.id) else { continue }
                    let bodyText: String? = msg.body?.content ?? msg.bodyPreview
                    let receivedAt = ISO8601DateFormatter().date(from: msg.receivedDateTime) ?? Date()
                    if let parsed = try? EmailParser.parse(subject: msg.subject, body: bodyText) {
                        let pending = PendingTransactionItem(
                            subject: parsed.subject,
                            body: parsed.body,
                            amount: parsed.amount,
                            date: parsed.date,
                            isCredit: parsed.isCredit,
                            suggestedCategory: parsed.suggestedCategory,
                            notes: parsed.description
                        )
                        self.addPendingTransactionIfNew(pending)
                        self.markEmailProcessed(messageId: msg.id, receivedAt: receivedAt)
                        added += 1
                    }
                }
            }
        }
        // Gmail (ICICI)
        if GmailService.shared.isSignedIn {
            group.enter()
            let since = lastEmailReceivedAt
            GmailService.shared.fetchMessages(query: "from:credit_cards@icicibank.com", since: since, max: 50) { [weak self] result in
                defer { group.leave() }
                guard let self = self else { return }
                if case .success(let msgs) = result {
                    for (subject, body, received) in msgs {
                        // Use a synthetic signature to dedupe: hash of subject+date+amount
                        let signature = self.signatureForEmail(subject: subject, body: body)
                        guard !self.processedEmailMessageIds.contains(signature) else { continue }
                        if let parsed = try? EmailParser.parse(subject: subject, body: body) {
                            let pending = PendingTransactionItem(
                                subject: parsed.subject,
                                body: parsed.body,
                                amount: parsed.amount,
                                date: parsed.date,
                                isCredit: parsed.isCredit,
                                suggestedCategory: parsed.suggestedCategory,
                                notes: parsed.description
                            )
                            self.addPendingTransactionIfNew(pending)
                            self.processedEmailMessageIds.insert(signature)
                            self.markEmailProcessed(messageId: signature, receivedAt: received)
                            added += 1
                        }
                    }
                }
            }
        }
        group.notify(queue: .main) {
            completion?(added)
        }
    }
    
    private func addPendingTransactionIfNew(_ item: PendingTransactionItem) {
        // Deduplicate by amount±1 and date±5m and similar subject
        let windowStart = item.date.addingTimeInterval(-300)
        let windowEnd = item.date.addingTimeInterval(300)
        let exists = pendingTransactions.contains { p in
            p.isCredit == item.isCredit &&
            abs(p.amount - item.amount) < 1 &&
            (windowStart...windowEnd).contains(p.date) &&
            p.subject.lowercased().prefix(24) == item.subject.lowercased().prefix(24)
        }
        if !exists { addPendingTransaction(item) }
    }
    
    private func signatureForEmail(subject: String, body: String) -> String {
        let key = (subject + "|" + String(body.prefix(120))).lowercased()
        return String(key.hashValue)
    }

    func fetchAllOutlookEmails(sender: String? = nil, completion: @escaping (Result<Int, Error>) -> Void) {
        OutlookService.shared.fetchRecentMessages(since: lastEmailReceivedAt, sender: sender) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let msgs):
                    self?.fetchedEmails = msgs
                    completion(.success(msgs.count))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    func fetchOutlookEmails(since: Date?, sender: String? = nil, completion: @escaping (Result<Int, Error>) -> Void) {
        OutlookService.shared.fetchRecentMessages(since: since, sender: sender) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let msgs):
                    self?.fetchedEmails = msgs
                    completion(.success(msgs.count))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    // MARK: - Pending Transactions
    private var hasLoadedPendingTransactions = false
    
    private func loadPendingTransactions() {
        if hasLoadedPendingTransactions {
            return
        }
        if let data = UserDefaults.standard.data(forKey: "PendingTransactions"),
           let items = try? JSONDecoder().decode([PendingTransactionItem].self, from: data) {
            pendingTransactions = items
            print("[ExpenseViewModel] Loaded \(items.count) pending transactions from UserDefaults")
        } else {
            print("[ExpenseViewModel] No pending transactions found in UserDefaults")
        }
        hasLoadedPendingTransactions = true
    }
    func savePendingTransactions() {
        if let data = try? JSONEncoder().encode(pendingTransactions) {
            UserDefaults.standard.set(data, forKey: "PendingTransactions")
        }
    }
    func addPendingTransaction(_ item: PendingTransactionItem) {
        pendingTransactions.insert(item, at: 0)
        savePendingTransactions()
        print("[ExpenseViewModel] Added pending transaction: \(item.subject) - \(item.amount) - \(item.date)")
        print("[ExpenseViewModel] Total pending transactions: \(pendingTransactions.count)")
        objectWillChange.send()
    }
    func removePendingTransaction(id: UUID) {
        pendingTransactions.removeAll { $0.id == id }
        savePendingTransactions()
        objectWillChange.send()
    }
    func updatePendingTransactionCategory(id: UUID, to category: TransactionCategory) {
        guard let idx = pendingTransactions.firstIndex(where: { $0.id == id }) else { return }
        pendingTransactions[idx].suggestedCategory = category.rawValue
        savePendingTransactions()
        objectWillChange.send()
    }
    
    // MARK: - Test Functions for Development
    func addTestPendingTransactions() {
        let testTransactions = [
            PendingTransactionItem(
                subject: "INR 105.00 was debited from your A/c no. XX5739",
                body: "Dear Customer, INR 105.00 was debited from your A/c no. XX5739 on 19-09-25, 14:23:24 IST",
                amount: 105.00,
                date: Date(),
                isCredit: false,
                suggestedCategory: "Food & Dining",
                notes: "Test transaction from today"
            ),
            PendingTransactionItem(
                subject: "INR 500.00 was credited to your A/c no. XX5739",
                body: "Dear Customer, INR 500.00 was credited to your A/c no. XX5739 on 18-09-25, 10:15:30 IST",
                amount: 500.00,
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                isCredit: true,
                suggestedCategory: "Salary",
                notes: "Test transaction from yesterday"
            ),
            PendingTransactionItem(
                subject: "INR 250.00 was debited from your A/c no. XX5739",
                body: "Dear Customer, INR 250.00 was debited from your A/c no. XX5739 on 17-09-25, 16:45:12 IST",
                amount: 250.00,
                date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
                isCredit: false,
                suggestedCategory: "Shopping",
                notes: "Test transaction from 2 days ago"
            )
        ]
        
        for transaction in testTransactions {
            addPendingTransaction(transaction)
        }
        
        print("[ExpenseViewModel] Added \(testTransactions.count) test pending transactions")
    }
    func approvePendingTransaction(id: UUID, toAccount: CDAccount?) {
        guard let idx = pendingTransactions.firstIndex(where: { $0.id == id }), let account = toAccount ?? accounts.first else { return }
        let item = pendingTransactions[idx]
        let notes = item.notes ?? item.subject
        
        // Resolve the account inside our viewContext to avoid cross-context relationship crashes
        let accountInContext: CDAccount = {
            if account.managedObjectContext === viewContext { return account }
            return viewContext.object(with: account.objectID) as! CDAccount
        }()
        
        // Always apply user rules/AI categorization at approval time
        let aiSuggested = AICategorizationManager.shared.categorizeTransaction(
            title: item.subject,
            amount: item.amount,
            isCredit: item.isCredit,
            notes: notes
        )
        let finalCategory = TransactionCategory(rawValue: aiSuggested) ?? .other
        addTransaction(
            amount: item.amount,
            category: finalCategory,
            isCredit: item.isCredit,
            account: accountInContext,
            notes: notes,
            date: item.date
        )
        pendingTransactions.remove(at: idx)
        savePendingTransactions()
    }

    // Re-apply user category rules to ALL transactions in Core Data
    func applyUserCategorizationRules() {
        viewContext.perform {
            let request = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
            // No predicate: process all
            do {
                let allTransactions = try self.viewContext.fetch(request)
                var updatedCount = 0
                for txn in allTransactions {
                    let text = "\(txn.wrappedCategory) \(txn.wrappedNotes)"
                    if let rule = AICategorizationManager.shared.findMatchingRule(in: text, isCredit: txn.isCredit) {
                        if rule.excludeFromDashboard, let id = txn.id {
                            self.excludedTransactionIds.insert(id)
                        }
                        if rule.category != txn.wrappedCategory {
                            txn.category = rule.category
                            updatedCount += 1
                        }
                    }
                }
                if updatedCount > 0 {
                    try self.viewContext.save()
                    DispatchQueue.main.async { [weak self] in
                        self?.fetchRecentTransactions()
                        self?.objectWillChange.send()
                    }
                }
                self.saveExcludedTransactions()
            } catch {
                print("Error reapplying categorization rules: \(error)")
            }
        }
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
                metadata: account.metadataDictionary
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
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "CDAccount")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try? viewContext.execute(deleteRequest)
            
            let transactionsFetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "CDTransaction")
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
                if let metadata = accountData.metadata {
                    account.metadataDictionary = metadata
                }
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
    
    func clearAllData() {
        do {
            // Delete all transactions first
            let transactionsFetch = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
            let transactions = try viewContext.fetch(transactionsFetch)
            for transaction in transactions {
                viewContext.delete(transaction)
            }
            
            // Then delete all accounts
            let accountsFetch = NSFetchRequest<CDAccount>(entityName: "CDAccount")
            let accounts = try viewContext.fetch(accountsFetch)
            for account in accounts {
                viewContext.delete(account)
            }
            
            // Save changes
            try viewContext.save()
            
            // Refresh local data
            fetchAccounts()
            fetchRecentTransactions()
        } catch {
            print("Error clearing data: \(error)")
        }
    }
    
    // MARK: - Cloud Sync
    
    func checkCloudDataStatus(completion: @escaping (Bool, Date?) -> Void) {
        guard let userId = AuthenticationManager.shared.currentUser?.id,
              !AuthenticationManager.shared.currentUser!.isGuest else {
            completion(false, nil)
            return
        }
        
        let docRef = db.collection("users").document(userId)
        docRef.getDocument { document, error in
            if let document = document, document.exists {
                let timestamp = document.data()?["lastSynced"] as? Timestamp
                completion(true, timestamp?.dateValue())
            } else {
                completion(false, nil)
            }
        }
    }
    
    func syncToCloud() {
        guard let userId = AuthenticationManager.shared.currentUser?.id,
              !AuthenticationManager.shared.currentUser!.isGuest else { return }
        
        // Don't sync if we're deleting an account
        guard !isDeletingAccount else {
            print("Skipping cloud sync - account deletion in progress")
            return
        }
        
        // Don't sync if temporarily disabled after local deletion
        if let disabledUntil = cloudSyncDisabledUntil, Date() < disabledUntil {
            print("Skipping cloud sync - temporarily disabled until \(disabledUntil)")
            return
        }
        
        Task {
            do {
                let data = try exportData()
                try await syncToCloudAsync(data: data)
            } catch {
                print("Error preparing data for sync: \(error)")
            }
        }
    }
    
    private func syncToCloudAsync(data: Data) async throws {
        guard let userId = AuthenticationManager.shared.currentUser?.id,
              !AuthenticationManager.shared.currentUser!.isGuest else { return }
        
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        let timestamp = Date()
        
        var payload: [String: Any] = [
            "data": jsonObject,
            "lastSynced": timestamp
        ]
        
        // Add device info
        payload["deviceInfo"] = [
            "platform": "iOS",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        
        do {
            try await performRateLimitedFirestoreWrite {
                let docRef = self.db.collection("users").document(userId)
                try await docRef.setData(payload)
            }
            DispatchQueue.main.async {
                self.lastSyncTime = timestamp
            }
            print("✅ Data synced to cloud successfully")
        } catch {
            print("❌ Failed to sync to cloud: \(error)")
            throw error
        }
    }
    
    func loadFromCloud(completion: @escaping (Bool) -> Void) {
        // Don't load from cloud if we're in the middle of deleting an account
        guard !isDeletingAccount else {
            print("Skipping cloud load - account deletion in progress")
            completion(false)
            return
        }
        
        // Don't load from cloud if temporarily disabled after local deletion
        if let disabledUntil = cloudSyncDisabledUntil, Date() < disabledUntil {
            print("Skipping cloud load - temporarily disabled until \(disabledUntil) to prevent account resurrection")
            completion(false)
            return
        }
        
        guard let userId = AuthenticationManager.shared.currentUser?.id,
              !AuthenticationManager.shared.currentUser!.isGuest else {
            completion(false)
            return
        }
        
        let docRef = db.collection("users").document(userId)
        docRef.getDocument { [weak self] document, error in
            guard let self = self,
                  let document = document,
                  document.exists,
                  let data = document.data()?["data"] as? [String: Any] else {
                print("No data found in cloud")
                completion(false)
                return
            }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                
                // Clear existing data before importing
                self.clearAllData()
                
                // Import new data
                try self.importData(from: jsonData)
                // Load user rules if present
                if let rulesAny = document.data()? ["rules"] ?? document.data()? ["userRules"],
                   let rulesArray = rulesAny as? [[String: Any]],
                   let rulesData = try? JSONSerialization.data(withJSONObject: rulesArray),
                   let rules = try? JSONDecoder().decode([UserRule].self, from: rulesData) {
                    AICategorizationManager.shared.replaceUserRules(rules)
                }
                
                if let timestamp = document.data()?["lastSynced"] as? Timestamp {
                    DispatchQueue.main.async {
                        self.lastSyncTime = timestamp.dateValue()
                        UserDefaults.standard.set(timestamp.dateValue(), forKey: "lastSyncTime")
                    }
                }
                
                completion(true)
            } catch {
                print("Error loading data from cloud: \(error)")
                completion(false)
            }
        }
    }
    
    // Call this after any significant data changes
    private func autoSync() {
        // Don't auto-sync if we're deleting an account
        guard !isDeletingAccount,
              AuthenticationManager.shared.currentUser != nil,
              !AuthenticationManager.shared.currentUser!.isGuest else { return }
        syncToCloud()
    }
    
    @objc private func handleSyncToCloud() {
        syncToCloud()
    }
    
    @objc private func handleLoadFromCloud() {
        loadFromCloud { _ in }
    }

    /// Fetches and caches the list of all mutual funds from AMFI
    func fetchAMFIFundList(completion: (() -> Void)? = nil) {
        print("[DEBUG] Fetching AMFI fund list...")
        let url = URL(string: "https://www.amfiindia.com/spages/NAVAll.txt")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else {
                print("[DEBUG] Failed to fetch or decode AMFI fund list.")
                DispatchQueue.main.async { completion?() }
                return
            }
            var fundList: [(String, String)] = []
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                let columns = line.components(separatedBy: ";")
                if columns.count > 3 {
                    let code = columns[0].trimmingCharacters(in: .whitespaces)
                    let name = columns[3].trimmingCharacters(in: .whitespaces)
                    if !code.isEmpty && !name.isEmpty && code != "Scheme Code" {
                        fundList.append((code, name))
                    }
                }
            }
            print("[DEBUG] Parsed \(fundList.count) funds from AMFI list.")
            DispatchQueue.main.async {
                self.amfiFundList = fundList
                completion?()
            }
        }
        task.resume()
    }

    /// Fetches latest NAVs from AMFI and updates mutual fund balances
    func updateMutualFundNAVs(completion: ((Bool) -> Void)? = nil) {
        // Use timestamped URL to bypass caching
        let url = URL(string: "https://www.amfiindia.com/spages/NAVAll.txt?t=07092025064309")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            // Parse NAVs: [SchemeCode: NAV] and name index
            var navs: [String: Double] = [:]
            var nameIndex: [String: (code: String, nav: Double, date: String)] = [:]
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                let columns = line.components(separatedBy: ";")
                if columns.count > 4, let nav = Double(columns[4]) {
                    let schemeCode = columns[0].trimmingCharacters(in: .whitespaces)
                    navs[schemeCode] = nav
                    if columns.count > 3 {
                        let schemeName = columns[3].trimmingCharacters(in: .whitespaces)
                        let dateStr = columns.count > 5 ? columns[5].trimmingCharacters(in: .whitespaces) : ""
                        if !schemeName.isEmpty { nameIndex[schemeName.lowercased()] = (schemeCode, nav, dateStr) }
                    }
                }
            }
            // Update mutual funds
            var updated = false
            for account in self.accounts where account.accountType == AccountType.mutualFund.rawValue {
                var metadata = account.metadataDictionary
                // Units can be stored in metadata["units"] if available; else fall back to creditLimit
                let units: Double = {
                    if let uStr = metadata["units"], let u = Double(uStr) { return u }
                    return account.creditLimit
                }()
                // Resolve scheme code and NAV
                var resolvedCode: String? = metadata["amfiSchemeCode"]
                var nav: Double? = nil
                var navDate: String = ""
                if let code = resolvedCode, let found = navs[code] {
                    nav = found
                } else {
                    let key = account.wrappedAccountName.lowercased()
                    if let tuple = nameIndex[key] {
                        resolvedCode = tuple.code
                        nav = tuple.nav
                        navDate = tuple.date
                    } else if let match = nameIndex.first(where: { key.contains($0.key) || $0.key.contains(key) }) {
                        resolvedCode = match.value.code
                        nav = match.value.nav
                        navDate = match.value.date
                    }
                }
                // Apply updates and persist metadata so UI can show code and timestamps
                if let nav = nav {
                    let newValue = nav * units
                    if abs(account.balance - newValue) > 0.0001 { // lower threshold
                        account.balance = newValue
                        updated = true
                    }
                    if let code = resolvedCode { metadata["amfiSchemeCode"] = code }
                    metadata["lastNAV"] = String(nav)
                    if !navDate.isEmpty { metadata["lastNAVDate"] = navDate }
                    metadata["lastNAVUpdateAt"] = ISO8601DateFormatter().string(from: Date())
                    account.metadataDictionary = metadata
                }
            }
            if updated {
                self.saveContext()
                let now = Date()
                self.lastNAVUpdateAt = now
                UserDefaults.standard.set(now, forKey: "LastNAVUpdateAt")
            }
            DispatchQueue.main.async { completion?(updated) }
        }
        task.resume()
    }

    func importGrowwCSV(from url: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        let didAccess = url.startAccessingSecurityScopedResource()
        
        do {
            // Try UTF-8, then fallback to ISO Latin 1
            let fileContent: String
            if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                fileContent = utf8
            } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
                fileContent = latin1
            } else {
                fileContent = try String(contentsOf: url) // system default
            }
            let lines = fileContent.components(separatedBy: .newlines)
            print("[Groww] Read file with \(lines.count) lines")
            
            var fundsImported = 0
            var holdingsStarted = false
            var headerParsed = false
            var headerIndexes: (name: Int, units: Int, invested: Int, current: Int, folio: Int?)? = nil
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if trimmed.contains("HOLDINGS AS ON") { holdingsStarted = true; print("[Groww] Found holdings section"); continue }
                if !holdingsStarted { continue }

                let columns = parseCSVLine(line)
                print("[Groww] Row columns: \(columns)")
                if !headerParsed {
                    // Parse header to get column positions
                    if columns.contains(where: { $0.caseInsensitiveCompare("Scheme Name") == .orderedSame || $0.caseInsensitiveCompare("Scheme") == .orderedSame }) {
                        let nameIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Scheme Name") == .orderedSame || $0.caseInsensitiveCompare("Scheme") == .orderedSame })
                        let unitsIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Units") == .orderedSame || $0.caseInsensitiveCompare("Unit") == .orderedSame })
                        let investedIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Invested Value") == .orderedSame || $0.caseInsensitiveCompare("Invested") == .orderedSame })
                        let currentIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Current Value") == .orderedSame || $0.caseInsensitiveCompare("Current") == .orderedSame })
                        // Optional folio column (commonly at 5th position)
                        let folioIdx = columns.firstIndex(where: { $0.lowercased().contains("folio") })
                        if let n = nameIdx, let u = unitsIdx, let i = investedIdx, let c = currentIdx {
                            headerIndexes = (n,u,i,c,folioIdx)
                            headerParsed = true
                            print("[Groww] Header indexes -> name: \(n), units: \(u), invested: \(i), current: \(c), folio: \(String(describing: folioIdx))")
                        } else {
                            print("[Groww] Could not find expected header columns in: \(columns)")
                        }
                    }
                    continue
                }

                guard let idx = headerIndexes, columns.count > max(idx.name, idx.units, idx.invested, idx.current) else { continue }
                let schemeName = columns[idx.name].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if schemeName.isEmpty { continue }
                let units = Double(columns[idx.units].replacingOccurrences(of: ",", with: "")) ?? 0
                let investedValue = Double(columns[idx.invested].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "₹", with: "")) ?? 0
                let currentValue = Double(columns[idx.current].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "₹", with: "")) ?? 0
                let folio: String? = {
                    if let fIdx = idx.folio, columns.indices.contains(fIdx) {
                        let val = columns[fIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                        return val.isEmpty ? nil : val
                    }
                    return nil
                }()

                // Update existing account if present; else create
                if let existing = self.accounts.first(where: { $0.wrappedAccountName.caseInsensitiveCompare(schemeName) == .orderedSame && $0.accountType == AccountType.mutualFund.rawValue }) {
                    existing.balance = currentValue
                    existing.creditLimit = investedValue
                    var md = existing.metadataDictionary
                    md["units"] = String(format: "%.4f", units)
                    if let folio = folio { md["folio"] = folio }
                    existing.metadataDictionary = md
                } else {
                    addAccount(
                        name: schemeName,
                        type: .mutualFund,
                        balance: currentValue,
                        creditLimit: investedValue,
                        metadata: {
                            var m: [String:String] = ["units": String(format: "%.4f", units)]
                            if let folio = folio { m["folio"] = folio }
                            return m
                        }()
                    )
                }
                fundsImported += 1
            }
            
            if !holdingsStarted || !headerParsed {
                print("[Groww] Invalid format: holdingsStarted=\(holdingsStarted), headerParsed=\(headerParsed)")
                completion(.failure(GrowwImportError.invalidFormat))
            } else if fundsImported > 0 {
                saveContext()
                completion(.success(fundsImported))
            } else {
                completion(.failure(GrowwImportError.noFundsFound))
            }
        } catch {
            completion(.failure(error))
        }
        if didAccess { url.stopAccessingSecurityScopedResource() }
    }

    // Convenience import from raw CSV text (Paste flow)
    func importGrowwCSV(text: String, completion: @escaping (Result<Int, Error>) -> Void) {
        do {
            let lines = text.components(separatedBy: .newlines)

            var fundsImported = 0
            var holdingsStarted = false
            var headerParsed = false
            var headerIndexes: (name: Int, units: Int, invested: Int, current: Int)? = nil

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if trimmed.contains("HOLDINGS AS ON") { holdingsStarted = true; continue }
                if !holdingsStarted { continue }

                let columns = parseCSVLine(line)
                if !headerParsed {
                    if columns.contains(where: { $0.caseInsensitiveCompare("Scheme Name") == .orderedSame }) {
                        let nameIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Scheme Name") == .orderedSame })
                        let unitsIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Units") == .orderedSame })
                        let investedIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Invested Value") == .orderedSame })
                        let currentIdx = columns.firstIndex(where: { $0.caseInsensitiveCompare("Current Value") == .orderedSame })
                        if let n = nameIdx, let u = unitsIdx, let i = investedIdx, let c = currentIdx {
                            headerIndexes = (n,u,i,c)
                            headerParsed = true
                        }
                    }
                    continue
                }

                guard let idx = headerIndexes, columns.count > max(idx.name, idx.units, idx.invested, idx.current) else { continue }
                let schemeName = columns[idx.name].trimmingCharacters(in: .whitespaces)
                if schemeName.isEmpty { continue }
                let units = Double(columns[idx.units].replacingOccurrences(of: ",", with: "")) ?? 0
                let investedValue = Double(columns[idx.invested].replacingOccurrences(of: ",", with: "")) ?? 0
                let currentValue = Double(columns[idx.current].replacingOccurrences(of: ",", with: "")) ?? 0

                if let existing = self.accounts.first(where: { $0.wrappedAccountName.caseInsensitiveCompare(schemeName) == .orderedSame && $0.accountType == AccountType.mutualFund.rawValue }) {
                    existing.balance = currentValue
                    existing.creditLimit = investedValue
                    var md = existing.metadataDictionary
                    md["units"] = String(format: "%.4f", units)
                    existing.metadataDictionary = md
                } else {
                    addAccount(
                        name: schemeName,
                        type: .mutualFund,
                        balance: currentValue,
                        creditLimit: investedValue,
                        metadata: ["units": String(format: "%.4f", units)]
                    )
                }
                fundsImported += 1
            }

            if fundsImported > 0 {
                saveContext()
                completion(.success(fundsImported))
            } else {
                completion(.failure(GrowwImportError.noFundsFound))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    func addBudget(category: String, amount: Double, month: Date) {
        let newBudget = Budget(context: viewContext)
        newBudget.id = UUID()
        newBudget.category = category
        newBudget.amount = amount
        newBudget.month = month
        
        saveContext()
        fetchBudgets()
    }
    
    func createTransactionFromReceipt(merchant: String, amount: Double, date: Date, notes: String) {
        let transaction = CDTransaction(context: viewContext)
        transaction.id = UUID()
        transaction.amount = amount
        transaction.category = merchant // Store merchant name in category field
        transaction.date = date
        transaction.notes = notes
        transaction.isCredit = false // This is an expense
        
        // Find and set the account (use first available account)
        if let firstAccount = accounts.first {
            transaction.account = firstAccount
        }
        
        saveContext()
        fetchRecentTransactions()
    }
    
    private func fetchBudgets() {
        let request = NSFetchRequest<Budget>(entityName: "Budget")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Budget.month, ascending: false)]
        
        do {
            budgets = try viewContext.fetch(request)
        } catch {
            print("Error fetching budgets: \(error)")
        }
    }
    
    // MARK: - Loan Management
    
    func calculateInterestForAllLoans() {
        let loanManager = LoanManager.shared
        var updated = false
        
        for account in accounts {
            if (account.accountType == AccountType.loan.rawValue || 
                account.accountType == AccountType.personalLoanGiven.rawValue) &&
                loanManager.shouldCalculateInterest(account) {
                loanManager.updateLoanWithInterest(account, in: viewContext)
                updated = true
            }
        }
        
        if updated {
            saveContext()
            fetchAccounts()
        }
    }
    
    func getLoanAccounts() -> [CDAccount] {
        return accounts.filter { account in
            account.accountType == AccountType.loan.rawValue || 
            account.accountType == AccountType.personalLoanGiven.rawValue
        }
    }
    
    func getLoanDetails(for account: CDAccount) -> LoanDetails? {
        return LoanManager.shared.getLoanDetails(account)
    }
    
    // MARK: - Data Deletion
    
    func deleteAllDataFromFirebase(completion: @escaping (Bool) -> Void) {
        guard let userId = AuthenticationManager.shared.currentUser?.id else {
            completion(false)
            return
        }
        
        // Delete all collections for the user
        let collections = ["accounts", "transactions", "budgets", "settings"]
        
        Task {
            do {
                for collection in collections {
                    try await performRateLimitedFirestoreWrite {
                        try await self.db.collection(collection).document(userId).delete()
                    }
                    print("DEBUG: Deleted \(collection) collection")
                }
                
                DispatchQueue.main.async {
                    completion(true)
                }
            } catch {
                print("Error deleting collections: \(error)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
}

enum GrowwImportError: Error, LocalizedError {
    case permissionDenied
    case noFundsFound
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Permission denied to access the selected file."
        case .noFundsFound: return "No mutual fund holdings could be found in this statement."
        case .invalidFormat: return "Could not detect Groww holdings header (Scheme Name/Units/Invested Value/Current Value). Please export the 'Holdings' CSV and try again."
        }
    }
} 

// MARK: - Axis Import Errors
enum AxisImportError: Error, LocalizedError {
    case invalidFormat
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Axis CSV format not recognized. Please ensure the file has headers like TransactionDate/Date, PARTICULARS/Narration, Debit/Withdrawal, Credit/Deposit."
        case .noTransactionsFound:
            return "No transactions were found to import from the Axis CSV."
        }
    }
}

