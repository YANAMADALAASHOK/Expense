import SwiftUI
import CoreData
import FirebaseFirestore

class ExpenseViewModel: ObservableObject {
    let viewContext: NSManagedObjectContext
    private let db = Firestore.firestore()
    private var isDeletingAccount = false
    
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
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        loadCustomCategories()
        loadSubcategories()
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
            // Check if we have local data first
            if accounts.isEmpty && recentTransactions.isEmpty {
                loadFromCloud { _ in }
            }
        }
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
    private func loadExcludedTransactions() {
        if let raw = UserDefaults.standard.array(forKey: "ExcludedTransactions") as? [String] {
            let ids = raw.compactMap { UUID(uuidString: $0) }
            excludedTransactionIds = Set(ids)
        }
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
    private func loadCustomCategories() {
        if let savedCategories = UserDefaults.standard.stringArray(forKey: "CustomCategories") {
            customCategories = savedCategories
        }
    }
    private func loadSubcategories() {
        if let data = UserDefaults.standard.data(forKey: "SubcategoriesByParent"),
           let dict = try? JSONDecoder().decode([String: [String]].self, from: data) {
            subcategoriesByParent = dict
        }
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
        
        viewContext.performAndWait {
            do {
                // Delete the account (transactions will be deleted automatically due to cascade rule)
                viewContext.delete(account)
                
                // Save changes
                try viewContext.save()
                print("Successfully deleted account: \(account.wrappedAccountName)")
                
                // Refresh data on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.fetchAccounts()
                    self?.fetchRecentTransactions()
                    self?.objectWillChange.send()
                    
                    // Sync to cloud after a short delay to ensure local changes are stable
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.syncToCloud()
                        self?.isDeletingAccount = false
                    }
                }
            } catch {
                print("Error deleting account: \(error)")
                // Try to reset context and refresh
                viewContext.rollback()
                DispatchQueue.main.async { [weak self] in
                    self?.refreshData()
                    self?.isDeletingAccount = false
                }
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
            // 1. Create debit transaction from funding account (bank/cash)
            let debitTxn = CDTransaction(context: viewContext)
            debitTxn.id = UUID()
            debitTxn.amount = amount
            debitTxn.category = TransactionCategory.creditCardPayment.rawValue
            debitTxn.isCredit = false // debit from funding account reduces balance
            debitTxn.account = fromAccount
            debitTxn.notes = "Credit Card Payment to \(toCreditCardAccount.wrappedAccountName) - \(notes)"
            debitTxn.date = date

            // 2. Create credit transaction to credit card account (reduces liability)
            let creditTxn = CDTransaction(context: viewContext)
            creditTxn.id = UUID()
            creditTxn.amount = amount
            creditTxn.category = TransactionCategory.creditCardPayment.rawValue
            creditTxn.isCredit = true // credit to credit card reduces card balance per app logic
            creditTxn.account = toCreditCardAccount
            creditTxn.notes = "Payment from \(fromAccount.wrappedAccountName) - \(notes)"
            creditTxn.date = date

            // 3. Update balances
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

            // Create new paired transactions
            let debitTxn = CDTransaction(context: viewContext)
            debitTxn.id = UUID()
            debitTxn.amount = amount
            debitTxn.category = TransactionCategory.creditCardPayment.rawValue
            debitTxn.isCredit = false
            debitTxn.account = fundingAccount
            debitTxn.notes = "Credit Card Payment to \(paidCard.wrappedAccountName) - \(notes)"
            debitTxn.date = date

            let creditTxn = CDTransaction(context: viewContext)
            creditTxn.id = UUID()
            creditTxn.amount = amount
            creditTxn.category = TransactionCategory.creditCardPayment.rawValue
            creditTxn.isCredit = true
            creditTxn.account = paidCard
            creditTxn.notes = "Payment from \(fundingAccount.wrappedAccountName) - \(notes)"
            creditTxn.date = date

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
    
    func updateTransaction(_ transaction: CDTransaction, amount: Double, category: TransactionCategory, isCredit: Bool, notes: String?, updateRules: Bool = true) {
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
                if updateRules {
                    // Learn a user rule from this edit (use notes or category text as pattern)
                    let patternSource = (notes?.isEmpty == false ? notes! : transaction.wrappedNotes)
                    if !patternSource.isEmpty {
                        AICategorizationManager.shared.addOrUpdateRule(pattern: patternSource, category: category.rawValue)
                    }
                }
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
    
    private func fetchAccounts() {
        let request = NSFetchRequest<CDAccount>(entityName: "CDAccount")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDAccount.accountName, ascending: true)]
        
        do {
            accounts = try viewContext.fetch(request)
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
    private func loadEmailIngestionState() {
        if let arr = UserDefaults.standard.array(forKey: "ProcessedEmailMessageIds") as? [String] {
            processedEmailMessageIds = Set(arr)
        }
        if let ts = UserDefaults.standard.object(forKey: "LastEmailReceivedAt") as? Date {
            lastEmailReceivedAt = ts
        }
    }
    func persistEmailIngestionState() {
        UserDefaults.standard.set(Array(processedEmailMessageIds), forKey: "ProcessedEmailMessageIds")
        if let ts = lastEmailReceivedAt {
            UserDefaults.standard.set(ts, forKey: "LastEmailReceivedAt")
        }
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
    private func loadPendingTransactions() {
        if let data = UserDefaults.standard.data(forKey: "PendingTransactions"),
           let items = try? JSONDecoder().decode([PendingTransactionItem].self, from: data) {
            pendingTransactions = items
        }
    }
    private func savePendingTransactions() {
        if let data = try? JSONEncoder().encode(pendingTransactions) {
            UserDefaults.standard.set(data, forKey: "PendingTransactions")
        }
    }
    func addPendingTransaction(_ item: PendingTransactionItem) {
        pendingTransactions.insert(item, at: 0)
        savePendingTransactions()
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
    func approvePendingTransaction(id: UUID, toAccount: CDAccount?) {
        guard let idx = pendingTransactions.firstIndex(where: { $0.id == id }), let account = toAccount ?? accounts.first else { return }
        let item = pendingTransactions[idx]
        let notes = item.notes ?? item.subject
        // Use AI/user rules categorization at approval time using item details
        var finalCategory = TransactionCategory(rawValue: item.suggestedCategory)
        if finalCategory == .other {
            let aiSuggested = AICategorizationManager.shared.categorizeTransaction(
                title: item.subject,
                amount: item.amount,
                isCredit: item.isCredit,
                notes: notes
            )
            finalCategory = TransactionCategory(rawValue: aiSuggested)
        }
        addTransaction(amount: item.amount, category: finalCategory, isCredit: item.isCredit, account: account, notes: notes, date: item.date)
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
        
        do {
            let data = try exportData()
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            let timestamp = Date()
            let docRef = db.collection("users").document(userId)
            
            var payload: [String: Any] = [
                "data": jsonObject,
                "lastSynced": timestamp
            ]
            if let rulesData = try? JSONEncoder().encode(AICategorizationManager.shared.getUserRules()),
               let rulesJson = try? JSONSerialization.jsonObject(with: rulesData) as? [[String: Any]] {
                payload["rules"] = rulesJson
            }

            docRef.setData(payload, merge: true) { [weak self] error in
                if let error = error {
                    print("Error syncing data: \(error)")
                } else {
                    DispatchQueue.main.async {
                        self?.lastSyncTime = timestamp
                        UserDefaults.standard.set(timestamp, forKey: "lastSyncTime")
                    }
                }
            }
        } catch {
            print("Error preparing data for sync: \(error)")
        }
    }
    
    func loadFromCloud(completion: @escaping (Bool) -> Void) {
        // Don't load from cloud if we're in the middle of deleting an account
        guard !isDeletingAccount else {
            print("Skipping cloud load - account deletion in progress")
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
        let url = URL(string: "https://www.amfiindia.com/spages/NAVAll.txt")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            // Parse NAVs: [SchemeCode: NAV]
            var navs: [String: Double] = [:]
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                let columns = line.components(separatedBy: ";")
                if columns.count > 4, let nav = Double(columns[4]) {
                    let schemeCode = columns[0].trimmingCharacters(in: .whitespaces)
                    navs[schemeCode] = nav
                }
            }
            // Update mutual funds
            var updated = false
            for account in self.accounts where account.accountType == AccountType.mutualFund.rawValue {
                let metadata = account.metadataDictionary
                if let code = metadata["amfiSchemeCode"], let nav = navs[code], let units = account.creditLimit as Double? {
                    let newValue = nav * units
                    if abs(account.balance - newValue) > 0.01 {
                        account.balance = newValue
                        updated = true
                    }
                }
            }
            if updated { self.saveContext() }
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
            var headerIndexes: (name: Int, units: Int, invested: Int, current: Int)? = nil
            
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
                        if let n = nameIdx, let u = unitsIdx, let i = investedIdx, let c = currentIdx {
                            headerIndexes = (n,u,i,c)
                            headerParsed = true
                            print("[Groww] Header indexes -> name: \(n), units: \(u), invested: \(i), current: \(c)")
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

                // Update existing account if present; else create
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
        
        let db = Firestore.firestore()
        
        // Delete all collections for the user
        let collections = ["accounts", "transactions", "budgets", "settings"]
        let group = DispatchGroup()
        var success = true
        
        for collection in collections {
            group.enter()
            db.collection(collection).document(userId).delete { error in
                if let error = error {
                    print("Error deleting \(collection): \(error)")
                    success = false
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(success)
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