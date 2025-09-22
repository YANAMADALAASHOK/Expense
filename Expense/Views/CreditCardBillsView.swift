import SwiftUI
import CoreData

struct CreditCardBillsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var creditCards: [CreditCard] = []
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteAllAlert = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading bills...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if creditCards.isEmpty {
                    ContentUnavailableView(
                        "No Credit Cards",
                        systemImage: "creditcard",
                        description: Text("Use 'Fetch Bills' in Settings to download your credit card statements from email.")
                    )
                } else {
                    List {
                        ForEach(creditCards) { card in
                            NavigationLink(destination: CardDetailView(card: card, viewModel: viewModel)) {
                                CreditCardRow(card: card)
                            }
                        }
                        .onDelete(perform: deleteCards)
                    }
                    .refreshable {
                        loadCreditCards()
                    }
                }
            }
            .navigationTitle("Credit Cards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !creditCards.isEmpty {
                        Button("Delete All") {
                            showingDeleteAllAlert = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                loadCreditCards()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Delete All Bills", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    deleteAllBills()
                }
            } message: {
                Text("Are you sure you want to delete all credit card bills? This will remove all credit card accounts and their transactions.")
            }
        }
    }
    
    private func loadCreditCards() {
        isLoading = true
        
        // Load credit card accounts from Core Data
        let creditCardAccounts = viewModel.accounts.filter { $0.wrappedAccountType == .creditCard }
        
        print("DEBUG: Total accounts: \(viewModel.accounts.count)")
        print("DEBUG: Credit card accounts found: \(creditCardAccounts.count)")
        
        var allCards: [CreditCard] = []
        
        for account in creditCardAccounts {
            print("DEBUG: Account - Name: \(account.wrappedAccountName), Type: \(account.wrappedAccountType), Balance: \(account.balance)")
            
            let metadata = account.metadataDictionary
            
            // Extract bank name and card number from account name
            let accountName = account.wrappedAccountName
            let components = accountName.components(separatedBy: " ****")
            let bankName = components.first ?? "Unknown Bank"
            let cardNumber = components.count > 1 ? components[1] : "Unknown"
            
            // Get credit limit from account or metadata
            let creditLimit = account.creditLimit > 0 ? account.creditLimit : (metadata["creditLimit"].flatMap { Double($0) } ?? 0.0)
            let currentBalance = abs(account.balance)
            let availableCredit = creditLimit - currentBalance
            
            // Count bills from history
            let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
            let totalBills = billHistoryKeys.count > 0 ? billHistoryKeys.count : 1
            
            // Count unpaid bills (only latest bill is unpaid)
            var unpaidBills = 0
            if billHistoryKeys.isEmpty {
                // No bills found
                unpaidBills = 0
            } else {
                // Only the latest bill is unpaid, all others are automatically paid
                unpaidBills = 1 // Always 1 unpaid bill (the latest one)
            }
            
            let card = CreditCard(
                bankName: bankName,
                cardNumber: cardNumber,
                creditLimit: creditLimit,
                currentBalance: currentBalance,
                availableCredit: availableCredit,
                totalBills: totalBills,
                unpaidBills: unpaidBills,
                account: account
            )
            allCards.append(card)
            print("DEBUG: Added card: \(bankName) ****\(cardNumber) - \(totalBills) bills, \(unpaidBills) unpaid")
        }
        
        creditCards = allCards
        
        print("DEBUG: Total credit cards loaded: \(creditCards.count)")
        
        isLoading = false
    }
    
    private func hasPaymentTransactions(account: CDAccount) -> Bool {
        return account.transactionsArray.contains { transaction in
            transaction.wrappedCategory.contains("Payment") && transaction.isCredit
        }
    }
    
    private func hasBillPayment(account: CDAccount, statementDate: Date, dueAmount: Double) -> Bool {
        let metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        // First check if bill is manually marked as paid in metadata
        let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
        
        for key in billHistoryKeys {
            if let statementJsonString = metadata[key],
               let statementJsonData = statementJsonString.data(using: .utf8),
               let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String] {
                
                let billStatementDate = statementData["statementDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
                let billDueAmount = statementData["dueAmount"].flatMap { Double($0) } ?? 0.0
                
                // Check if this matches our bill
                if Calendar.current.isDate(billStatementDate, inSameDayAs: statementDate) &&
                   abs(billDueAmount - dueAmount) < 0.01 {
                    
                    // Check if manually marked as paid
                    if statementData["manuallyPaid"] == "true" {
                        return true
                    }
                }
            }
        }
        
        // Then check if there are payment transactions for this specific bill
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
    
    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            let card = creditCards[index]
            deleteCreditCardAccount(card.account)
        }
        loadCreditCards() // Refresh the list
    }
    
    private func deleteAllBills() {
        let creditCardAccounts = viewModel.accounts.filter { $0.wrappedAccountType == .creditCard }
        
        for account in creditCardAccounts {
            deleteCreditCardAccount(account)
        }
        
        loadCreditCards() // Refresh the list
    }
    
    private func deleteBill(_ bill: CreditCardBill) {
        // Find the corresponding credit card account
        let accountName = "\(bill.bankName) ****\(bill.cardNumber)"
        if let account = viewModel.accounts.first(where: { 
            $0.wrappedAccountName == accountName && $0.wrappedAccountType == .creditCard 
        }) {
            deleteCreditCardAccount(account)
        }
    }
    
    private func deleteCreditCardAccount(_ account: CDAccount) {
        let context = viewModel.viewContext
        
        // Delete all transactions associated with this account
        let transactions = account.transactionsArray
        for transaction in transactions {
            context.delete(transaction)
        }
        
        // Delete the account itself
        context.delete(account)
        
        // Save the context
        do {
            try context.save()
            print("DEBUG: Successfully deleted credit card account: \(account.wrappedAccountName)")
        } catch {
            print("DEBUG: Failed to delete credit card account: \(error)")
            errorMessage = "Failed to delete bill: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct CreditCard: Identifiable {
    let id = UUID()
    let bankName: String
    let cardNumber: String
    let creditLimit: Double
    let currentBalance: Double
    let availableCredit: Double
    let totalBills: Int
    let unpaidBills: Int
    let account: CDAccount
}

struct CreditCardBill: Identifiable {
    let id = UUID()
    let bankName: String
    let cardNumber: String
    let statementDate: Date
    let dueDate: Date
    let totalAmount: Double // Current usage/balance
    let dueAmount: Double // Amount due from statement
    let creditLimit: Double // Credit limit
    let pdfFileName: String?
    let isProcessed: Bool
    let isPaid: Bool // New field to track payment status
}

struct CreditCardRow: View {
    let card: CreditCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.bankName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("****\(card.cardNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("₹\(card.currentBalance, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if card.unpaidBills > 0 {
                        Text("\(card.unpaidBills) unpaid")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    } else {
                        Text("All paid")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available Credit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("₹\(card.availableCredit, specifier: "%.0f")")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Bills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(card.totalBills)")
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CardDetailView: View {
    let card: CreditCard
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var bills: [CreditCardBill] = []
    @State private var isLoading = false
    
    var openBills: [CreditCardBill] {
        bills.filter { !$0.isPaid }
    }
    
    var paidBills: [CreditCardBill] {
        bills.filter { $0.isPaid }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Card Summary
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.bankName)
                                .font(.headline)
                            Text("****\(card.cardNumber)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("₹\(card.currentBalance, specifier: "%.2f")")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Current Balance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Credit Limit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("₹\(card.creditLimit, specifier: "%.2f")")
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Available Credit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("₹\(card.availableCredit, specifier: "%.2f")")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Open Bills Section
                if !openBills.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Open Bills")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            Text("\(openBills.count) bills")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ForEach(openBills) { bill in
                            NavigationLink(destination: BillDetailView(bill: bill, viewModel: viewModel)) {
                                CreditCardBillRow(bill: bill)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Paid Bills Section
                if !paidBills.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Paid Bills")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            Spacer()
                            
                            Text("\(paidBills.count) bills")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ForEach(paidBills) { bill in
                            NavigationLink(destination: BillDetailView(bill: bill, viewModel: viewModel)) {
                                CreditCardBillRow(bill: bill)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                if bills.isEmpty && !isLoading {
                    Text("No bills found for this card")
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle("\(card.bankName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadBillsForCard()
        }
    }
    
    private func loadBillsForCard() {
        isLoading = true
        
        let metadata = card.account.metadataDictionary
        var allBills: [CreditCardBill] = []
        
        print("DEBUG: CardDetail - Account name: \(card.account.wrappedAccountName)")
        print("DEBUG: CardDetail - Account metadata count: \(metadata.count)")
        print("DEBUG: CardDetail - Raw metadata: \(metadata)")
        
        // Load bills from history
        let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
        print("DEBUG: CardDetail - Found \(billHistoryKeys.count) statement keys: \(billHistoryKeys.sorted())")
        
        if billHistoryKeys.isEmpty {
            print("DEBUG: CardDetail - No statement keys found! Checking for legacy metadata...")
            // Check if there are any other keys that might contain bill data
            let allKeys = metadata.keys.sorted()
            print("DEBUG: CardDetail - All available keys: \(allKeys)")
        }
        
        for key in billHistoryKeys {
            print("DEBUG: CardDetail - Processing key: \(key)")
            
            guard let statementJsonString = metadata[key] else {
                print("DEBUG: CardDetail - No JSON string for key: \(key)")
                continue
            }
            
            print("DEBUG: CardDetail - JSON string length: \(statementJsonString.count)")
            print("DEBUG: CardDetail - JSON string preview: \(String(statementJsonString.prefix(200)))")
            
            guard let statementJsonData = statementJsonString.data(using: .utf8) else {
                print("DEBUG: CardDetail - Failed to convert JSON string to data for key: \(key)")
                continue
            }
            
            guard let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String] else {
                print("DEBUG: CardDetail - Failed to parse JSON data for key: \(key)")
                continue
            }
            
            print("DEBUG: CardDetail - Successfully parsed statement data: \(statementData)")
            
            let dateFormatter = ISO8601DateFormatter()
            let statementDate = statementData["statementDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
            let dueDate = statementData["dueDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
            let dueAmount = statementData["dueAmount"].flatMap { Double($0) } ?? 0.0
            let currentUsage = statementData["currentUsage"].flatMap { Double($0) } ?? 0.0
            let statementCreditLimit = statementData["creditLimit"].flatMap { Double($0) } ?? card.creditLimit
            let pdfFileName = statementData["pdfFileName"]
            
            // Check if bill is paid (either manually marked or has payment transaction)
            let isPaid = isSpecificBillPaid(statementData: statementData, account: card.account, statementDate: statementDate, dueAmount: dueAmount)
            
            print("DEBUG: CardDetail - Creating bill: \(statementDate), Amount: ₹\(dueAmount), Paid: \(isPaid)")
            
            let bill = CreditCardBill(
                bankName: card.bankName,
                cardNumber: card.cardNumber,
                statementDate: statementDate,
                dueDate: dueDate,
                totalAmount: currentUsage,
                dueAmount: dueAmount,
                creditLimit: statementCreditLimit,
                pdfFileName: pdfFileName,
                isProcessed: true,
                isPaid: isPaid
            )
            allBills.append(bill)
            print("DEBUG: CardDetail - Successfully created bill for: \(statementDate)")
        }
        
        // Sort bills by statement date (newest first)
        bills = allBills.sorted { $0.statementDate > $1.statementDate }
        
        print("DEBUG: CardDetail - Final result: \(allBills.count) bills loaded")
        for (index, bill) in bills.enumerated() {
            print("DEBUG: CardDetail - Bill \(index + 1): \(bill.statementDate), Amount: ₹\(bill.dueAmount), Paid: \(bill.isPaid)")
        }
        
        isLoading = false
    }
    
    // Function to check if a specific bill is paid (only latest bill is unpaid)
    private func isSpecificBillPaid(statementData: [String: String], account: CDAccount, statementDate: Date, dueAmount: Double) -> Bool {
        // First check if manually marked as paid in metadata
        if statementData["manuallyPaid"] == "true" {
            print("DEBUG: CardDetail - Bill manually marked as PAID - Statement: \(statementDate), Amount: ₹\(dueAmount)")
            return true
        }
        
        // Get all statement dates for this account to find the latest one
        let metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        var allStatementDates: [Date] = []
        let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
        
        for key in billHistoryKeys {
            if let statementJsonString = metadata[key],
               let statementJsonData = statementJsonString.data(using: .utf8),
               let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String],
               let statementDateString = statementData["statementDate"],
               let date = dateFormatter.date(from: statementDateString) {
                allStatementDates.append(date)
            }
        }
        
        // Find the latest statement date
        guard let latestStatementDate = allStatementDates.max() else {
            print("DEBUG: CardDetail - No statement dates found, marking as unpaid")
            return false
        }
        
        // Only the latest bill is unpaid, all others are automatically paid
        let isLatestBill = Calendar.current.isDate(statementDate, inSameDayAs: latestStatementDate)
        let isPaid = !isLatestBill
        
        if isPaid {
            print("DEBUG: CardDetail - Bill auto-marked as PAID (older bill) - Statement: \(statementDate), Amount: ₹\(dueAmount)")
        } else {
            print("DEBUG: CardDetail - Bill marked as UNPAID (latest bill) - Statement: \(statementDate), Amount: ₹\(dueAmount)")
        }
        
        return isPaid
    }
    
    private func hasBillPayment(account: CDAccount, statementDate: Date, dueAmount: Double) -> Bool {
        // Check if there are payment transactions for this specific bill
        // Look for payments after statement date (no end date limit for now)
        
        let paymentTransactions = account.transactionsArray.filter { transaction in
            let notes = transaction.wrappedNotes.uppercased()
            let category = transaction.wrappedCategory.uppercased()
            
            // Check for various payment patterns
            let isPaymentTransaction = transaction.isCredit && (
                notes.contains("BBPS PAYMENT") ||
                notes.contains("PAYMENT RECEIVED") ||
                notes.contains("PAYMENT THANK") ||
                notes.contains("NEFT PAYMENT") ||
                notes.contains("UPI PAYMENT") ||
                notes.contains("IMPS PAYMENT") ||
                notes.contains("RTGS PAYMENT") ||
                notes.contains("MB PAYMENT") ||
                category.contains("PAYMENT")
            )
            
            return isPaymentTransaction && transaction.wrappedDate >= statementDate
        }
        
        print("DEBUG: CardDetail - Checking payment for statement date: \(statementDate), due amount: ₹\(dueAmount)")
        print("DEBUG: CardDetail - Found \(paymentTransactions.count) payment transactions after statement date")
        
        for transaction in paymentTransactions {
            print("DEBUG: CardDetail - Payment transaction - Date: \(transaction.wrappedDate), Amount: ₹\(transaction.amount), Notes: \(transaction.wrappedNotes)")
            
            // Check if amount matches (allow ₹100 variance for payment matching)
            if abs(transaction.amount - dueAmount) < 100.0 {
                print("DEBUG: CardDetail - Found matching payment! Amount difference: ₹\(abs(transaction.amount - dueAmount))")
                return true
            }
        }
        
        print("DEBUG: CardDetail - No matching payment found for due amount ₹\(dueAmount)")
        return false
    }
}

struct CreditCardBillRow: View {
    let bill: CreditCardBill
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Statement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(bill.statementDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("₹\(bill.dueAmount, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundColor(bill.isPaid ? .green : .red)
                    
                    Text(bill.isPaid ? "Paid" : "Due: \(bill.dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let pdfFileName = bill.pdfFileName {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(pdfFileName)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct BillDetailView: View {
    let bill: CreditCardBill
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var transactions: [CDTransaction] = []
    @State private var showingPaymentSheet = false
    @State private var selectedPaymentAccount: CDAccount?
    @State private var paymentAmount: String = ""
    @State private var showingPaymentSuccess = false
    @State private var paymentError: String?
    @State private var currentBillStatus: Bool
    
    init(bill: CreditCardBill, viewModel: ExpenseViewModel) {
        self.bill = bill
        self.viewModel = viewModel
        self._currentBillStatus = State(initialValue: bill.isPaid)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Bill Summary Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bill.bankName)
                                .font(.headline)
                            Text("****\(bill.cardNumber)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Due: ₹\(bill.dueAmount, specifier: "%.2f")")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                
                                Text("Used: ₹\(bill.totalAmount, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(bill.isProcessed ? "Processed" : "Pending")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(bill.isProcessed ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                .foregroundColor(bill.isProcessed ? .green : .orange)
                                .cornerRadius(4)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Statement Date")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(bill.statementDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Due Date")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                        }
                    }
                    
                    if bill.creditLimit > 0 {
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Credit Limit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("₹\(bill.creditLimit, specifier: "%.2f")")
                                    .font(.subheadline)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Available Credit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("₹\(bill.creditLimit - bill.totalAmount, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    if let pdfFileName = bill.pdfFileName {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.blue)
                            Text(pdfFileName)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Divider()
                    
                    // Payment Status (automatic based on latest bill logic)
                    HStack {
                        Image(systemName: currentBillStatus ? "checkmark.circle.fill" : "clock.circle.fill")
                            .font(.title3)
                            .foregroundColor(currentBillStatus ? .green : .orange)
                        Text(currentBillStatus ? "Bill Paid (Older Statement)" : "Current Outstanding Bill")
                            .font(.headline)
                            .foregroundColor(currentBillStatus ? .green : .orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(currentBillStatus ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Payment Options (only for unpaid/current bills)
                    if !currentBillStatus {
                        Button(action: {
                            paymentAmount = String(format: "%.2f", bill.dueAmount)
                            showingPaymentSheet = true
                        }) {
                            HStack {
                                Image(systemName: "creditcard")
                                    .font(.title3)
                                Text("Pay Bill - ₹\(bill.dueAmount, specifier: "%.2f")")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Transactions Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Transactions")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(transactions.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if transactions.isEmpty {
                        Text("No transactions found")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(transactions) { transaction in
                            BillTransactionRowView(transaction: transaction)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Bill Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadTransactions()
        }
        .sheet(isPresented: $showingPaymentSheet) {
            PaymentSheet(
                bill: bill,
                viewModel: viewModel,
                paymentAmount: $paymentAmount,
                selectedAccount: $selectedPaymentAccount,
                onPaymentComplete: { success, error in
                    showingPaymentSheet = false
                    if success {
                        showingPaymentSuccess = true
                        loadTransactions() // Refresh transactions
                    } else {
                        paymentError = error
                    }
                }
            )
        }
        .alert("Payment Successful", isPresented: $showingPaymentSuccess) {
            Button("OK") { }
        } message: {
            Text("Your bill payment of ₹\(paymentAmount) has been processed successfully.")
        }
        .alert("Payment Error", isPresented: .constant(paymentError != nil)) {
            Button("OK") { paymentError = nil }
        } message: {
            Text(paymentError ?? "")
        }
    }
    
    private func loadTransactions() {
        // Find the credit card account that matches this bill
        let accountName = "\(bill.bankName) ****\(bill.cardNumber)"
        
        if let account = viewModel.accounts.first(where: { $0.wrappedAccountName == accountName }) {
            transactions = account.transactionsArray
        }
    }
    
}

struct BillTransactionRowView: View {
    let transaction: CDTransaction
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.wrappedNotes)
                    .font(.subheadline)
                    .lineLimit(2)
                
                Text(transaction.wrappedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("₹\(transaction.amount, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(transaction.wrappedCategory)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PaymentSheet: View {
    let bill: CreditCardBill
    @ObservedObject var viewModel: ExpenseViewModel
    @Binding var paymentAmount: String
    @Binding var selectedAccount: CDAccount?
    let onPaymentComplete: (Bool, String?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    
    var availableAccounts: [CDAccount] {
        viewModel.accounts.filter { account in
            account.wrappedAccountType != .creditCard && account.balance >= (Double(paymentAmount) ?? 0)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Pay Credit Card Bill")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(bill.bankName) ****\(bill.cardNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Payment Amount
                VStack(alignment: .leading, spacing: 8) {
                    Text("Payment Amount")
                        .font(.headline)
                    
                    HStack {
                        Text("₹")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        TextField("0.00", text: $paymentAmount)
                            .font(.title2)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Button("Full Amount") {
                            paymentAmount = String(format: "%.2f", bill.dueAmount)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Minimum") {
                            paymentAmount = String(format: "%.2f", bill.dueAmount * 0.05) // 5% minimum
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                }
                
                // Account Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pay From Account")
                        .font(.headline)
                    
                    if availableAccounts.isEmpty {
                        Text("No accounts with sufficient balance")
                            .foregroundColor(.red)
                            .italic()
                    } else {
                        Picker("Select Account", selection: $selectedAccount) {
                            Text("Select Account").tag(nil as CDAccount?)
                            ForEach(availableAccounts, id: \.id) { account in
                                HStack {
                                    Text(account.wrappedAccountName)
                                    Spacer()
                                    Text("₹\(account.balance, specifier: "%.2f")")
                                        .foregroundColor(.secondary)
                                }
                                .tag(account as CDAccount?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                // Pay Button
                Button(action: processPayment) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "creditcard")
                        }
                        Text(isProcessing ? "Processing..." : "Pay ₹\(paymentAmount)")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canPay ? Color.blue : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(!canPay || isProcessing)
            }
            .padding()
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isProcessing)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }
    
    private var canPay: Bool {
        guard let amount = Double(paymentAmount),
              amount > 0,
              let account = selectedAccount,
              account.balance >= amount else {
            return false
        }
        return true
    }
    
    private func processPayment() {
        guard let amount = Double(paymentAmount),
              let paymentAccount = selectedAccount else {
            onPaymentComplete(false, "Invalid payment details")
            return
        }
        
        isProcessing = true
        
        // Create double-entry transactions
        let success = createPaymentTransactions(
            amount: amount,
            fromAccount: paymentAccount,
            bill: bill
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isProcessing = false
            if success {
                onPaymentComplete(true, nil)
            } else {
                onPaymentComplete(false, "Failed to process payment")
            }
        }
    }
    
    private func createPaymentTransactions(amount: Double, fromAccount: CDAccount, bill: CreditCardBill) -> Bool {
        let context = viewModel.viewContext
        
        do {
            // Find the credit card account
            let creditCardAccountName = "\(bill.bankName) ****\(bill.cardNumber)"
            guard let creditCardAccount = viewModel.accounts.first(where: { 
                $0.wrappedAccountName == creditCardAccountName && $0.wrappedAccountType == .creditCard 
            }) else {
                print("DEBUG: Credit card account not found: \(creditCardAccountName)")
                return false
            }
            
            // Transaction 1: Debit from payment account
            let debitTransaction = CDTransaction(context: context)
            debitTransaction.id = UUID()
            debitTransaction.amount = amount
            debitTransaction.category = "Credit Card Payment"
            debitTransaction.date = Date()
            debitTransaction.isCredit = false // Debit from account
            debitTransaction.notes = "Payment to \(bill.bankName) ****\(bill.cardNumber)"
            debitTransaction.account = fromAccount
            
            // Transaction 2: Credit to credit card account (reduces debt)
            let creditTransaction = CDTransaction(context: context)
            creditTransaction.id = UUID()
            creditTransaction.amount = amount
            creditTransaction.category = "Payment Received"
            creditTransaction.date = Date()
            creditTransaction.isCredit = true // Credit to credit card (reduces balance)
            creditTransaction.notes = "Payment from \(fromAccount.wrappedAccountName)"
            creditTransaction.account = creditCardAccount
            
            // Update account balances
            fromAccount.balance -= amount // Reduce balance in payment account
            creditCardAccount.balance += amount // Reduce debt in credit card (balance becomes less negative)
            
            // Add transactions to accounts
            fromAccount.addToTransactions(debitTransaction)
            creditCardAccount.addToTransactions(creditTransaction)
            
            // Save context
            try context.save()
            
            print("DEBUG: Payment processed successfully")
            print("DEBUG: - Amount: ₹\(amount)")
            print("DEBUG: - From: \(fromAccount.wrappedAccountName) (New balance: ₹\(fromAccount.balance))")
            print("DEBUG: - To: \(creditCardAccount.wrappedAccountName) (New balance: ₹\(creditCardAccount.balance))")
            
            // Refresh accounts in view model
            DispatchQueue.main.async {
                viewModel.fetchAccounts()
            }
            
            return true
            
        } catch {
            print("DEBUG: Failed to process payment: \(error)")
            return false
        }
    }
}

#Preview {
    CreditCardBillsView(viewModel: ExpenseViewModel(context: PersistenceController.preview.container.viewContext))
}