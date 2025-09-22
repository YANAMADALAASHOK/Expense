import SwiftUI
import CoreData

struct CreditCardBillsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var bills: [CreditCardBill] = []
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
                } else if bills.isEmpty {
                    ContentUnavailableView(
                        "No Credit Card Bills",
                        systemImage: "creditcard",
                        description: Text("Use 'Fetch Bills' in Settings to download your credit card statements from email.")
                    )
                } else {
                    List {
                        ForEach(bills) { bill in
                            NavigationLink(destination: BillDetailView(bill: bill, viewModel: viewModel)) {
                                CreditCardBillRow(bill: bill)
                            }
                        }
                        .onDelete(perform: deleteBills)
                    }
                    .refreshable {
                        loadBills()
                    }
                }
            }
            .navigationTitle("Credit Card Bills")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !bills.isEmpty {
                        Button("Delete All") {
                            showingDeleteAllAlert = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                loadBills()
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
    
    private func loadBills() {
        isLoading = true
        
        // Load credit card accounts from Core Data and extract all bill history
        let creditCardAccounts = viewModel.accounts.filter { $0.wrappedAccountType == .creditCard }
        
        print("DEBUG: Total accounts: \(viewModel.accounts.count)")
        print("DEBUG: Credit card accounts found: \(creditCardAccounts.count)")
        
        var allBills: [CreditCardBill] = []
        
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
            
            // Check for multiple bill history in metadata
            let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
            
            if billHistoryKeys.isEmpty {
                // Fallback to single bill from current metadata
                let dateFormatter = ISO8601DateFormatter()
                let statementDate = metadata["lastStatementDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
                let dueDate = metadata["lastDueDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
                let currentUsage = abs(account.balance)
                let dueAmount = metadata["lastDueAmount"].flatMap { Double($0) } ?? currentUsage
                let isProcessed = !account.transactionsArray.isEmpty
                
                let bill = CreditCardBill(
                    bankName: bankName,
                    cardNumber: cardNumber,
                    statementDate: statementDate,
                    dueDate: dueDate,
                    totalAmount: currentUsage,
                    dueAmount: dueAmount,
                    creditLimit: creditLimit,
                    pdfFileName: metadata["lastPDFFileName"],
                    isProcessed: isProcessed
                )
                allBills.append(bill)
                print("DEBUG: Added single bill for \(bankName) ****\(cardNumber) - \(statementDate)")
            } else {
                // Process multiple bills from history
                print("DEBUG: Found \(billHistoryKeys.count) bill history entries")
                
                for key in billHistoryKeys {
                    if let statementJsonString = metadata[key],
                       let statementJsonData = statementJsonString.data(using: .utf8),
                       let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String] {
                        
                        let dateFormatter = ISO8601DateFormatter()
                        let statementDate = statementData["statementDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
                        let dueDate = statementData["dueDate"].flatMap { dateFormatter.date(from: $0) } ?? Date()
                        let dueAmount = statementData["dueAmount"].flatMap { Double($0) } ?? 0.0
                        let currentUsage = statementData["currentUsage"].flatMap { Double($0) } ?? dueAmount
                        let statementCreditLimit = statementData["creditLimit"].flatMap { Double($0) } ?? creditLimit
                        let pdfFileName = statementData["pdfFileName"]
                        let isProcessed = true // If it's in history, it's processed
                        
                        let bill = CreditCardBill(
                            bankName: bankName,
                            cardNumber: cardNumber,
                            statementDate: statementDate,
                            dueDate: dueDate,
                            totalAmount: currentUsage,
                            dueAmount: dueAmount,
                            creditLimit: statementCreditLimit,
                            pdfFileName: pdfFileName,
                            isProcessed: isProcessed
                        )
                        allBills.append(bill)
                        print("DEBUG: Added bill from history: \(key) - Due: ₹\(dueAmount)")
                    } else {
                        print("DEBUG: Failed to parse bill history: \(key)")
                    }
                }
            }
        }
        
        // Only show actual processed bills - no mock data
        print("DEBUG: Showing only actual processed bills from Core Data accounts")
        
        bills = allBills
        
        // Sort bills by statement date (newest first)
        bills.sort { $0.statementDate > $1.statementDate }
        
        print("DEBUG: Total bills loaded: \(bills.count)")
        
        isLoading = false
    }
    
    private func deleteBills(at offsets: IndexSet) {
        for index in offsets {
            let bill = bills[index]
            deleteBill(bill)
        }
        loadBills() // Refresh the list
    }
    
    private func deleteAllBills() {
        let creditCardAccounts = viewModel.accounts.filter { $0.wrappedAccountType == .creditCard }
        
        for account in creditCardAccounts {
            deleteCreditCardAccount(account)
        }
        
        loadBills() // Refresh the list
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
}

struct CreditCardBillRow: View {
    let bill: CreditCardBill
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.bankName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("****\(bill.cardNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Due: ₹\(bill.dueAmount, specifier: "%.2f")")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text("Used: ₹\(bill.totalAmount, specifier: "%.2f")")
                            .font(.caption)
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
            
            HStack {
                Label("Statement: \(bill.statementDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label("Due: \(bill.dueDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        }
        .padding(.vertical, 4)
    }
}

struct BillDetailView: View {
    let bill: CreditCardBill
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var transactions: [CDTransaction] = []
    
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

#Preview {
    CreditCardBillsView(viewModel: ExpenseViewModel(context: PersistenceController.preview.container.viewContext))
}