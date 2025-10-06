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
                    // Load Bills Button
                    if bills.isEmpty {
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
                        .padding(.top, 100)
                    } else {
                        // Action Buttons
                        HStack(spacing: 12) {
                            // Clear All Bills Button
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
                            
                            // Refresh Button
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
                        
                        // Unpaid Bills Section
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
                        
                        // Paid Bills Section
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
                    
                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .navigationTitle("Credit Card Bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    Button("Done") {
                        dismiss()
                    }
                }
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
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .alert("Clear All Bills?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    clearAllBills()
                }
            } message: {
                Text("This will delete all \(bills.count) bill(s) for this card. You can fetch them again from email.")
            }
        }
    }
    
    private func loadBills() {
        guard let accountId = account.id else {
            print("ERROR: Account ID is nil, cannot load bills")
            return
        }
        bills = CreditCardBillStorage.shared.loadBills(for: accountId)
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
                bills = fetchedBills
                
                // FIRST: Check if latest bill is already paid (balance already adjusted)
                let latestBillAlreadyPaid = bills.last?.isPaid ?? false
                
                // Update account with latest bill info ONLY if not already paid
                // If paid, balance has been adjusted and should not be overwritten
                if let latestBill = bills.last, !latestBillAlreadyPaid {
                    updateAccountWithBill(latestBill)
                    print("DEBUG: 💳 Updated balance from PDF (bill not yet paid)")
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
        
        account.metadataDictionary = metadata
        
        // ALWAYS update balance from PDF current usage
        // Balance should reflect: Credit Limit - Available Limit from latest statement
        // This is the actual current usage regardless of payment status
        account.balance = -bill.currentUsage
        print("DEBUG: ⚡ Updated balance to ₹\(account.balance) from PDF (Credit Limit - Available Limit)")
        
        account.creditLimit = bill.creditLimit
        
        viewModel.saveContext()
    }
    
    private func markBillAsPaid(_ bill: CreditCardBill) {
        CreditCardBillStorage.shared.markBillAsPaid(bill.id)
        loadBills()
    }
    
    private func clearAllBills() {
        // Delete all bills for this card
        CreditCardBillStorage.shared.saveBills([], for: account.id!)
        bills = []
        print("DEBUG: Cleared all bills for card \(account.wrappedAccountName)")
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
        // Load all bills (this will trigger migration on first load)
        let allBills = CreditCardBillStorage.shared.loadAllBills()
        
        // Filter for unpaid bills (after migration has updated balanceAdjusted flags)
        let unpaidBills = allBills.filter { !$0.isPaid }
        
        print("DEBUG: Total bills: \(allBills.count), Unpaid bills: \(unpaidBills.count)")
        
        // Get ALL accounts to match bills with their card accounts
        let accountsFetchRequest = NSFetchRequest<CDAccount>(entityName: "CDAccount")
        let allAccounts = (try? viewModel.viewContext.fetch(accountsFetchRequest)) ?? []
        
        // Get ALL transactions from ALL accounts (not just credit card account)
        // Payment transactions are in the SOURCE account (bank), not the credit card
        let fetchRequest = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDTransaction.date, ascending: false)]
        
        let allTransactions = (try? viewModel.viewContext.fetch(fetchRequest)) ?? []
        print("DEBUG: Total transactions across all accounts: \(allTransactions.count)")
        
        // Check each unpaid bill
        for bill in unpaidBills {
            // Get the card account to extract card number from account name
            let billAccount = allAccounts.first { $0.id == bill.cardAccountId }
            let cardNumber = billAccount?.accountName?.components(separatedBy: "****").last ?? "Unknown"
            
            print("DEBUG: 🔍 Checking bill for \(formatStatementPeriod(bill.statementDate)) - Card: ****\(cardNumber), Amount: ₹\(bill.totalAmount), Period: \(bill.statementDate) to \(bill.dueDate)")
            
            // Look for payment transactions from the due date BACKWARDS to statement date
            // (payments usually happen AFTER the bill is generated, near or on the due date)
            let paymentTransactions = allTransactions.filter { transaction in
                guard let txnDate = transaction.date,
                      let txnCategory = transaction.category else {
                    return false
                }
                
                let txnAmount = transaction.amount
                let txnAccount = transaction.account
                
                // Check if transaction is in the date range (statement date to due date)
                let isInDateRange = txnDate >= bill.statementDate && txnDate <= bill.dueDate
                
                // Check if it's a credit card payment category
                let isPaymentCategory = txnCategory.lowercased() == "credit card payment"
                
                // Check if amount matches within ±10 rupees
                let amountDiff = abs(txnAmount - bill.totalAmount)
                let isAmountMatch = amountDiff <= 10
                
                if isInDateRange && txnCategory.lowercased().contains("credit card") {
                    print("DEBUG:    📝 Transaction: Date: \(txnDate), Account: \(txnAccount?.accountName ?? "N/A"), Category: \(txnCategory), Amount: ₹\(txnAmount), Bill: ₹\(bill.totalAmount), Diff: ₹\(String(format: "%.2f", amountDiff)), Match: \(isPaymentCategory && isAmountMatch)")
                }
                
                return isInDateRange && isPaymentCategory && isAmountMatch
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
                    continue
                }
                
                // Adjust card balance to reflect the payment
                guard let freshAccount = try? viewModel.viewContext.object(with: account.objectID) as? CDAccount else {
                    print("DEBUG: ❌ Failed to re-fetch account for balance adjustment")
                    continue
                }
                
                let currentBalance = freshAccount.balance
                // Credit card balances are negative (amount owed)
                // Payment reduces the debt, so add the payment amount (makes balance less negative)
                let newBalance = currentBalance + billAmount
                freshAccount.balance = newBalance
                
                print("DEBUG: 💳 Adjusted card balance after payment:")
                print("DEBUG:    Before Payment: ₹\(String(format: "%.2f", currentBalance))")
                print("DEBUG:    Payment Amount: +₹\(String(format: "%.2f", billAmount))")
                print("DEBUG:    After Payment: ₹\(String(format: "%.2f", newBalance))")
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
