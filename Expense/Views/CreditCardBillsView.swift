import SwiftUI
import CoreData

struct CreditCardBillsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var creditCards: [CreditCard] = []
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteAllAlert = false
    @State private var selectedBillForPayment: CreditCardBill?
    @State private var showingPaymentSheet = false
    
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
            let totalBills = billHistoryKeys.count
            
            print("DEBUG: Account \(accountName) - Found \(billHistoryKeys.count) statement keys: \(billHistoryKeys.sorted())")
            
            // Count unpaid bills (only latest bill is unpaid)
            var unpaidBills = 0
            if billHistoryKeys.isEmpty {
                // No bills found
                unpaidBills = 0
            } else {
                // Find the latest statement date to determine which bill is unpaid
                let dateFormatter = ISO8601DateFormatter()
                var latestStatementDate: Date?
                
                for key in billHistoryKeys {
                    if let statementJsonString = metadata[key],
                       let statementJsonData = statementJsonString.data(using: .utf8),
                       let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String],
                       let statementDateString = statementData["statementDate"],
                       let statementDate = dateFormatter.date(from: statementDateString) {
                        
                        if latestStatementDate == nil || statementDate > latestStatementDate! {
                            latestStatementDate = statementDate
                        }
                    }
                }
                
                // Only the latest bill is unpaid
                unpaidBills = latestStatementDate != nil ? 1 : 0
            }
            
            // Only add card if it has bills
            if totalBills > 0 {
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
            } else {
                print("DEBUG: Skipping card \(bankName) ****\(cardNumber) - no bills found")
            }
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
    
    // Enhanced card details
    var fullCardNumber: String {
        // Try to get full card number from account metadata, fallback to masked
        if let metadata = account.metadata,
           let metadataString = String(data: metadata, encoding: .utf8),
           let fullNumber = extractFullCardNumber(from: metadataString) {
            return fullNumber
        }
        return "****\(cardNumber)"
    }
    
    var expiryDate: String {
        // Try to get expiry from account metadata
        if let metadata = account.metadata,
           let metadataString = String(data: metadata, encoding: .utf8),
           let expiry = extractExpiryDate(from: metadataString) {
            return expiry
        }
        return "MM/YY"
    }
    
    var cvv: String {
        // Try to get CVV from account metadata
        if let metadata = account.metadata,
           let metadataString = String(data: metadata, encoding: .utf8),
           let cvvValue = extractCVV(from: metadataString) {
            return cvvValue
        }
        return "***"
    }
    
    private func extractFullCardNumber(from metadata: String) -> String? {
        // Look for full card number in metadata
        let patterns = [
            "fullCardNumber\":\\s*\"([0-9\\s]+)\"",
            "cardNumber\":\\s*\"([0-9\\s]+)\"",
            "fullNumber\":\\s*\"([0-9\\s]+)\""
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)),
               let range = Range(match.range(at: 1), in: metadata) {
                return String(metadata[range]).replacingOccurrences(of: " ", with: "")
            }
        }
        return nil
    }
    
    private func extractExpiryDate(from metadata: String) -> String? {
        // Look for expiry date in metadata
        let patterns = [
            "expiryDate\":\\s*\"([0-9]{2}/[0-9]{2})\"",
            "expiry\":\\s*\"([0-9]{2}/[0-9]{2})\"",
            "validThru\":\\s*\"([0-9]{2}/[0-9]{2})\""
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)),
               let range = Range(match.range(at: 1), in: metadata) {
                return String(metadata[range])
            }
        }
        return nil
    }
    
    private func extractCVV(from metadata: String) -> String? {
        // Look for CVV in metadata
        let patterns = [
            "cvv\":\\s*\"([0-9]{3,4})\"",
            "cvc\":\\s*\"([0-9]{3,4})\"",
            "securityCode\":\\s*\"([0-9]{3,4})\""
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)),
               let range = Range(match.range(at: 1), in: metadata) {
                return String(metadata[range])
            }
        }
        return nil
    }
    
    // Helper function to add card details to account metadata
    static func addCardDetails(to account: CDAccount, fullNumber: String, expiry: String, cvv: String) {
        var metadata = account.metadataDictionary
        metadata["fullCardNumber"] = fullNumber
        metadata["expiryDate"] = expiry
        metadata["cvv"] = cvv
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata) {
            account.metadata = jsonData
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
    let isPaid: Bool // New field to track payment status
}

struct CreditCardRow: View {
    let card: CreditCard
    @State private var showingCardDetails = false
    @State private var showingShareSheet = false
    
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
                    Text("₹\(String(format: "%.0f", card.currentBalance))")
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
                    Text("₹\(String(format: "%.0f", card.availableCredit))")
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
            
            // Card action buttons
            HStack {
                Button(action: {
                    showingCardDetails = true
                }) {
                    HStack {
                        Image(systemName: "creditcard")
                        Text("Card Details")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    showingShareSheet = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(8)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingCardDetails) {
            CreditCardDetailsView(card: card)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [createShareText()])
        }
    }
    
    private func createShareText() -> String {
        return """
        💳 \(card.bankName) Credit Card
        
        Card Number: \(card.fullCardNumber)
        Expiry Date: \(card.expiryDate)
        CVV: \(card.cvv)
        
        💰 Financial Details:
        Credit Limit: ₹\(String(format: "%.0f", card.creditLimit))
        Current Balance: ₹\(String(format: "%.0f", card.currentBalance))
        Available Credit: ₹\(String(format: "%.0f", card.availableCredit))
        
        📊 Bills Status:
        Total Bills: \(card.totalBills)
        Unpaid Bills: \(card.unpaidBills)
        
        Generated from Expense Tracker App
        """
    }
}

// MARK: - Credit Card Details View
struct CreditCardDetailsView: View {
    let card: CreditCard
    @Environment(\.dismiss) var dismiss
    @State private var showingShareSheet = false
    @State private var isCardNumberVisible = false
    @State private var isCVVVisible = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Card Visual
                    CreditCardVisualView(
                        card: card,
                        showFullNumber: isCardNumberVisible,
                        showCVV: isCVVVisible
                    )
                    
                    // Card Details Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Card Information")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        CardDetailRow(
                            title: "Bank Name",
                            value: card.bankName,
                            icon: "building.2"
                        )
                        
                        CardDetailRow(
                            title: "Card Number",
                            value: isCardNumberVisible ? card.fullCardNumber : "****\(card.cardNumber)",
                            icon: "creditcard",
                            isSecure: true,
                            isVisible: isCardNumberVisible,
                            onToggleVisibility: { isCardNumberVisible.toggle() }
                        )
                        
                        CardDetailRow(
                            title: "Expiry Date",
                            value: card.expiryDate,
                            icon: "calendar"
                        )
                        
                        CardDetailRow(
                            title: "CVV",
                            value: isCVVVisible ? card.cvv : "***",
                            icon: "lock.shield",
                            isSecure: true,
                            isVisible: isCVVVisible,
                            onToggleVisibility: { isCVVVisible.toggle() }
                        )
                    }
                    .padding(.horizontal)
                    
                    // Financial Details Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Financial Information")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        CardDetailRow(
                            title: "Credit Limit",
                            value: "₹\(String(format: "%.0f", card.creditLimit))",
                            icon: "chart.line.uptrend.xyaxis"
                        )
                        
                        CardDetailRow(
                            title: "Current Balance",
                            value: "₹\(String(format: "%.0f", card.currentBalance))",
                            icon: "indianrupeesign.circle"
                        )
                        
                        CardDetailRow(
                            title: "Available Credit",
                            value: "₹\(String(format: "%.0f", card.availableCredit))",
                            icon: "checkmark.circle.fill",
                            valueColor: .green
                        )
                    }
                    .padding(.horizontal)
                    
                    // Bills Status Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Bills Status")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        CardDetailRow(
                            title: "Total Bills",
                            value: "\(card.totalBills)",
                            icon: "doc.text"
                        )
                        
                        CardDetailRow(
                            title: "Unpaid Bills",
                            value: "\(card.unpaidBills)",
                            icon: "exclamationmark.triangle",
                            valueColor: card.unpaidBills > 0 ? .red : .green
                        )
                    }
                    .padding(.horizontal)
                    
                    // Share Button
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Card Details")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [createDetailedShareText()])
        }
    }
    
    private func createDetailedShareText() -> String {
        return """
        💳 \(card.bankName) Credit Card Details
        
        🔢 Card Information:
        Card Number: \(card.fullCardNumber)
        Expiry Date: \(card.expiryDate)
        CVV: \(card.cvv)
        
        💰 Financial Summary:
        Credit Limit: ₹\(String(format: "%.0f", card.creditLimit))
        Current Balance: ₹\(String(format: "%.0f", card.currentBalance))
        Available Credit: ₹\(String(format: "%.0f", card.availableCredit))
        
        📊 Bills Overview:
        Total Bills: \(card.totalBills)
        Unpaid Bills: \(card.unpaidBills)
        Status: \(card.unpaidBills > 0 ? "⚠️ Has pending bills" : "✅ All bills paid")
        
        📱 Shared from Expense Tracker App
        Date: \(Date().formatted(date: .abbreviated, time: .shortened))
        """
    }
}

// MARK: - Supporting Views
struct CreditCardVisualView: View {
    let card: CreditCard
    let showFullNumber: Bool
    let showCVV: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(height: 200)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(card.bankName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text("CREDIT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Text(showFullNumber ? formatCardNumber(card.fullCardNumber) : "****  ****  ****  \(card.cardNumber)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .tracking(2)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("VALID THRU")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Text(card.expiryDate)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("CVV")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Text(showCVV ? card.cvv : "***")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(20)
        }
        .padding(.horizontal)
    }
    
    private func formatCardNumber(_ number: String) -> String {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        var formatted = ""
        for (index, character) in cleaned.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += "  "
            }
            formatted += String(character)
        }
        return formatted
    }
}

struct CardDetailRow: View {
    let title: String
    let value: String
    let icon: String
    var isSecure: Bool = false
    var isVisible: Bool = false
    var valueColor: Color = .primary
    var onToggleVisibility: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(valueColor)
            }
            
            Spacer()
            
            if isSecure, let toggle = onToggleVisibility {
                Button(action: toggle) {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// ShareSheet is already defined in ExportManager.swift

struct CardDetailView: View {
    let card: CreditCard
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var bills: [CreditCardBill] = []
    @State private var isLoading = false
    @State private var showPaidBills = false
    @State private var selectedBillForPayment: CreditCardBill?
    @State private var showingPaymentSheet = false
    @State private var selectedBillForDetail: CreditCardBill?
    @State private var paymentAmount = ""
    @State private var selectedPaymentAccount: CDAccount?
    
    var openBills: [CreditCardBill] {
        bills.filter { !$0.isPaid }.sorted { $0.statementDate > $1.statementDate }
    }
    
    var paidBills: [CreditCardBill] {
        bills.filter { $0.isPaid }.sorted { $0.statementDate > $1.statementDate }
    }
    
    var body: some View {
        List {
            Section {
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
                            Text("₹\(String(format: "%.2f", card.currentBalance))")
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
                            Text("₹\(String(format: "%.2f", card.creditLimit))")
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Available Credit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("₹\(String(format: "%.2f", card.availableCredit))")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                    }
                }
                .listRowBackground(Color(.systemGray6))
                .listRowSeparator(.hidden)
            }
            
            
            // Current Bills Section
            if !openBills.isEmpty {
                Section(header: 
                    HStack {
                        Text("Current Bills")
                            .font(.headline)
                            .foregroundColor(.red)
                        Spacer()
                        Text("Not Paid")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                ) {
                    ForEach(openBills) { bill in
                        CreditCardBillRow(bill: bill)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedBillForDetail = bill
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    print("DEBUG: Mark Paid button tapped for bill: \(bill.dueAmount)")
                                    markBillAsManuallyPaid(bill: bill)
                                } label: {
                                    Label("Mark Paid", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                                
                                Button {
                                    print("DEBUG: Pay button tapped for bill: \(bill.dueAmount)")
                                    selectedBillForPayment = bill
                                } label: {
                                    Label("Pay", systemImage: "creditcard.fill")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
                
            // Paid Bills Section
            if !paidBills.isEmpty {
                Section(header: 
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showPaidBills.toggle()
                        }
                    }) {
                        HStack {
                            Text("Paid Bills (\(paidBills.count))")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            Spacer()
                            
                            Image(systemName: showPaidBills ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                ) {
                    if showPaidBills {
                        ForEach(paidBills) { bill in
                            CreditCardBillRow(bill: bill)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedBillForDetail = bill
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        print("DEBUG: Mark Unpaid button tapped for bill: \(bill.dueAmount)")
                                        markBillAsUnpaid(bill: bill)
                                    } label: {
                                        Label("Mark Unpaid", systemImage: "xmark.circle.fill")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                }
            }
                
            // Empty state
            if bills.isEmpty && !isLoading {
                Section {
                    Text("No bills found for this card")
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle("\(card.bankName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadBillsForCard()
        }
        .sheet(item: $selectedBillForDetail) { bill in
            NavigationView {
                BillDetailView(bill: bill, viewModel: viewModel)
            }
        }
        .sheet(item: $selectedBillForPayment) { bill in
            PaymentSheet(
                bill: bill,
                viewModel: viewModel,
                paymentAmount: $paymentAmount,
                selectedAccount: $selectedPaymentAccount,
                onPaymentComplete: { success, message in
                    if success {
                        loadBillsForCard() // Refresh bills after payment
                    }
                    selectedBillForPayment = nil
                }
            )
        }
    }
    
    private func loadBillsForCard() {
        isLoading = true
        
        let metadata = card.account.metadataDictionary
        var allBills: [CreditCardBill] = []
        
        print("DEBUG: CardDetail - Account name: \(card.account.wrappedAccountName)")
        print("DEBUG: CardDetail - Account metadata count: \(metadata.count)")
        print("DEBUG: CardDetail - Raw metadata keys: \(metadata.keys.sorted())")
        
        // Load bills from history
        let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
        print("DEBUG: CardDetail - Found \(billHistoryKeys.count) statement keys: \(billHistoryKeys.sorted())")
        
        if billHistoryKeys.isEmpty {
            print("DEBUG: CardDetail - ❌ No statement keys found! This means no bills were saved to metadata.")
            print("DEBUG: CardDetail - Account balance: \(card.account.balance)")
            print("DEBUG: CardDetail - Account credit limit: \(card.account.creditLimit)")
            print("DEBUG: CardDetail - All available metadata keys: \(metadata.keys.sorted())")
            
            // Check if this account has transactions
            let transactionCount = card.account.transactionsArray.count
            print("DEBUG: CardDetail - Account has \(transactionCount) transactions")
            
            if transactionCount > 0 {
                print("DEBUG: CardDetail - Sample transactions:")
                for (index, transaction) in card.account.transactionsArray.prefix(3).enumerated() {
                    print("DEBUG: CardDetail - Transaction \(index + 1): \(transaction.wrappedNotes) - ₹\(transaction.amount) on \(transaction.wrappedDate)")
                }
            }
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
            
            // For ICICI cards, try to get the correct total amount due
            let actualDueAmount: Double
            if card.bankName.uppercased().contains("ICICI") {
                print("DEBUG: CardDetail - ICICI card detected, available fields: \(statementData.keys.sorted())")
                
                // For ICICI, try various field names for the correct due amount
                actualDueAmount = statementData["totalAmountDue"].flatMap { Double($0) } ?? 
                                 statementData["totalDue"].flatMap { Double($0) } ?? 
                                 statementData["amountDue"].flatMap { Double($0) } ??
                                 statementData["paymentDue"].flatMap { Double($0) } ??
                                 statementData["minimumDue"].flatMap { Double($0) } ??
                                 dueAmount // Use original dueAmount as fallback, not currentUsage
                
                print("DEBUG: CardDetail - ICICI field values:")
                print("DEBUG: - dueAmount: ₹\(dueAmount)")
                print("DEBUG: - currentUsage: ₹\(currentUsage)")
                print("DEBUG: - totalAmountDue: \(statementData["totalAmountDue"] ?? "nil")")
                print("DEBUG: - totalDue: \(statementData["totalDue"] ?? "nil")")
                print("DEBUG: - amountDue: \(statementData["amountDue"] ?? "nil")")
                print("DEBUG: - Final actualDueAmount: ₹\(actualDueAmount)")
            } else {
                actualDueAmount = dueAmount
            }
            
            // Check if bill is paid (either manually marked or has payment transaction)
            let isPaid = isSpecificBillPaid(statementData: statementData, account: card.account, statementDate: statementDate, dueAmount: actualDueAmount)
            
            print("DEBUG: CardDetail - Creating bill: \(statementDate), Amount: ₹\(actualDueAmount), Paid: \(isPaid)")
            
            let bill = CreditCardBill(
                bankName: card.bankName,
                cardNumber: card.cardNumber,
                statementDate: statementDate,
                dueDate: dueDate,
                totalAmount: currentUsage,
                dueAmount: actualDueAmount,
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
        
        // Filter out duplicate bills (same statement date and amount)
        bills = bills.reduce(into: [CreditCardBill]()) { result, bill in
            let isDuplicate = result.contains { existingBill in
                Calendar.current.isDate(existingBill.statementDate, inSameDayAs: bill.statementDate) &&
                abs(existingBill.dueAmount - bill.dueAmount) < 0.01
            }
            if !isDuplicate {
                result.append(bill)
            }
        }
        
        print("DEBUG: CardDetail - After deduplication: \(bills.count) unique bills")
        
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
    
    private func markBillAsManuallyPaid(bill: CreditCardBill) {
        print("DEBUG: 🔄 Starting markBillAsManuallyPaid for bill: ₹\(bill.dueAmount)")
        
        // Find the credit card account for this bill
        let account = card.account
        var metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        let statementKey = "statement_\(dateFormatter.string(from: bill.statementDate))"
        
        print("DEBUG: - Account: \(account.wrappedAccountName)")
        print("DEBUG: - Statement Key: \(statementKey)")
        print("DEBUG: - Metadata keys: \(metadata.keys.sorted())")
        
        // Check if this account has this bill
        if let existingJsonString = metadata[statementKey] {
            print("DEBUG: - Found metadata for statement key")
            print("DEBUG: - JSON string: \(existingJsonString)")
            
            if let existingJsonData = existingJsonString.data(using: .utf8),
               var existingBillData = try? JSONSerialization.jsonObject(with: existingJsonData) as? [String: String] {
                print("DEBUG: - Successfully parsed JSON data: \(existingBillData)")
                
                if let dueAmount = existingBillData["dueAmount"] {
                    let metadataAmount = Double(dueAmount) ?? 0
                    let billAmount = bill.dueAmount
                    let difference = abs(metadataAmount - billAmount)
                    
                    print("DEBUG: - Metadata amount: ₹\(metadataAmount)")
                    print("DEBUG: - Bill amount: ₹\(billAmount)")
                    print("DEBUG: - Difference: ₹\(difference)")
                    
                    if difference < 0.01 {
                        print("DEBUG: - ✅ Amounts match, proceeding to mark as paid")
                        
                        // Mark as manually paid
                        existingBillData["manuallyPaid"] = "true"
                        existingBillData["paidDate"] = dateFormatter.string(from: Date())
                        
                        print("DEBUG: - Updated bill data: \(existingBillData)")
                        
                        // Convert back to JSON string
                        if let updatedJsonData = try? JSONSerialization.data(withJSONObject: existingBillData),
                           let updatedJsonString = String(data: updatedJsonData, encoding: .utf8) {
                            metadata[statementKey] = updatedJsonString
                            account.metadataDictionary = metadata
                            
                            print("DEBUG: 💳 Marked bill as PAID in metadata")
                            print("DEBUG: - Statement Date: \(bill.statementDate)")
                            print("DEBUG: - Amount: ₹\(bill.dueAmount)")
                            print("DEBUG: - Paid Date: \(Date())")
                            
                            // Save the context
                            do {
                                try viewModel.viewContext.save()
                                print("DEBUG: ✅ Successfully marked bill as manually paid and saved to Core Data")
                                
                                // Refresh the bills list
                                loadBillsForCard()
                            } catch {
                                print("DEBUG: ❌ Failed to save after marking bill as paid: \(error)")
                            }
                        } else {
                            print("DEBUG: ❌ Failed to convert updated data back to JSON")
                        }
                    } else {
                        print("DEBUG: ❌ Amount mismatch - difference too large: ₹\(difference)")
                    }
                } else {
                    print("DEBUG: ❌ No dueAmount found in metadata")
                }
            } else {
                print("DEBUG: ❌ Failed to parse JSON data")
            }
        } else {
            print("DEBUG: ❌ No metadata found for statement key: \(statementKey)")
            print("DEBUG: - Available keys: \(metadata.keys.sorted())")
        }
    }
    
    private func markBillAsUnpaid(bill: CreditCardBill) {
        // Find the credit card account for this bill
        let account = card.account
        var metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        let statementKey = "statement_\(dateFormatter.string(from: bill.statementDate))"
        
        // Check if this account has this bill
        if let existingJsonString = metadata[statementKey],
           let existingJsonData = existingJsonString.data(using: .utf8),
           var existingBillData = try? JSONSerialization.jsonObject(with: existingJsonData) as? [String: String],
           let dueAmount = existingBillData["dueAmount"],
           abs(Double(dueAmount) ?? 0 - bill.dueAmount) < 0.01 {
            
            // Remove the manually paid flag
            existingBillData.removeValue(forKey: "manuallyPaid")
            existingBillData.removeValue(forKey: "paidDate")
            
            // Convert back to JSON string
            if let updatedJsonData = try? JSONSerialization.data(withJSONObject: existingBillData),
               let updatedJsonString = String(data: updatedJsonData, encoding: .utf8) {
                metadata[statementKey] = updatedJsonString
                account.metadataDictionary = metadata
                
                print("DEBUG: 🔄 Marked bill as UNPAID in metadata")
                print("DEBUG: - Statement Date: \(bill.statementDate)")
                print("DEBUG: - Amount: ₹\(bill.dueAmount)")
                
                // Save the context
                do {
                    try viewModel.viewContext.save()
                    print("DEBUG: ✅ Successfully marked bill as unpaid and saved to Core Data")
                    
                    // Refresh the bills list
                    loadBillsForCard()
                } catch {
                    print("DEBUG: ❌ Failed to save after marking bill as unpaid: \(error)")
                }
            }
        }
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
                    Text("₹\(String(format: "%.2f", bill.dueAmount))")
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
                                Text("Due: ₹\(String(format: "%.2f", bill.dueAmount))")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                
                                Text("Used: ₹\(String(format: "%.2f", bill.totalAmount))")
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
                                Text("₹\(String(format: "%.2f", bill.creditLimit))")
                                    .font(.subheadline)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Available Credit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("₹\(String(format: "%.2f", bill.creditLimit - bill.totalAmount))")
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
                                Text("Pay Bill - ₹\(String(format: "%.2f", bill.dueAmount))")
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
                        currentBillStatus = true // Update bill status to paid
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
        
        guard let account = viewModel.accounts.first(where: { $0.wrappedAccountName == accountName }) else {
            print("DEBUG: BillDetailView - Account not found: \(accountName)")
            return
        }
        
        // Get the statement period dates
        let metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        // Find all statement dates to determine the period for this bill
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
        
        // Sort statement dates
        allStatementDates.sort()
        
        // Find the previous statement date (start of this billing period)
        let currentStatementDate = bill.statementDate
        let previousStatementDate: Date
        
        if let currentIndex = allStatementDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: currentStatementDate) }),
           currentIndex > 0 {
            previousStatementDate = allStatementDates[currentIndex - 1]
        } else {
            // If this is the first statement, use a date far in the past
            previousStatementDate = Calendar.current.date(byAdding: .year, value: -10, to: currentStatementDate) ?? currentStatementDate
        }
        
        print("DEBUG: BillDetailView - Filtering transactions")
        print("DEBUG: - Statement Date: \(currentStatementDate)")
        print("DEBUG: - Previous Statement Date: \(previousStatementDate)")
        print("DEBUG: - Total transactions in account: \(account.transactionsArray.count)")
        
        // Filter transactions for this billing period only
        // Include transactions AFTER previous statement date and UP TO current statement date
        let filteredTransactions = account.transactionsArray.filter { transaction in
            let transactionDate = transaction.wrappedDate
            let isInPeriod = transactionDate > previousStatementDate && transactionDate <= currentStatementDate
            
            // Also exclude payment transactions (credits to credit card)
            let isPayment = transaction.isCredit && (
                transaction.wrappedNotes.uppercased().contains("PAYMENT") ||
                transaction.wrappedCategory.uppercased().contains("PAYMENT")
            )
            
            return isInPeriod && !isPayment
        }
        
        // Sort by date (newest first)
        transactions = filteredTransactions.sorted { $0.wrappedDate > $1.wrappedDate }
        
        print("DEBUG: - Filtered transactions: \(transactions.count)")
        print("DEBUG: - Date range: \(previousStatementDate.formatted(date: .abbreviated, time: .omitted)) to \(currentStatementDate.formatted(date: .abbreviated, time: .omitted))")
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
                Text("₹\(String(format: "%.2f", transaction.amount))")
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
                                    Text("₹\(String(format: "%.2f", account.balance))")
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
            creditCardAccount.balance -= amount // Reduce debt in credit card (balance becomes less negative/more positive)
            
            // Add transactions to accounts
            fromAccount.addToTransactions(debitTransaction)
            creditCardAccount.addToTransactions(creditTransaction)
            
            // Mark bill as paid in metadata
            markBillAsPaid(creditCardAccount: creditCardAccount, bill: bill)
            
            // Save context
            try context.save()
            
            print("DEBUG: Payment processed successfully")
            print("DEBUG: - Amount: ₹\(amount)")
            print("DEBUG: - From: \(fromAccount.wrappedAccountName) (New balance: ₹\(fromAccount.balance))")
            print("DEBUG: - To: \(creditCardAccount.wrappedAccountName) (New balance: ₹\(creditCardAccount.balance))")
            print("DEBUG: - Bill marked as PAID")
            
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
    
    private func markBillAsPaid(creditCardAccount: CDAccount, bill: CreditCardBill) {
        var metadata = creditCardAccount.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        // Find the statement key for this bill
        let statementKey = "statement_\(dateFormatter.string(from: bill.statementDate))"
        
        if let existingJsonString = metadata[statementKey],
           let existingJsonData = existingJsonString.data(using: .utf8),
           var existingBillData = try? JSONSerialization.jsonObject(with: existingJsonData) as? [String: String] {
            
            // Mark as manually paid
            existingBillData["manuallyPaid"] = "true"
            existingBillData["paidDate"] = dateFormatter.string(from: Date())
            
            // Convert back to JSON string
            if let updatedJsonData = try? JSONSerialization.data(withJSONObject: existingBillData),
               let updatedJsonString = String(data: updatedJsonData, encoding: .utf8) {
                metadata[statementKey] = updatedJsonString
                creditCardAccount.metadataDictionary = metadata
                
                print("DEBUG: 💳 Marked bill as PAID in metadata")
                print("DEBUG: - Statement Date: \(bill.statementDate)")
                print("DEBUG: - Amount: ₹\(bill.dueAmount)")
                print("DEBUG: - Paid Date: \(Date())")
            }
        }
    }
    
}

#Preview {
    CreditCardBillsView(viewModel: ExpenseViewModel(context: PersistenceController.preview.container.viewContext))
}