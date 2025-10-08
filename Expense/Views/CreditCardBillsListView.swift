import SwiftUI
import CoreData

// MARK: - Credit Card Bills List View
struct CreditCardBillsListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    let account: CDAccount
    
    @State private var bills: [CreditCardBill] = []
    @State private var isLoading = false
    @State private var isFetchingBills = false
    @State private var showingPaymentSheet = false
    @State private var selectedBill: CreditCardBill?
    @State private var showingBillDetails = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingDeleteConfirmation = false
    
    private var metadata: [String: String] {
        account.metadataDictionary
    }
    
    private var unpaidBills: [CreditCardBill] {
        bills.filter { !$0.isPaid }.sorted { $0.statementDate > $1.statementDate }
    }
    
    private var paidBills: [CreditCardBill] {
        bills.filter { $0.isPaid }.sorted { $0.statementDate > $1.statementDate }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if bills.isEmpty {
                        emptyStateView
                    } else {
                        billsContentView
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .navigationTitle("Credit Card Bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .onAppear {
                loadBills()
            }
            .sheet(isPresented: $showingPaymentSheet) {
                if let bill = selectedBill {
                    PayBillView(bill: bill, account: account, viewModel: viewModel) {
                        loadBills()
                    }
                }
            }
            .sheet(isPresented: $showingBillDetails) {
                if let bill = selectedBill {
                    CreditCardBillDetailsView(bill: bill)
                }
            }
            .alert("Delete All Bills", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    clearAllBills()
                }
            } message: {
                Text("Are you sure you want to delete all bills? This action cannot be undone.")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.5))
            
            Text("No Bills Loaded")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Fetch bills from your email to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            fetchBillsButton
        }
        .padding(.top, 100)
    }
    
    private var fetchBillsButton: some View {
        Button(action: fetchBills) {
            HStack {
                if isFetchingBills {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "arrow.down.doc")
                }
                Text(isFetchingBills ? "Fetching Bills..." : "Fetch Bills from Email")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
        }
        .disabled(isFetchingBills)
        .padding(.horizontal)
    }
    
    private var billsContentView: some View {
        VStack(spacing: 20) {
            actionButtonsView
            unpaidBillsSection
            paidBillsSection
        }
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button(action: { showingDeleteConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Clear All Bills")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red)
                .cornerRadius(10)
            }
            
            Spacer()
            
            Button(action: fetchBills) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.blue)
            }
            .disabled(isFetchingBills)
        }
        .padding(.horizontal)
    }
    
    private var unpaidBillsSection: some View {
        Group {
            if !unpaidBills.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Unpaid Bills")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    ForEach(unpaidBills) { bill in
                        BillRowView(
                            bill: bill,
                            onMarkPaid: { markBillAsPaid(bill) },
                            onPayBill: {
                                selectedBill = bill
                                showingPaymentSheet = true
                            },
                            onViewDetails: {
                                selectedBill = bill
                                showingBillDetails = true
                            }
                        )
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var paidBillsSection: some View {
        if !paidBills.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paid Bills")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top)
                
                ForEach(paidBills) { bill in
                    BillRowView(
                        bill: bill,
                        onMarkPaid: nil,
                        onPayBill: nil,
                        onViewDetails: {
                            selectedBill = bill
                            showingBillDetails = true
                        }
                    )
                    .padding(.horizontal)
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Clear All Bills", systemImage: "trash")
                }
                
                Button(role: .destructive) {
                    resetBalanceAndClearTransactions()
                } label: {
                    Label("Reset Balance & Clear Transactions", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Fetch Bills") {
                fetchBills()
            }
            .disabled(isLoading)
        }
    }
    
    // MARK: - Functions
    
    private func loadBills() {
        // Re-fetch account in the current context to ensure it's valid
        guard let accountObjectID = account.objectID as? NSManagedObjectID else {
            print("ERROR: Cannot get account object ID")
            return
        }
        
        // Get the account in the current view context
        guard let currentAccount = try? viewModel.viewContext.existingObject(with: accountObjectID) as? CDAccount,
              let accountId = currentAccount.id else {
            print("ERROR: Cannot re-fetch account in current context")
            return
        }
        
        // Debug: Check what bills exist and what account we're looking for
        let allBills = CreditCardBillStorage.shared.loadAllBills()
        print("DEBUG: 🔍 Loading bills for account: \(currentAccount.wrappedAccountName) (ID: \(accountId))")
        print("DEBUG: 📊 Total bills in storage: \(allBills.count)")
        
        // Show all bills with their card account IDs
        for bill in allBills {
            print("DEBUG: 📄 Bill: \(bill.statementDate) - Card ID: \(bill.cardAccountId), Amount: ₹\(bill.totalAmount)")
        }
        
        // No migration needed - bills should be created with correct account ID from start
        
        bills = CreditCardBillStorage.shared.loadBills(for: accountId)
        print("DEBUG: ✅ Loaded \(bills.count) bills for this account")
        
        // Debug: Show which bills were loaded
        for bill in bills {
            print("DEBUG: 📄 Loaded bill: \(bill.statementDate) - ₹\(bill.totalAmount)")
        }
    }
    
    private func migrateBillsForHDFCCard(accountId: UUID) {
        let allBills = CreditCardBillStorage.shared.loadAllBills()
        var migratedBills: [CreditCardBill] = []
        var hasChanges = false
        
        for bill in allBills {
            // Check if this bill should belong to the current HDFC account
            // Look for HDFC bills based on PDF filename or transaction patterns
            let isHDFCBill = bill.pdfFileName?.contains("HDFC") == true ||
                           bill.pdfFileName?.contains("Millennia") == true ||
                           bill.transactions.contains { transaction in
                               transaction.description.contains("FLIPKART") ||
                               transaction.description.contains("IGST-VPS") ||
                               transaction.description.contains("TELE TRANSFER") ||
                               transaction.description.contains("MER EMI") ||
                               transaction.description.contains("ZOMATO") ||
                               transaction.description.contains("LATE FEE") ||
                               transaction.description.contains("FINANCE CHARGES")
                           }
            
            // If this is an HDFC bill and isn't already assigned to current account
            if isHDFCBill && bill.cardAccountId != accountId {
                print("DEBUG: 🔄 Migrating bill from \(bill.statementDate) to account \(accountId)")
                
                // Create a new bill with the updated account ID
                let updatedBill = CreditCardBill(
                    id: bill.id,
                    cardAccountId: accountId, // Update to current account
                    statementDate: bill.statementDate,
                    dueDate: bill.dueDate,
                    totalAmount: bill.totalAmount,
                    minimumDue: bill.minimumDue,
                    availableLimit: bill.availableLimit,
                    creditLimit: bill.creditLimit,
                    currentUsage: bill.currentUsage,
                    isPaid: bill.isPaid,
                    balanceAdjusted: bill.balanceAdjusted,
                    pdfFileName: bill.pdfFileName,
                    transactions: bill.transactions
                )
                migratedBills.append(updatedBill)
                hasChanges = true
            } else {
                // Keep the original bill unchanged
                migratedBills.append(bill)
            }
        }
        
        // Save the migrated bills if there were changes
        if hasChanges {
            if let encoded = try? JSONEncoder().encode(migratedBills) {
                UserDefaults.standard.set(encoded, forKey: "CreditCardBills")
                print("DEBUG: ✅ Migrated HDFC bills to current account")
            }
        }
    }
    
    private func fetchBills() {
        // Check if user profile is complete
        guard let currentUser = AuthenticationManager.shared.currentUser,
              currentUser.firstName != nil,
              currentUser.dateOfBirth != nil else {
            errorMessage = "Please complete your profile with First Name and Date of Birth in Settings → Profile"
            showingError = true
            return
        }
        
        isFetchingBills = true
        
        Task {
            let fetchedBills = await CreditCardBillFetcher.shared.fetchBills(
                for: account,
                viewModel: viewModel
            ) { progress in
                print("Progress: \(progress)")
            }
            
            await MainActor.run {
                // Save fetched bills to storage
                if !fetchedBills.isEmpty {
                    for bill in fetchedBills {
                        CreditCardBillStorage.shared.addBill(bill)
                    }
                    print("DEBUG: 💾 Saved \(fetchedBills.count) bills to storage")
                }
                
                // Load all bills for this account (including newly saved ones)
                // Re-fetch account in the current context to ensure it's valid
                if let accountObjectID = account.objectID as? NSManagedObjectID,
                   let currentAccount = try? viewModel.viewContext.existingObject(with: accountObjectID) as? CDAccount,
                   let accountId = currentAccount.id {
                    bills = CreditCardBillStorage.shared.loadBills(for: accountId)
                    print("DEBUG: 📋 Loaded \(bills.count) bills from storage for display")
                } else {
                    print("DEBUG: ⚠️ Using fetched bills directly due to account context issue")
                    bills = fetchedBills
                }
                
                // FIRST: Check if latest bill is already paid (balance already adjusted)
                let latestBillAlreadyPaid = bills.last?.isPaid ?? false
                
                // Update account with latest bill info ONLY if not already paid
                // If paid, balance has been adjusted and should not be overwritten
                if let latestBill = bills.last, !latestBillAlreadyPaid {
                    // Prefer the LATEST bill with credit limit data (not the first one)
                    let bestBill = bills.last { $0.creditLimit > 0 && $0.availableLimit > 0 } ?? latestBill
                    updateAccountWithBill(bestBill)
                    if bestBill.creditLimit > 0 {
                        print("DEBUG: 💳 Updated account with regular statement data - Limit: ₹\(bestBill.creditLimit), Usage: ₹\(bestBill.currentUsage)")
                    } else {
                        print("DEBUG: 💳 Updated balance from latest bill (no credit limit data available)")
                    }
                } else if latestBillAlreadyPaid {
                    print("DEBUG: 💳 Skipped balance update - latest bill already paid, keeping adjusted balance")
                }
                
                // THEN auto-detect and mark paid bills
                // This adjusts balance for newly detected payments
                detectAndMarkPaidBills()
                
                // NOTE: Transactions are auto-synced in CreditCardBillFetcher when bills are added
                // No need to sync again here
                
                isFetchingBills = false
            }
        }
    }
    
    private func updateAccountWithBill(_ bill: CreditCardBill) {
        var metadata = account.metadataDictionary
        metadata["availableLimit"] = String(bill.availableLimit)
        metadata["totalLimit"] = String(bill.creditLimit)
        metadata["currentUsage"] = String(bill.currentUsage)
        metadata["lastStatementDate"] = ISO8601DateFormatter().string(from: bill.statementDate)
        // Record when bills were loaded into the app (today's date)
        metadata["lastBillLoadDate"] = ISO8601DateFormatter().string(from: Date())
        
        account.metadataDictionary = metadata
        
        // Sort bills chronologically (oldest to latest)
        let sortedBills = bills.sorted { $0.statementDate < $1.statementDate }
        print("DEBUG: 📅 Processing \(sortedBills.count) bills chronologically...")
        
        // Mark all bills as paid except the latest one
        if let latestBill = sortedBills.last {
            print("DEBUG: 🆕 Latest bill: \(formatStatementPeriod(latestBill.statementDate)) - ₹\(latestBill.totalAmount)")
            
            // Mark all older bills as paid (they're superseded by the latest bill)
            for oldBill in sortedBills.dropLast() {
                if !oldBill.isPaid {
                    print("DEBUG: ✅ Auto-marking older bill as paid: \(formatStatementPeriod(oldBill.statementDate)) - ₹\(oldBill.totalAmount)")
                    CreditCardBillStorage.shared.markBillAsPaid(oldBill.id)
                }
            }
            
            // Card balance = current usage from latest bill (if available), otherwise bill amount
            let balanceToUse = latestBill.currentUsage > 0 ? latestBill.currentUsage : latestBill.totalAmount
            account.balance = -balanceToUse
            print("DEBUG: ⚡ Updated balance to ₹\(account.balance) from latest bill: \(formatStatementPeriod(latestBill.statementDate))")
        }
        
        // Update the account's credit limit property
        if bill.creditLimit > 0 {
            account.creditLimit = bill.creditLimit
        }
        
        viewModel.saveContext()
        
        // Reload bills to reflect the paid status changes
        loadBills()
    }
    
    private func markBillAsPaid(_ bill: CreditCardBill) {
        CreditCardBillStorage.shared.markBillAsPaid(bill.id)
        loadBills()
    }
    
    private func clearAllBills() {
        // Re-fetch account in the current context to ensure it's valid
        guard let accountObjectID = account.objectID as? NSManagedObjectID,
              let currentAccount = try? viewModel.viewContext.existingObject(with: accountObjectID) as? CDAccount,
              let accountId = currentAccount.id else {
            print("ERROR: Cannot re-fetch account for clearing bills")
            return
        }
        
        CreditCardBillStorage.shared.saveBills([], for: accountId)
        bills = []
        
        // Reset the bill load date tag when bills are cleared
        var metadata = account.metadataDictionary
        metadata.removeValue(forKey: "lastBillLoadDate")
        metadata.removeValue(forKey: "lastStatementDate")
        account.metadataDictionary = metadata
        viewModel.saveContext()
        
        print("DEBUG: 🧹 Cleared all bills for card \(currentAccount.wrappedAccountName) and reset load date tags")
    }
    
    private func resetBalanceAndClearTransactions() {
        // Delete all transactions for this account
        let fetchRequest = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
        fetchRequest.predicate = NSPredicate(format: "account == %@", account)
        
        if let transactions = try? viewModel.viewContext.fetch(fetchRequest) {
            print("DEBUG: 🗑️ Deleting \(transactions.count) transactions for \(account.wrappedAccountName)")
            for transaction in transactions {
                viewModel.viewContext.delete(transaction)
            }
        }
        
        // Reset balance to 0 (will be updated when bills are re-fetched)
        account.balance = 0
        
        // Reset credit limit to 0
        account.creditLimit = 0
        
        // Clear only bill-related metadata while preserving core account info
        var preservedMetadata: [String: String] = [:]
        let currentMetadata = account.metadataDictionary
        
        // Preserve essential account information
        if let accountNumber = currentMetadata["accountNumber"] {
            preservedMetadata["accountNumber"] = accountNumber
        }
        if let bankName = currentMetadata["bankName"] {
            preservedMetadata["bankName"] = bankName
        }
        if let emailAddress = currentMetadata["emailAddress"] {
            preservedMetadata["emailAddress"] = emailAddress
        }
        if let cardType = currentMetadata["cardType"] {
            preservedMetadata["cardType"] = cardType
        }
        
        // Set metadata to only preserved values (removes all bill-related data)
        account.metadataDictionary = preservedMetadata
        
        // Save changes
        try? viewModel.viewContext.save()
        
        print("DEBUG: ✅ Reset complete! Balance, credit limit, and bill metadata cleared.")
        print("DEBUG: 🔒 Preserved: accountNumber, bankName, emailAddress, cardType")
        print("DEBUG: 🗑️ Cleared: All bill-related metadata (statements, due dates, etc.)")
    }
    
    // Format statement period for logging
    private func formatStatementPeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
    
    private func detectAndMarkPaidBills() {
        // Re-fetch account in the current context to ensure it's valid
        guard let accountObjectID = account.objectID as? NSManagedObjectID else {
            print("ERROR: Cannot get account object ID for paid bills detection")
            return
        }
        
        // Get the account in the current view context
        guard let currentAccount = try? viewModel.viewContext.existingObject(with: accountObjectID) as? CDAccount,
              let accountId = currentAccount.id else {
            print("ERROR: Cannot re-fetch account in current context for paid bills detection")
            return
        }
        
        // Only check bills for THIS account, not all accounts
        let accountBills = CreditCardBillStorage.shared.loadBills(for: accountId)
        
        // Filter for unpaid bills for this specific account
        let unpaidBills = accountBills.filter { !$0.isPaid }
        
        print("DEBUG: Total bills for this account: \(accountBills.count), Unpaid bills: \(unpaidBills.count)")
        
        // Get ALL accounts to match bills with their card accounts
        let accountsFetchRequest = NSFetchRequest<CDAccount>(entityName: "CDAccount")
        let allAccounts = (try? viewModel.viewContext.fetch(accountsFetchRequest)) ?? []
        
        // Get ALL transactions from ALL accounts (not just credit card account)
        // Payment transactions are in the SOURCE account (bank), not the credit card
        let fetchRequest = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDTransaction.date, ascending: false)]
        
        let allTransactions = (try? viewModel.viewContext.fetch(fetchRequest)) ?? []
        print("DEBUG: Total transactions across all accounts: \(allTransactions.count)")
        
        // Only check the latest unpaid bill (should be only one after our logic)
        let latestUnpaidBill = unpaidBills.sorted { $0.statementDate > $1.statementDate }.first
        
        if let bill = latestUnpaidBill {
            // Get the card account to extract card number from account name
            let billAccount = allAccounts.first { $0.id == bill.cardAccountId }
            let cardNumber = billAccount?.accountName?.components(separatedBy: "****").last ?? "Unknown"
            
            print("DEBUG: 🔍 Checking bill for \(formatStatementPeriod(bill.statementDate)) - Card: ****\(cardNumber), Amount: ₹\(bill.totalAmount)")
            print("DEBUG: 🔍 Bill period: \(bill.statementDate) to \(bill.dueDate)")
            print("DEBUG: 🔍 Looking for payments in date range and amount within ±₹10 of ₹\(bill.totalAmount)")
            
            // Look for payment transactions from BANK ACCOUNTS (not credit card account)
            // These are payments made FROM bank accounts TO credit cards
            let paymentTransactions = allTransactions.filter { transaction in
                guard let txnDate = transaction.date,
                      let txnCategory = transaction.category,
                      let txnAccount = transaction.account else {
                    return false
                }
                
                let txnAmount = transaction.amount
                let description = transaction.notes?.lowercased() ?? ""
                
                // IMPORTANT: Only look at transactions from BANK accounts, not credit card accounts
                let isFromBankAccount = txnAccount.accountType != "Credit Card"
                
                // Check if transaction is in the date range (statement date to due date + 30 days buffer)
                let extendedDueDate = Calendar.current.date(byAdding: .day, value: 30, to: bill.dueDate) ?? bill.dueDate
                let isInDateRange = txnDate >= bill.statementDate && txnDate <= extendedDueDate
                
                // Check if it's a credit card payment (multiple ways to detect)
                let isPaymentCategory = txnCategory.lowercased() == "credit card payment" ||
                                      txnCategory.lowercased() == "others" ||
                                      description.contains("bppy") ||
                                      description.contains("cc payment") ||
                                      description.contains("credit card") ||
                                      description.contains("payment") ||
                                      description.contains("hdfc") ||
                                      description.contains("axis") ||
                                      description.contains("icici")
                
                // Check if amount matches within ±10 rupees
                let amountDiff = abs(txnAmount - bill.totalAmount)
                let isAmountMatch = amountDiff <= 10
                
                let isMatch = isFromBankAccount && isInDateRange && isPaymentCategory && isAmountMatch
                
                if isInDateRange && isFromBankAccount && (isPaymentCategory || amountDiff <= 10) {
                    print("DEBUG:    📝 Transaction: Date: \(txnDate), Account: \(txnAccount.accountName ?? "N/A") [\(txnAccount.accountType ?? "Unknown")], Category: \(txnCategory), Description: \(description), Amount: ₹\(txnAmount), Bill: ₹\(bill.totalAmount), Diff: ₹\(String(format: "%.2f", amountDiff)), Match: \(isMatch)")
                }
                
                return isMatch
            }
            
            print("DEBUG: Found \(paymentTransactions.count) matching payment transactions")
            
            // If payment found, mark bill as paid AND adjust balance (if not already adjusted)
            if let payment = paymentTransactions.first {
                let billAmount = bill.totalAmount
                let paymentAmount = payment.amount
                let discount = billAmount - paymentAmount
                
                print("DEBUG: ✅ Found payment for bill:")
                print("DEBUG:    Bill Due: ₹\(billAmount)")
                print("DEBUG:    Payment Made: ₹\(paymentAmount)")
                if discount > 0 {
                    print("DEBUG:    💰 Discount/Cashback: ₹\(String(format: "%.2f", discount)) (CRED/App offer - your benefit!)")
                }
                
                // Check if balance was already adjusted
                if bill.balanceAdjusted {
                    print("DEBUG: ⏭️  Balance already adjusted for this bill, skipping")
                    return
                }
                
                // Adjust card balance to reflect the payment
                guard let freshAccount = viewModel.viewContext.object(with: account.objectID) as? CDAccount else {
                    print("DEBUG: ❌ Failed to re-fetch account for balance adjustment")
                    return
                }
                
                let currentBalance = freshAccount.balance
                let newBalance = currentBalance + billAmount // Add because balance is negative
                freshAccount.balance = newBalance
                
                // Update the metadata to reflect reduced usage
                var metadata = freshAccount.metadataDictionary
                let currentUsage = Double(metadata["currentUsage"] ?? "0") ?? 0
                let newUsage = max(0, currentUsage - billAmount) // Ensure it doesn't go negative
                metadata["currentUsage"] = String(newUsage)
                freshAccount.metadataDictionary = metadata
                
                print("DEBUG: 💳 Adjusted card balance after payment:")
                print("DEBUG:    Before Payment: ₹\(String(format: "%.2f", currentBalance))")
                print("DEBUG:    Payment Amount: +₹\(String(format: "%.2f", billAmount))")
                print("DEBUG:    After Payment: ₹\(String(format: "%.2f", newBalance))")
                print("DEBUG:    Current Usage: ₹\(String(format: "%.2f", currentUsage)) → ₹\(String(format: "%.2f", newUsage))")
                if discount > 0 {
                    print("DEBUG:    🎉 You saved ₹\(String(format: "%.2f", discount))")
                }
                
                // Mark bill as paid AND balance adjusted
                CreditCardBillStorage.shared.markBillAsPaid(bill.id, balanceAdjusted: true)
            } else {
                print("DEBUG: ❌ No matching payment found for this bill")
            }
        }
        
        // Save the context once after all bills are checked
        do {
            try viewModel.viewContext.save()
            print("DEBUG: ✅ Saved all balance adjustments to Core Data")
        } catch {
            print("DEBUG: ❌ Failed to save balance updates: \(error)")
        }
        
        // Reload bills to reflect paid status
        loadBills()
        
        // Trigger UI refresh
        viewModel.objectWillChange.send()
        print("DEBUG: ✅ Triggered UI refresh")
        print("DEBUG: 🔍 Finished checking bill payments")
    }
}

// MARK: - Bill Row View
struct BillRowView: View {
    let bill: CreditCardBill
    let onMarkPaid: (() -> Void)?
    let onPayBill: (() -> Void)?
    let onViewDetails: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Statement Date: \(bill.statementDate, style: .date)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Due Date: \(bill.dueDate, style: .date)")
                        .font(.caption)
                        .foregroundColor(bill.isPaid ? .secondary : .red)
                }
                
                Spacer()
                
                if bill.isPaid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                }
            }
            
            // Amounts
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Due")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(bill.totalAmount, format: .currency(code: "INR"))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(bill.isPaid ? .secondary : .red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Minimum Due")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(bill.minimumDue, format: .currency(code: "INR"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Usage Info
            HStack {
                Text("Usage: \(bill.currentUsage, format: .currency(code: "INR"))")
                    .font(.caption)
                Text("•")
                    .foregroundColor(.secondary)
                Text("Available: \(bill.availableLimit, format: .currency(code: "INR"))")
                    .font(.caption)
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(bill.transactions.count) transactions")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            
            // Action Buttons
            if !bill.isPaid {
                HStack(spacing: 12) {
                    if let onMarkPaid = onMarkPaid {
                        Button(action: onMarkPaid) {
                            Text("Mark as Paid")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                    }
                    
                    if let onPayBill = onPayBill {
                        Button(action: onPayBill) {
                            Text("Pay Bill")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            // View Transactions Button
            Button(action: onViewDetails) {
                HStack {
                    Text("View Transactions")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Preview
#Preview {
    CreditCardBillsListView(account: {
        let context = PersistenceController.preview.container.viewContext
        let account = CDAccount(context: context)
        account.id = UUID()
        account.accountName = "Axis Bank ****6988"
        account.accountType = AccountType.creditCard.rawValue
        return account
    }())
    .environmentObject(ExpenseViewModel(context: PersistenceController.preview.container.viewContext))
    .environmentObject(AuthenticationManager.shared)
}
