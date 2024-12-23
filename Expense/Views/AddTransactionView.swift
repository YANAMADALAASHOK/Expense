import SwiftUI

enum TransactionType {
    case expense
    case income
    case loanPayment
    case creditCardPayment
}

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    let transactionType: TransactionType
    
    @State private var amount = ""
    @State private var category = TransactionCategory.other
    @State private var selectedAccount: CDAccount?
    @State private var notes = ""
    @State private var showingError = false
    @State private var showingCategoryManagement = false
    @State private var transactionDate = Date()
    
    init(viewModel: ExpenseViewModel, transactionType: TransactionType = .expense) {
        self.viewModel = viewModel
        self.transactionType = transactionType
    }
    
    private var transactionAccounts: [CDAccount] {
        viewModel.accounts.filter { account in
            switch transactionType {
            case .loanPayment:
                return account.accountType == AccountType.loan.rawValue
            case .creditCardPayment:
                return account.accountType == AccountType.creditCard.rawValue
            case .expense, .income:
                return account.accountType == AccountType.bankAccount.rawValue ||
                       account.accountType == AccountType.creditCard.rawValue
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
                    
                    DatePicker("Date", selection: $transactionDate, in: ...Date(), displayedComponents: [.date])
                    
                    if transactionType != .loanPayment {
                        Picker("Category", selection: $category) {
                            ForEach(allCategories, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                    }
                }
                
                Section("Account") {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as CDAccount?)
                        ForEach(transactionAccounts, id: \.id) { account in
                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (Optional)", text: $notes)
                }
            }
            .navigationTitle(navigationTitle)
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
    
    private var navigationTitle: String {
        switch transactionType {
        case .expense:
            return "Add Expense"
        case .income:
            return "Add Income"
        case .loanPayment:
            return "Add Loan Payment"
        case .creditCardPayment:
            return "Credit Card Payment"
        }
    }
    
    private func saveTransaction() {
        guard let amountValue = Double(amount),
              let account = selectedAccount else {
            showingError = true
            return
        }
        
        switch transactionType {
        case .loanPayment:
            // For loan payments, always set as credit (reducing the loan balance)
            viewModel.addTransaction(
                amount: amountValue,
                category: .emiPayment,
                isCredit: true,  // Credit for loan account means reducing the balance
                account: account,
                notes: notes.isEmpty ? "EMI Payment" : notes,
                date: transactionDate
            )
        case .creditCardPayment:
            // For credit card payments, set as credit (reducing the card balance)
            viewModel.addTransaction(
                amount: amountValue,
                category: .creditCardPayment,
                isCredit: true,  // Credit for credit card means reducing the balance
                account: account,
                notes: notes.isEmpty ? "Credit Card Payment" : notes,
                date: transactionDate
            )
        case .expense:
            viewModel.addTransaction(
                amount: amountValue,
                category: category,
                isCredit: false,
                account: account,
                notes: notes.isEmpty ? nil : notes,
                date: transactionDate
            )
        case .income:
            viewModel.addTransaction(
                amount: amountValue,
                category: category,
                isCredit: true,
                account: account,
                notes: notes.isEmpty ? nil : notes,
                date: transactionDate
            )
        }
        
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