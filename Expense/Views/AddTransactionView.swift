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
    @State private var transferFromAccount: CDAccount?
    @State private var transferToAccount: CDAccount?
    @State private var selectedCreditCardAccount: CDAccount?
    @State private var selectedFundingAccount: CDAccount?
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
            let cc = viewModel.accounts.first { $0.accountType == AccountType.creditCard.rawValue }
            let funding = viewModel.accounts.first { acct in
                acct.accountType == AccountType.bankAccount.rawValue ||
                acct.accountType == AccountType.savings.rawValue ||
                acct.accountType == AccountType.cash.rawValue
            }
            _selectedCreditCardAccount = State(initialValue: cc)
            _selectedFundingAccount = State(initialValue: funding)
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

    private var creditCardAccounts: [CDAccount] {
        viewModel.accounts.filter { $0.accountType == AccountType.creditCard.rawValue }
    }

    private var fundingAccounts: [CDAccount] {
        viewModel.accounts.filter { acct in
            acct.accountType == AccountType.bankAccount.rawValue ||
            acct.accountType == AccountType.savings.rawValue ||
            acct.accountType == AccountType.cash.rawValue
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
                
                if category == .selfTransfer {
                    Section("Transfer Accounts") {
                        Picker("From", selection: $transferFromAccount) {
                            Text("Select Source").tag(nil as CDAccount?)
                            ForEach(viewModel.accounts) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
                        }
                        Picker("To", selection: $transferToAccount) {
                            Text("Select Destination").tag(nil as CDAccount?)
                            ForEach(viewModel.accounts) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
                        }
                    }
                } else if transactionType == .creditCardPayment {
                    Section("Payment Accounts") {
                        Picker("Paid Card", selection: $selectedCreditCardAccount) {
                            Text("Select Card").tag(nil as CDAccount?)
                            ForEach(creditCardAccounts) { account in
                                Text(account.wrappedAccountName).tag(account as CDAccount?)
                            }
                        }
                        Picker("Paid From", selection: $selectedFundingAccount) {
                            Text("Select Funding Account").tag(nil as CDAccount?)
                            ForEach(fundingAccounts) { account in
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
        if category == .selfTransfer { return "Self Transfer" }

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
            guard let loanAccount = selectedAccount else { showingError = true; return }
            viewModel.addTransaction(
                amount: amountValue,
                category: .emiPayment,
                isCredit: true,  // Credit for loan account means reducing the balance
                account: loanAccount,
                notes: notes.isEmpty ? "EMI Payment" : notes,
                date: transactionDate
            )
        case .creditCardPayment:
            guard let toCard = selectedCreditCardAccount, let from = selectedFundingAccount else {
                showingError = true
                return
            }
            viewModel.processCreditCardPayment(
                amount: amountValue,
                fromAccount: from,
                toCreditCardAccount: toCard,
                notes: notes.isEmpty ? "Credit Card Payment" : notes,
                date: transactionDate
            )
        case .expense:
            guard let expenseAccount = selectedAccount else { showingError = true; return }
            let parent = category.displayName
            let manualSub = subcategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let chosenSub = manualSub.isEmpty ? (selectedSuggestedSubcategory ?? "") : manualSub
            let finalCategory: TransactionCategory = chosenSub.isEmpty ? category : .custom("\(parent)::\(chosenSub)")
            if !chosenSub.isEmpty { viewModel.addSubcategory(parent: parent, subcategory: chosenSub) }
            viewModel.addTransaction(
                amount: amountValue,
                category: finalCategory,
                isCredit: false,
                account: expenseAccount,
                notes: notes.isEmpty ? nil : notes,
                date: transactionDate
            )
        case .income:
            guard let incomeAccount = selectedAccount else { showingError = true; return }
            let parent = category.displayName
            let manualSub = subcategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let chosenSub = manualSub.isEmpty ? (selectedSuggestedSubcategory ?? "") : manualSub
            let finalCategory: TransactionCategory = chosenSub.isEmpty ? category : .custom("\(parent)::\(chosenSub)")
            if !chosenSub.isEmpty { viewModel.addSubcategory(parent: parent, subcategory: chosenSub) }
            viewModel.addTransaction(
                amount: amountValue,
                category: finalCategory,
                isCredit: true,
                account: incomeAccount,
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