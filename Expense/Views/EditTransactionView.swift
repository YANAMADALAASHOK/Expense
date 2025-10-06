import SwiftUI

struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    let transaction: CDTransaction
    
    @State private var amount: String
    @State private var category: TransactionCategory
    @State private var isCredit: Bool
    @State private var notes: String
    @State private var showingError = false
    @State private var excludeFromDashboard = false
    @State private var subcategoryInput: String = ""
    @State private var selectedSuggestedSubcategory: String? = nil
    @State private var ccPaidCard: CDAccount? = nil
    @State private var ccFundingAccount: CDAccount? = nil
    @State private var transactionDate: Date
    
    init(viewModel: ExpenseViewModel, transaction: CDTransaction) {
        self.viewModel = viewModel
        self.transaction = transaction
        
        _amount = State(initialValue: String(transaction.amount))
        let raw = transaction.wrappedCategory
        if let range = raw.range(of: "::"), !raw.hasPrefix("::"), !raw.hasSuffix("::") {
            let parent = String(raw[..<range.lowerBound])
            _category = State(initialValue: TransactionCategory(rawValue: parent))
            _subcategoryInput = State(initialValue: String(raw[range.upperBound...]))
        } else {
            _category = State(initialValue: TransactionCategory(rawValue: raw))
        }
        _isCredit = State(initialValue: transaction.isCredit)
        _notes = State(initialValue: transaction.wrappedNotes)
        _excludeFromDashboard = State(initialValue: viewModel.isTransactionExcluded(transaction))
        _transactionDate = State(initialValue: transaction.wrappedDate)
        if TransactionCategory(rawValue: transaction.wrappedCategory) == .creditCardPayment {
            // Preselect based on notes if possible (best-effort)
            let all = viewModel.accounts
            if let note = transaction.notes {
                if let matchCard = all.first(where: { note.contains($0.wrappedAccountName) && $0.accountType == AccountType.creditCard.rawValue }) {
                    _ccPaidCard = State(initialValue: matchCard)
                }
                if let matchFunding = all.first(where: { note.contains($0.wrappedAccountName) && $0.accountType != AccountType.creditCard.rawValue }) {
                    _ccFundingAccount = State(initialValue: matchFunding)
                }
            }
        }
    }
    
    var allCategories: [TransactionCategory] {
        var categories = TransactionCategory.allCases
        let customTransactionCategories = viewModel.customCategories.map { customCategory in
            TransactionCategory.custom(customCategory)
        }
        categories.append(contentsOf: customTransactionCategories)
        return categories
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Transaction Details") {
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencySettings.selectedCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    DatePicker("Date & Time", selection: $transactionDate, displayedComponents: [.date, .hourAndMinute])
                    
                    Picker("Category", selection: $category) {
                        ForEach(allCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    let suggestions = viewModel.subcategories(for: category.displayName)
                    if !suggestions.isEmpty {
                        Picker("Subcategory", selection: Binding<String?>(
                            get: { selectedSuggestedSubcategory },
                            set: { selectedSuggestedSubcategory = $0 }
                        )) {
                            Text("None").tag(nil as String?)
                            ForEach(suggestions, id: \.self) { sub in
                                Text(sub).tag(sub as String?)
                            }
                        }
                    }
                    TextField("Subcategory (Optional)", text: $subcategoryInput)
                    
                    Toggle("Is Income", isOn: $isCredit)
                }
                
                Section("Notes") {
                    TextField("Notes (Optional)", text: $notes)
                }

                if TransactionCategory(rawValue: transaction.wrappedCategory) == .creditCardPayment {
                    Section("Credit Card Payment Details") {
                        Picker("Paid Card", selection: $ccPaidCard) {
                            Text("Select Card").tag(nil as CDAccount?)
                            ForEach(viewModel.accounts.filter { $0.accountType == AccountType.creditCard.rawValue }) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
                        }
                        Picker("Paid From", selection: $ccFundingAccount) {
                            Text("Select Funding Account").tag(nil as CDAccount?)
                            ForEach(viewModel.accounts.filter { $0.accountType != AccountType.creditCard.rawValue }) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
                        }
                        Text("On save, the app will convert this into a linked debit from the funding account and a credit to the card, and update both balances.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Dashboard") {
                    Toggle("Exclude from Dashboard", isOn: $excludeFromDashboard)
                }
                
                if let account = transaction.account {
                    Section("Account") {
                        Text(account.wrappedAccountName)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTransaction() }
                }
            }
            .alert("Invalid Amount", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enter a valid amount")
            }
        }
    }
    
    private func saveTransaction() {
        guard let amountValue = Double(amount) else {
            showingError = true
            return
        }
        
        let parent = category.displayName
        let manualSub = subcategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenSub = manualSub.isEmpty ? (selectedSuggestedSubcategory ?? "") : manualSub
        let finalCategory: TransactionCategory = chosenSub.isEmpty ? category : .custom("\(parent)::\(chosenSub)")
        if !chosenSub.isEmpty { viewModel.addSubcategory(parent: parent, subcategory: chosenSub) }

        if finalCategory == .creditCardPayment, let card = ccPaidCard, let funding = ccFundingAccount {
            viewModel.convertToCreditCardPayment(
                transaction: transaction,
                amount: amountValue,
                paidCard: card,
                fundingAccount: funding,
                notes: notes,
                date: transactionDate
            )
        } else {
            viewModel.updateTransaction(
                transaction,
                amount: amountValue,
                category: finalCategory,
                isCredit: isCredit,
                notes: notes.isEmpty ? nil : notes,
                date: transactionDate,
                updateRules: false
            )
        }
        viewModel.setExcluded(for: transaction, excluded: excludeFromDashboard)
        
        dismiss()
    }
}

#if DEBUG
struct EditTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        EditTransactionView(
            viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext),
            transaction: PreviewHelper.shared.sampleTransaction()
        )
    }
}
#endif 