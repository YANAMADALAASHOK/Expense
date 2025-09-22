import SwiftUI
import CoreData

struct AccountsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingAddAccount = false
    @State private var showingAddMutualFund = false
    @State private var showingAddPersonalLoan = false
    @State private var showingLoanPayment = false
    @State private var showingAccountTransactions = false
    @State private var selectedAccount: CDAccount?
    @State private var selectedAccountForTransactions: CDAccount?
    @State private var isRefreshing = false
    @State private var selectedAccountType: AccountType?
    @State private var isUpdatingNAVs = false
    @State private var showingAddInsurance = false
    @State private var editingInsurance: InsurancePolicy?
    @State private var insurancePolicies: [InsurancePolicy] = []
    @State private var isFetchingStatements = false
    @State private var fetchingProgress = ""
    
    private var assetAccounts: [CDAccount] {
        viewModel.accounts.filter { $0.wrappedAccountType.isAsset }
    }
    
    private var bankAccounts: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.bankAccount.rawValue }
    }
    private var bankAccountsTotal: Double { bankAccounts.reduce(0) { $0 + $1.balance } }
    
    private var mutualFunds: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.mutualFund.rawValue }
    }
    private var mutualFundsTotal: Double { mutualFunds.reduce(0) { $0 + $1.balance } }
    
    private var liabilityAccounts: [CDAccount] {
        viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }
    }
    
    private var loans: [CDAccount] {
        liabilityAccounts.filter { $0.accountType == AccountType.loan.rawValue }
    }
    private var loansOutstanding: Double { loans.reduce(0) { $0 + $1.balance } }
    
    private var creditCards: [CDAccount] {
        liabilityAccounts.filter { $0.accountType == AccountType.creditCard.rawValue }
    }
    private var creditCardsOutstanding: Double { creditCards.reduce(0) { $0 + $1.balance } }
    
    private var personalLoansGiven: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }
    }
    private var personalLoansOutstanding: Double { personalLoansGiven.reduce(0) { $0 + $1.balance } }
    
    var body: some View {
        NavigationView {
            List {
                Section { BalanceSummarySection(accounts: viewModel.accounts) }
                assetsSection
                liabilitiesSection
                insurancesSection
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AddAccountMenu(
                        showingAddAccount: $showingAddAccount,
                        showingAddMutualFund: $showingAddMutualFund,
                        showingAddPersonalLoan: $showingAddPersonalLoan
                    )
                }
            }
            .refreshable {
                refreshData()
            }
            .onAppear {
                viewModel.fetchAccounts()
                
                // Auto-fetch credit card statements when view appears
                Task {
                    await autoFetchCreditCardStatements()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetCreditCardData"))) { _ in
                print("DEBUG: Received reset credit card data notification")
                fetchCreditCardStatements()
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(viewModel: viewModel)
                    .onDisappear {
                        selectedAccountType = nil
                    }
            }
            .sheet(isPresented: $showingAddMutualFund) {
                AddMutualFundView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAddPersonalLoan) {
                AddPersonalLoanGivenView(viewModel: viewModel)
                    .onDisappear {
                        selectedAccountType = nil
                    }
            }
            .sheet(item: $selectedAccount) { account in
                if account.accountType == AccountType.personalLoanGiven.rawValue {
                    EditPersonalLoanGivenView(viewModel: viewModel, account: account)
                } else {
                    EditAccountView(viewModel: viewModel, account: account)
                }
            }
            .sheet(isPresented: $showingLoanPayment) {
                LoanPaymentView(viewModel: viewModel, preSelectedLoan: selectedAccount)
            }
            .sheet(isPresented: $showingAccountTransactions) {
                if let account = selectedAccountForTransactions {
                    AccountTransactionsView(viewModel: viewModel, account: account)
                }
            }
            .sheet(isPresented: $showingAddInsurance) {
                AddInsurancePolicyView(
                    accounts: viewModel.accounts,
                    initial: nil,
                    onSave: addInsurancePolicy,
                    onDelete: nil
                )
            }
            .sheet(item: $editingInsurance) { policy in
                AddInsurancePolicyView(
                    accounts: viewModel.accounts,
                    initial: policy,
                    onSave: updateInsurancePolicy,
                    onDelete: deleteInsurancePolicy
                )
            }
        }
    }
    
    private func refreshData() {
        isRefreshing = true
        viewModel.refreshData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRefreshing = false
        }
    }
    
    private func recordLoanInterest(for account: CDAccount) {
        let metadata = account.metadataDictionary
        guard let rateString = metadata["interestRate"],
              let rate = Double(rateString) else {
            return
        }
        
        // Calculate interest based on current balance
        let balance = account.balance
        let monthlyRate = rate / 12.0 / 100.0  // Convert annual rate to monthly decimal
        let interest = balance * monthlyRate
        
        // Add interest transaction
        viewModel.addTransaction(
            amount: interest,
            category: .interest,
            isCredit: false,  // Debit because it increases the loan amount
            account: account,
            notes: "Monthly Interest @ \(rate)% per annum",
            date: Date()
        )
    }
}

// MARK: - Supporting Views
extension AccountsView {
    @ViewBuilder
    private var assetsSection: some View {
        Section("Assets") {
            bankAccountsGroup
            mutualFundsGroup
            personalLoansGroup
        }
    }
    
    @ViewBuilder
    private var bankAccountsGroup: some View {
        DisclosureGroup {
            ForEach(bankAccounts) { account in
                AccountRow(account: account)
                    .onTapGesture { openTransactions(for: account) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { openTransactions(for: account) } label: { Label("Transactions", systemImage: "list.bullet") }
                            .tint(.blue)
                        Button { editAccount(account) } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.orange)
                        Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        } label: {
            HStack {
                Text("Bank Accounts")
                Spacer()
                Text(bankAccountsTotal, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var mutualFundsGroup: some View {
        DisclosureGroup {
            ForEach(mutualFunds) { account in
                MutualFundRow(account: account)
                    .onTapGesture { editAccount(account) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { openTransactions(for: account) } label: { Label("Transactions", systemImage: "list.bullet") }.tint(.blue)
                        Button { editAccount(account) } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                        Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        } label: {
            HStack {
                Text("Mutual Funds")
                Spacer()
                Text(mutualFundsTotal, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var personalLoansGroup: some View {
        DisclosureGroup {
            ForEach(personalLoansGiven) { account in
                NavigationLink(destination: LoanDetailsView(viewModel: viewModel, account: account)) {
                    AccountRow(account: account)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { selectedAccount = account } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                    Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } label: {
            HStack {
                Text("Personal Loans Given")
                Spacer()
                Text(personalLoansOutstanding, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var liabilitiesSection: some View {
        Section("Liabilities") {
            creditCardsGroup
            loansGroup
        }
    }
    @ViewBuilder
    private var creditCardsGroup: some View {
        DisclosureGroup {
            // Auto-fetch status indicator (no manual button)
            if isFetchingStatements {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(360))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isFetchingStatements)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-fetching Statements...")
                        Button("Fetch Credit Card Statements") {
                            fetchCreditCardStatements()
                        }
                        .disabled(isFetchingStatements)
                        
                        Button("Reset & Reload All Statements") {
                            resetAndReloadStatements()
                        }
                        .disabled(isFetchingStatements)
                        
                        if !fetchingProgress.isEmpty {
                            Text(fetchingProgress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            ForEach(creditCards) { account in
                AccountRow(account: account)
                    .onTapGesture { openTransactions(for: account) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { openTransactions(for: account) } label: { Label("Transactions", systemImage: "list.bullet") }.tint(.blue)
                        Button { selectedAccount = account } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                        Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        } label: {
            HStack {
                Text("Credit Cards")
                Spacer()
                Text(creditCardsOutstanding, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    @ViewBuilder
    private var loansGroup: some View {
        DisclosureGroup {
            ForEach(loans) { account in
                NavigationLink(destination: LoanDetailsView(viewModel: viewModel, account: account)) {
                    AccountRow(account: account)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { selectedAccount = account; showingLoanPayment = true } label: { Label("Pay Loan", systemImage: "indianrupeesign.circle") }.tint(.green)
                    Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } label: {
            HStack {
                Text("Loans")
                Spacer()
                Text(loansOutstanding, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    // Small helpers to keep closures simple
    private func openTransactions(for account: CDAccount) {
        selectedAccount = nil
        showingAddAccount = false
        showingAddMutualFund = false
        showingAddPersonalLoan = false
        showingLoanPayment = false
        selectedAccountForTransactions = account
        DispatchQueue.main.async { showingAccountTransactions = true }
    }
    private func editAccount(_ account: CDAccount) {
        selectedAccountForTransactions = nil
        showingAccountTransactions = false
        selectedAccount = account
    }
    
    // Insurance management methods
    private func loadInsurancePolicies() {
        let insuranceManager = InsuranceManager.shared
        insurancePolicies = insuranceManager.loadPolicies()
    }
    
    private func processInsurancePremiums() {
        let insuranceManager = InsuranceManager.shared
        insuranceManager.processInsurancePremiums(context: viewModel.viewContext, accounts: viewModel.accounts)
    }
    
    private func addInsurancePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.append(policy)
        saveInsurancePolicies()
    }
    
    private func updateInsurancePolicy(_ policy: InsurancePolicy) {
        if let index = insurancePolicies.firstIndex(where: { $0.id == policy.id }) {
            insurancePolicies[index] = policy
            saveInsurancePolicies()
        }
    }
    
    private func deleteInsurancePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.removeAll { $0.id == policy.id }
        saveInsurancePolicies()
        
        // Clean up the last processed date
        let lastProcessedKey = "insurance_\(policy.id)_lastProcessed"
        UserDefaults.standard.removeObject(forKey: lastProcessedKey)
    }
    
    private func saveInsurancePolicies() {
        let insuranceManager = InsuranceManager.shared
        insuranceManager.savePolicies(insurancePolicies)
    }
    
    @ViewBuilder
    private var insurancesSection: some View {
        Section("Insurance Policies") {
            if insurancePolicies.isEmpty {
                Text("No insurance policies added yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(insurancePolicies) { policy in
                    InsurancePolicyRowView(
                        policy: policy,
                        accounts: viewModel.accounts
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingInsurance = policy }
                    .swipeActions(edge: .trailing) {
                        Button("Edit") { editingInsurance = policy }
                            .tint(.orange)
                        Button("Delete", role: .destructive) { deleteInsurancePolicy(policy) }
                    }
                }
            }
            
            Button {
                showingAddInsurance = true
            } label: {
                Label("Add Insurance Policy", systemImage: "plus")
            }
        }
    }
    
    @MainActor
    private func fetchCreditCardStatements() {
        Task {
            await manualFetchCreditCardStatements(forceRefresh: true)
        }
    }
    
    @MainActor
    private func resetAndReloadStatements() {
        // Clear the last fetch timestamp to force a fresh fetch
        UserDefaults.standard.removeObject(forKey: "lastCreditCardAutoFetch")
        print("DEBUG: Reset fetch timer - will reload all statements")
        
        Task {
            await manualFetchCreditCardStatements(forceRefresh: true)
        }
    }
    
    @MainActor
    private func autoFetchCreditCardStatements() async {
        await manualFetchCreditCardStatements(forceRefresh: false)
    }
    
    @MainActor
    private func manualFetchCreditCardStatements(forceRefresh: Bool = true) async {
        // Only auto-fetch if not already fetching
        guard !isFetchingStatements else { return }
        
        // Check if we should auto-fetch (e.g., once per day) unless force refresh
        let lastFetchKey = "lastCreditCardAutoFetch"
        let lastFetch = UserDefaults.standard.object(forKey: lastFetchKey) as? Date
        let shouldFetch = forceRefresh || lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 24 * 60 * 60 // 24 hours
        
        if shouldFetch {
            print("DEBUG: \(forceRefresh ? "Manual" : "Auto")-fetching credit card statements...")
            UserDefaults.standard.set(Date(), forKey: lastFetchKey)
            
            // Add timeout protection for the entire fetch process
            await withTimeout(seconds: 300, operation: { // 5 minute timeout
                await performAutomatedStatementFetch()
            })
        } else {
            print("DEBUG: Skipping auto-fetch - already fetched recently")
        }
    }
    
    @MainActor
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            // Add the main operation
            group.addTask {
                do {
                    return try await operation()
                } catch {
                    print("DEBUG: Operation failed with error: \(error)")
                    return nil
                }
            }
            
            // Add timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                print("DEBUG: Operation timed out after \(seconds) seconds")
                return nil
            }
            
            // Return the first completed task result
            let result = await group.next()
            group.cancelAll() // Cancel remaining tasks
            return result ?? nil
        }
    }
    
    @MainActor
    private func performAutomatedStatementFetch() async {
        isFetchingStatements = true
        fetchingProgress = "Connecting to email..."
        
        // Ensure we reset the fetching state even if something goes wrong
        defer {
            isFetchingStatements = false
            fetchingProgress = ""
        }
        
        do {
            // Step 1: Fetch emails from Axis Bank with timeout
            fetchingProgress = "Fetching emails from cc.statements@axisbank.com..."
            let outlookService = OutlookService.shared
            
            // Add timeout for email fetching (2 minutes)
            guard let emails = await withTimeout(seconds: 120, operation: {
                try await outlookService.fetchEmails(from: "cc.statements@axisbank.com")
            }) else {
                print("DEBUG: Email fetching timed out")
                fetchingProgress = "Email fetch timed out - will retry next time"
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Show message for 2 seconds
                return
            }
            
            print("DEBUG: Automated fetch - Found \(emails.count) emails")
            
            // Step 2: Process each email with PDF attachments
            var processedCount = 0
            // Sort emails by date (oldest first, newest last) so latest bill sets final balance
            let sortedEmails = emails.sorted { email1, email2 in
                let date1 = ISO8601DateFormatter().date(from: email1.receivedDateTime) ?? Date.distantPast
                let date2 = ISO8601DateFormatter().date(from: email2.receivedDateTime) ?? Date.distantPast
                return date1 < date2
            }
            
            let totalEmails = sortedEmails.count
            print("DEBUG: Processing \(totalEmails) emails in chronological order (oldest first)")
            
            for (index, email) in sortedEmails.enumerated() {
                fetchingProgress = "Processing email \(index + 1) of \(totalEmails)..."
                
                do {
                    // Add timeout for attachment fetching (30 seconds per email)
                    guard let attachments = await withTimeout(seconds: 30, operation: {
                        try await outlookService.fetchAttachments(for: email.id)
                    }) else {
                        print("DEBUG: Attachment fetching timed out for email: \(email.subject ?? "Unknown")")
                        continue
                    }
                    
                    let pdfAttachments = attachments.filter { attachment in
                        attachment.contentType?.lowercased().contains("pdf") == true ||
                        attachment.name?.lowercased().hasSuffix(".pdf") == true
                    }
                    
                    if !pdfAttachments.isEmpty {
                        fetchingProgress = "Processing PDF from \(email.subject ?? "Unknown")..."
                        
                        for attachment in pdfAttachments {
                            // Add timeout for PDF download and processing (60 seconds per PDF)
                            let success = await withTimeout(seconds: 60, operation: {
                                if let pdfData = try await outlookService.downloadAttachment(messageId: email.id, attachmentId: attachment.id) {
                                    
                                    // Step 3: Parse PDF and create/update accounts
                                    await processPDFStatement(
                                        pdfData: pdfData,
                                        pdfFileName: attachment.name ?? "Statement.pdf",
                                        email: email
                                    )
                                    return true
                                }
                                return false
                            })
                            
                            if success == true {
                                processedCount += 1
                            } else {
                                print("DEBUG: PDF processing timed out or failed for: \(attachment.name ?? "Unknown")")
                            }
                        }
                    }
                } catch {
                    print("DEBUG: Error processing email \(index + 1): \(error.localizedDescription)")
                    // Continue with next email instead of failing completely
                    continue
                }
            }
            
            fetchingProgress = "Completed! Processed \(processedCount) statements."
            
            // Step 4: Refresh accounts and mark bills appropriately
            viewModel.fetchAccounts()
            
            // Wait a moment to show completion message
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
        } catch {
            fetchingProgress = "Error: \(error.localizedDescription)"
            print("DEBUG: Automated fetch error: \(error)")
            
            // Wait to show error message
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        }
    }
    
    // Helper function to detect payment transactions
    private func isPaymentTransaction(_ description: String) -> Bool {
        let paymentKeywords = [
            "BBPS PAYMENT", "PAYMENT RECEIVED", "PAYMENT THANK YOU",
            "CREDIT RECEIVED", "AMOUNT RECEIVED", "PAYMENT PROCESSED",
            "ONLINE PAYMENT", "NEFT PAYMENT", "RTGS PAYMENT", "UPI PAYMENT",
            "IMPS PAYMENT", "CHEQUE PAYMENT", "CASH PAYMENT", "AUTOPAY",
            "REFUND", "REVERSAL", "CASHBACK", "REWARD POINTS"
        ]
        
        let upperDescription = description.uppercased()
        return paymentKeywords.contains { upperDescription.contains($0) }
    }
    
    // Helper function to automatically mark bills as paid when payment transactions match
    private func checkAndMarkBillAsPaid(account: CDAccount, paymentAmount: Double, paymentDate: Date, paymentDescription: String) {
        let metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        // Look for bills that match this payment amount
        let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
        
        for key in billHistoryKeys {
            if let statementJsonString = metadata[key],
               let statementJsonData = statementJsonString.data(using: .utf8),
               let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String] {
                
                let statementDate = statementData["statementDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
                let dueAmount = statementData["dueAmount"].flatMap { Double($0) } ?? 0.0
                let dueDate = statementData["dueDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
                
                // Check if payment amount matches due amount (within ₹1 tolerance)
                // and payment is after statement date but before or on due date + 30 days grace period
                let gracePeriod: TimeInterval = 30 * 24 * 60 * 60 // 30 days
                let maxPaymentDate = dueDate.addingTimeInterval(gracePeriod)
                
                if abs(paymentAmount - dueAmount) <= 1.0 && 
                   paymentDate >= statementDate && 
                   paymentDate <= maxPaymentDate {
                    
                    // Check if this bill is not already marked as paid
                    if !hasBillPayment(account: account, statementDate: statementDate, dueAmount: dueAmount) {
                        print("DEBUG: 🎯 AUTO-PAYMENT DETECTED!")
                        print("DEBUG: - Payment: ₹\(paymentAmount) on \(paymentDate)")
                        print("DEBUG: - Bill Due: ₹\(dueAmount) on \(dueDate)")
                        print("DEBUG: - Statement: \(statementDate)")
                        print("DEBUG: - Description: \(paymentDescription)")
                        print("DEBUG: - Amount difference: ₹\(abs(paymentAmount - dueAmount))")
                        
                        // Mark this bill as automatically paid by updating the transaction notes
                        // The existing payment transaction already marks it as paid
                        // We just need to log this for user awareness
                        print("DEBUG: ✅ Bill automatically marked as paid!")
                        
                        return // Found matching bill, no need to check others
                    }
                }
            }
        }
    }
    
    // Helper function to check if a bill has been paid
    private func hasBillPayment(account: CDAccount, statementDate: Date, dueAmount: Double) -> Bool {
        // Check if there are payment transactions for this specific bill
        // Look for payments after statement date
        
        let paymentTransactions = account.transactionsArray.filter { transaction in
            transaction.wrappedCategory.contains("Payment") && 
            transaction.isCredit && 
            transaction.wrappedDate >= statementDate
        }
        
        for transaction in paymentTransactions {
            // Check if amount matches (allow ₹1 variance)
            if abs(transaction.amount - dueAmount) < 1.0 {
                return true
            }
        }
        
        return false
    }
    
    // Helper function to save bill metadata for UI display
    private func saveBillMetadata(account: CDAccount, billInfo: CreditCardBillInfo, pdfFileName: String) {
        var metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        // Create a unique key for this statement
        let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
        
        // Create bill data dictionary (totalAmount is already the current usage)
        let billData: [String: String] = [
            "statementDate": dateFormatter.string(from: billInfo.statementDate),
            "dueDate": dateFormatter.string(from: billInfo.dueDate),
            "dueAmount": String(billInfo.dueAmount),
            "currentUsage": String(billInfo.totalAmount),
            "creditLimit": String(billInfo.creditLimit ?? 0.0),
            "bankName": billInfo.bankName,
            "cardNumber": billInfo.cardNumber,
            "pdfFileName": pdfFileName
        ]
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: billData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            metadata[statementKey] = jsonString
            
            // Update account metadata
            let metadataString = metadata.compactMapValues { $0 }.reduce(into: "") { result, pair in
                result += "\(pair.key)=\(pair.value)\n"
            }
            account.metadata = metadataString.data(using: .utf8)
            
            print("DEBUG: 💾 Saved bill metadata for statement: \(billInfo.statementDate)")
            print("DEBUG: - Key: \(statementKey)")
            print("DEBUG: - Due Amount: ₹\(billInfo.dueAmount)")
            print("DEBUG: - PDF: \(pdfFileName)")
        }
    }
    
    
    @MainActor
    private func processPDFStatement(pdfData: Data, pdfFileName: String, email: OutlookMessage) async {
        // Save PDF temporarily
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(pdfFileName)
        do {
            try pdfData.write(to: tempURL)
            
            // Parse PDF
            let parser = PDFTransactionParser.shared
            guard let billInfo = parser.parsePDF(at: tempURL) else {
                print("DEBUG: Failed to parse PDF: \(pdfFileName)")
                return
            }
            
            print("DEBUG: Automated - Parsed PDF: \(billInfo.bankName) ****\(billInfo.cardNumber), Due: ₹\(billInfo.dueAmount)")
            
            // Create or find existing credit card account
            let accountName = "\(billInfo.bankName) ****\(billInfo.cardNumber)"
            let existingAccount = viewModel.accounts.first(where: { account in
                account.wrappedAccountName == accountName && account.wrappedAccountType == AccountType.creditCard
            })
            
            let dateFormatter = ISO8601DateFormatter()
            
            let creditCardAccount: CDAccount
            if let existing = existingAccount {
                creditCardAccount = existing
                print("DEBUG: Automated - Using existing account: \(accountName)")
                
                // Update metadata
                var metadata = existing.metadataDictionary
                
                // Store this statement in bill history
                let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
                var statementData: [String: String] = [:]
                statementData["statementDate"] = dateFormatter.string(from: billInfo.statementDate)
                statementData["dueDate"] = dateFormatter.string(from: billInfo.dueDate)
                statementData["dueAmount"] = String(billInfo.dueAmount)
                statementData["currentUsage"] = String(billInfo.totalAmount)
                statementData["creditLimit"] = String(billInfo.creditLimit ?? 0)
                statementData["pdfFileName"] = pdfFileName
                statementData["transactionCount"] = String(billInfo.transactions.count)
                statementData["emailSubject"] = email.subject ?? ""
                statementData["emailDate"] = email.receivedDateTime
                
                if let statementJsonData = try? JSONSerialization.data(withJSONObject: statementData),
                   let statementJsonString = String(data: statementJsonData, encoding: .utf8) {
                    metadata[statementKey] = statementJsonString
                }
                
                // Check if this statement is newer than the last one
                var shouldUpdateAccountBalance = true
                if let lastDateString = metadata["lastStatementDate"],
                   let lastDate = dateFormatter.date(from: lastDateString) {
                    shouldUpdateAccountBalance = billInfo.statementDate >= lastDate
                    print("DEBUG: Bill date comparison: \(billInfo.statementDate) >= \(lastDate) = \(shouldUpdateAccountBalance)")
                } else {
                    print("DEBUG: No previous bill date found, will update balance")
                }
                
                // Only update account balance if this bill is newer or same date
                if shouldUpdateAccountBalance {
                    metadata["lastStatementDate"] = dateFormatter.string(from: billInfo.statementDate)
                    metadata["lastDueDate"] = dateFormatter.string(from: billInfo.dueDate)
                    metadata["lastDueAmount"] = String(billInfo.dueAmount)
                    metadata["creditLimit"] = String(billInfo.creditLimit ?? 0)
                    metadata["lastCurrentUsage"] = String(billInfo.totalAmount)
                    
                    // Simple formula: Current Usage = Credit Limit - Available Credit Limit
                    creditCardAccount.balance = billInfo.totalAmount
                    creditCardAccount.creditLimit = billInfo.creditLimit ?? 0
                    
                    print("DEBUG: ✅ Updated balance from newer bill: ₹\(billInfo.totalAmount)")
                } else {
                    print("DEBUG: ❌ Skipping balance update - bill is older: \(billInfo.statementDate)")
                }
                
                creditCardAccount.metadataDictionary = metadata
                
            } else {
                // Create new account
                creditCardAccount = CDAccount(context: viewModel.viewContext)
                creditCardAccount.id = UUID()
                creditCardAccount.accountName = accountName
                creditCardAccount.accountType = AccountType.creditCard.rawValue
                // Simple formula: Current Usage = Credit Limit - Available Credit Limit
                creditCardAccount.balance = billInfo.totalAmount
                creditCardAccount.creditLimit = billInfo.creditLimit ?? 0
                
                print("DEBUG: ✅ Created new account with balance: ₹\(billInfo.totalAmount)")
                
                var metadata: [String: String] = [:]
                
                metadata["bankName"] = billInfo.bankName
                metadata["cardNumber"] = billInfo.cardNumber
                metadata["lastStatementDate"] = dateFormatter.string(from: billInfo.statementDate)
                metadata["lastDueDate"] = dateFormatter.string(from: billInfo.dueDate)
                metadata["lastDueAmount"] = String(billInfo.dueAmount)
                metadata["creditLimit"] = String(billInfo.creditLimit ?? 0)
                metadata["lastPDFFileName"] = pdfFileName
                metadata["lastEmailSubject"] = email.subject ?? ""
                metadata["lastEmailDate"] = email.receivedDateTime
                
                // Store statement history
                let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
                var statementData: [String: String] = [:]
                statementData["statementDate"] = dateFormatter.string(from: billInfo.statementDate)
                statementData["dueDate"] = dateFormatter.string(from: billInfo.dueDate)
                statementData["dueAmount"] = String(billInfo.dueAmount)
                statementData["currentUsage"] = String(billInfo.totalAmount)
                statementData["creditLimit"] = String(billInfo.creditLimit ?? 0)
                statementData["pdfFileName"] = pdfFileName
                statementData["transactionCount"] = String(billInfo.transactions.count)
                statementData["emailSubject"] = email.subject ?? ""
                statementData["emailDate"] = email.receivedDateTime
                
                if let statementJsonData = try? JSONSerialization.data(withJSONObject: statementData),
                   let statementJsonString = String(data: statementJsonData, encoding: .utf8) {
                    metadata[statementKey] = statementJsonString
                }
                
                creditCardAccount.metadataDictionary = metadata
                
                print("DEBUG: Automated - Created new account: \(accountName)")
            }
            
            // Save the account first to ensure it's properly persisted in the context
            try viewModel.viewContext.save()
            
            // Refresh the account from the context to ensure it's properly managed
            viewModel.viewContext.refresh(creditCardAccount, mergeChanges: true)
            
            // Process all transactions and always update balance (last bill processed wins)
            var newTransactionsCount = 0
            
            print("DEBUG: Processing bill dated: \(billInfo.statementDate)")
            
            // Add all transactions from this bill
            for transaction in billInfo.transactions {
                let existingTransaction = creditCardAccount.transactionsArray.first(where: { cdTransaction in
                    abs(cdTransaction.amount - transaction.amount) < 0.01 &&
                    Calendar.current.isDate(cdTransaction.wrappedDate, inSameDayAs: transaction.date) &&
                    cdTransaction.wrappedNotes.contains(transaction.description)
                })
                
                if existingTransaction == nil {
                    // Determine if this is a credit transaction (payment to the card)
                    let isPayment = isPaymentTransaction(transaction.description)
                    
                    // Re-fetch the account in viewContext to ensure proper context management
                    let accountInViewContext = viewModel.viewContext.object(with: creditCardAccount.objectID) as! CDAccount
                    
                    // Add transaction using viewModel (which handles context properly)
                    viewModel.addTransaction(
                        amount: transaction.amount,
                        category: TransactionCategory(rawValue: transaction.category),
                        isCredit: isPayment, // Credit transactions reduce the amount owed
                        account: accountInViewContext,
                        notes: transaction.description,
                        date: transaction.date
                    )
                    
                    // Check for automatic bill payment detection
                    if isPayment {
                        checkAndMarkBillAsPaid(
                            account: accountInViewContext,
                            paymentAmount: transaction.amount,
                            paymentDate: transaction.date,
                            paymentDescription: transaction.description
                        )
                    }
                    
                    print("DEBUG: ✅ Added transaction: \(transaction.description) - ₹\(transaction.amount)")
                    newTransactionsCount += 1
                }
            }
            
            // Always update balance to current usage from this bill (last one processed wins)
            let finalAccount = viewModel.viewContext.object(with: creditCardAccount.objectID) as! CDAccount
            finalAccount.balance = billInfo.totalAmount
            print("DEBUG: ✅ Balance updated to: ₹\(billInfo.totalAmount) (from bill dated \(billInfo.statementDate))")
            
            // Save bill metadata for UI display
            saveBillMetadata(account: finalAccount, billInfo: billInfo, pdfFileName: pdfFileName)
            
            
            // Save context
            try viewModel.viewContext.save()
            
            print("DEBUG: Automated - Processed \(billInfo.bankName) ****\(billInfo.cardNumber): \(newTransactionsCount) new transactions")
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
        } catch {
            print("DEBUG: Automated - Error processing PDF \(pdfFileName): \(error)")
        }
    }
    
}

private struct BalanceSummarySection: View {
    let accounts: [CDAccount]
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingBalanceBreakdown = false
    @State private var showingLiabilityBreakdown = false
    
    var bankBalance: Double {
        accounts.filter { $0.accountType == AccountType.bankAccount.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var investmentBalance: Double {
        accounts.filter { $0.accountType == AccountType.mutualFund.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var totalInvestment: Double {
        accounts.filter { $0.accountType == AccountType.mutualFund.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var investmentReturns: Double {
        let returns = investmentBalance - totalInvestment
        return returns
    }
    
    var personalLoansGivenBalance: Double {
        accounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var personalLoansPrincipal: Double {
        accounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var personalLoansInterest: Double {
        personalLoansGivenBalance - personalLoansPrincipal
    }
    
    var totalBalance: Double {
        accounts.filter { $0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }
    }
    
    var totalLiabilities: Double {
        accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }
    }
    
    var creditCardBalance: Double {
        accounts.filter { $0.accountType == AccountType.creditCard.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var loanBalance: Double {
        accounts.filter { $0.accountType == AccountType.loan.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var totalLoanAmount: Double {
        accounts.filter { $0.accountType == AccountType.loan.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var totalCreditLimit: Double {
        accounts.filter { $0.accountType == AccountType.creditCard.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var netWorth: Double { totalBalance - totalLiabilities }
    
    var body: some View {
        Section {
            Button(action: { showingBalanceBreakdown.toggle() }) {
                SummaryRow(title: "Total Balance", amount: totalBalance, color: .green)
            }
            
            if showingBalanceBreakdown {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("Available Balance:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Bank Accounts")
                                .padding(.leading)
                            Spacer()
                            Text(bankBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                    }
                    
                    Group {
                        Text("Investments:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Total Investment")
                                .padding(.leading)
                            Spacer()
                            Text(totalInvestment, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Current Value")
                                .padding(.leading)
                            Spacer()
                            Text(investmentBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Returns")
                                .padding(.leading)
                            Spacer()
                            Text(investmentReturns, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(investmentReturns >= 0 ? .green : .red)
                        }
                        .font(.caption)
                    }
                    
                    Group {
                        Text("Personal Loans Given:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Total Principal")
                                .padding(.leading)
                            Spacer()
                            Text(personalLoansPrincipal, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Interest Earned")
                                .padding(.leading)
                            Spacer()
                            Text(personalLoansInterest, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Total Amount")
                                .padding(.leading)
                            Spacer()
                            Text(personalLoansGivenBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Button(action: { showingLiabilityBreakdown.toggle() }) {
                SummaryRow(title: "Total Liabilities", amount: totalLiabilities, color: .red)
            }
            
            if showingLiabilityBreakdown {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("Credit Cards:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Outstanding Balance")
                                .padding(.leading)
                            Spacer()
                            Text(creditCardBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Total Credit Limit")
                                .padding(.leading)
                            Spacer()
                            Text(totalCreditLimit, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                    
                    Group {
                        Text("Loans:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Total Loan Amount")
                                .padding(.leading)
                            Spacer()
                            Text(totalLoanAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Outstanding Amount")
                                .padding(.leading)
                            Spacer()
                            Text(loanBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Repaid Amount")
                                .padding(.leading)
                            Spacer()
                            Text(totalLoanAmount - loanBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }
            
            SummaryRow(title: "Net Worth", amount: netWorth, color: netWorth >= 0 ? .green : .red)
        }
    }
}

private struct SummaryRow: View {
    @StateObject private var currencySettings = CurrencySettings.shared
    let title: String
    let amount: Double
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                .foregroundColor(color)
        }
    }
}

private struct AddAccountMenu: View {
    @Binding var showingAddAccount: Bool
    @Binding var showingAddMutualFund: Bool
    @Binding var showingAddPersonalLoan: Bool
    @State private var selectedAccountType: AccountType?
    
    var body: some View {
        Menu {
            Menu("Add Account") {
                Button(action: { 
                    selectedAccountType = .bankAccount
                    DispatchQueue.main.async {
                        showingAddAccount = true 
                    }
                }) {
                    Label("Bank Account", systemImage: "banknote")
                }
                
                Button(action: { 
                    selectedAccountType = .creditCard
                    DispatchQueue.main.async {
                        showingAddAccount = true 
                    }
                }) {
                    Label("Credit Card", systemImage: "creditcard")
                }
                
                Button(action: { 
                    selectedAccountType = .loan
                    DispatchQueue.main.async {
                        showingAddAccount = true 
                    }
                }) {
                    Label("Loan", systemImage: "indianrupeesign")
                }
            }
            
            Button(action: { 
                DispatchQueue.main.async {
                    showingAddMutualFund = true 
                }
            }) {
                Label("Add Mutual Fund", systemImage: "chart.line.uptrend.xyaxis")
            }
            
            Button(action: { 
                selectedAccountType = .personalLoanGiven
                DispatchQueue.main.async {
                    showingAddPersonalLoan = true 
                }
            }) {
                Label("Personal Loan Given", systemImage: "person.text.rectangle")
            }
        } label: {
            Image(systemName: "plus")
        }
    }
}

// Simple insurance policy row for AccountsView
private struct InsurancePolicyRowView: View {
    let policy: InsurancePolicy
    let accounts: [CDAccount]
    @StateObject private var currencySettings = CurrencySettings.shared
    
    private var accountName: String {
        accounts.first(where: { $0.id == policy.accountId })?.wrappedAccountName ?? "Unknown Account"
    }
    
    private var nextDueDate: String {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.day, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        var targetMonth = currentMonth
        var targetYear = currentYear
        
        // If we've passed this month's due date, show next month
        if currentDay > policy.dayOfMonth {
            targetMonth += 1
            if targetMonth > 12 {
                targetMonth = 1
                targetYear += 1
            }
        }
        
        let dateComponents = DateComponents(year: targetYear, month: targetMonth, day: policy.dayOfMonth)
        if let nextDate = calendar.date(from: dateComponents) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: nextDate)
        }
        
        return "Day \(policy.dayOfMonth)"
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(policy.name)
                    .font(.headline)
                Text("Next due: \(nextDueDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !policy.isActive {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(policy.premiumAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(.headline)
                    .foregroundColor(.red)
                Text(accountName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 