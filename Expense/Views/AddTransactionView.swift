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
    @State private var ccSourceAccount: CDAccount?
    @State private var ccTargetCard: CDAccount?
    @State private var notes = ""
    @State private var showingError = false
    @State private var showingCategoryManagement = false
    @State private var transactionDate = Date()
    @State private var subcategoryInput: String = ""
    @State private var selectedSuggestedSubcategory: String? = nil
    
    init(viewModel: ExpenseViewModel, transactionType: TransactionType = .expense) {
        self.viewModel = viewModel
        self.transactionType = transactionType
        
        // Set initial account selection
        let accounts = viewModel.accounts.filter { account in
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
        _selectedAccount = State(initialValue: accounts.first)
        if transactionType == .creditCardPayment {
            let sources = viewModel.accounts.filter { $0.accountType == AccountType.bankAccount.rawValue }
            _ccSourceAccount = State(initialValue: sources.first)
            _ccTargetCard = State(initialValue: accounts.first)
        }
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
                        // Subcategory (optional)
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
                    }
                }
                
                if transactionType == .creditCardPayment {
                    Section("Payment From") {
                        Picker("Source Account", selection: $ccSourceAccount) {
                            Text("Select Account").tag(nil as CDAccount?)
                            ForEach(viewModel.accounts.filter { $0.accountType == AccountType.bankAccount.rawValue }) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
                        }
                    }
                    Section("Credit Card") {
                        Picker("Target Card", selection: $ccTargetCard) {
                            Text("Select Card").tag(nil as CDAccount?)
                            ForEach(viewModel.accounts.filter { $0.accountType == AccountType.creditCard.rawValue }) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
                        }
                    }
                } else {
                    Section("Account") {
                        Picker("Account", selection: $selectedAccount) {
                            Text("Select Account").tag(nil as CDAccount?)
                            ForEach(transactionAccounts) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
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
        guard let amountValue = Double(amount) else {
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
            guard let from = ccSourceAccount, let to = ccTargetCard else {
                showingError = true
                return
            }
            viewModel.processCreditCardPayment(
                amount: amountValue,
                fromAccount: from,
                toCreditCardAccount: to,
                notes: notes.isEmpty ? "Credit Card Payment" : notes,
                date: transactionDate
            )
        case .expense:
            let parent = category.displayName
            let manualSub = subcategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let chosenSub = manualSub.isEmpty ? (selectedSuggestedSubcategory ?? "") : manualSub
            let finalCategory: TransactionCategory = chosenSub.isEmpty ? category : .custom("\(parent)::\(chosenSub)")
            if !chosenSub.isEmpty { viewModel.addSubcategory(parent: parent, subcategory: chosenSub) }
            viewModel.addTransaction(
                amount: amountValue,
                category: finalCategory,
                isCredit: false,
                account: account,
                notes: notes.isEmpty ? nil : notes,
                date: transactionDate
            )
        case .income:
            let parent = category.displayName
            let manualSub = subcategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let chosenSub = manualSub.isEmpty ? (selectedSuggestedSubcategory ?? "") : manualSub
            let finalCategory: TransactionCategory = chosenSub.isEmpty ? category : .custom("\(parent)::\(chosenSub)")
            if !chosenSub.isEmpty { viewModel.addSubcategory(parent: parent, subcategory: chosenSub) }
            viewModel.addTransaction(
                amount: amountValue,
                category: finalCategory,
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