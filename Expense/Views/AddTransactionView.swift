import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    
    @State private var amount = ""
    @State private var category = TransactionCategory.other
    @State private var isCredit = false
    @State private var selectedAccount: CDAccount?
    @State private var notes = ""
    @State private var showingError = false
    @State private var showingCategoryManagement = false
    @State private var transactionDate = Date()
    
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
                    
                    DatePicker("Date", selection: $transactionDate, in: ...Date(), displayedComponents: [.date])
                    
                    Picker("Category", selection: $category) {
                        ForEach(allCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    
                    Toggle("Is Income", isOn: $isCredit)
                }
                
                Section("Account") {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as CDAccount?)
                        ForEach(viewModel.accounts, id: \.id) { account in
                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (Optional)", text: $notes)
                }
            }
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTransaction() }
                }
            }
            .alert("Invalid Input", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enter a valid amount and select an account")
            }
        }
    }
    
    private func saveTransaction() {
        guard let amountValue = Double(amount),
              let account = selectedAccount else {
            showingError = true
            return
        }
        
        viewModel.addTransaction(
            amount: amountValue,
            category: category,
            isCredit: isCredit,
            account: account,
            notes: notes.isEmpty ? nil : notes,
            date: transactionDate
        )
        
        dismiss()
    }
}

#if DEBUG
struct AddTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        AddTransactionView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 