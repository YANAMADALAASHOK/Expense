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
    
    init(viewModel: ExpenseViewModel, transaction: CDTransaction) {
        self.viewModel = viewModel
        self.transaction = transaction
        
        _amount = State(initialValue: String(transaction.amount))
        _category = State(initialValue: TransactionCategory(rawValue: transaction.wrappedCategory) ?? .other)
        _isCredit = State(initialValue: transaction.isCredit)
        _notes = State(initialValue: transaction.wrappedNotes)
        _excludeFromDashboard = State(initialValue: viewModel.isTransactionExcluded(transaction))
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
                    
                    Picker("Category", selection: $category) {
                        ForEach(allCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    
                    Toggle("Is Income", isOn: $isCredit)
                }
                
                Section("Notes") {
                    TextField("Notes (Optional)", text: $notes)
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
        
        // Only update rules if category actually changed
        let originalCategory = TransactionCategory(rawValue: transaction.wrappedCategory) ?? .other
        viewModel.updateTransaction(
            transaction,
            amount: amountValue,
            category: category,
            isCredit: isCredit,
            notes: notes.isEmpty ? nil : notes,
            updateRules: category != originalCategory
        )
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