import SwiftUI

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    let account: CDAccount
    
    @State private var accountName: String
    @State private var balance: String
    @State private var creditLimit: String
    @State private var showingError = false
    
    init(viewModel: ExpenseViewModel, account: CDAccount) {
        self.viewModel = viewModel
        self.account = account
        
        _accountName = State(initialValue: account.accountName ?? "")
        _balance = State(initialValue: String(account.balance))
        _creditLimit = State(initialValue: String(account.creditLimit))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $accountName)
                    
                    if account.accountType == AccountType.mutualFund.rawValue {
                        HStack {
                            TextField("Current Value", text: $balance)
                                .keyboardType(.decimalPad)
                            Picker("Currency", selection: $currencySettings.selectedCurrency) {
                                ForEach(Currency.allCases, id: \.self) { currency in
                                    Text(currency.symbol).tag(currency)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        let investedAmount = account.creditLimit
                        let currentValue = Double(balance) ?? 0
                        let profit = currentValue - investedAmount
                        let returns = investedAmount > 0 ? (profit / investedAmount) * 100 : 0
                        
                        Text("Initial Investment: \(investedAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))")
                            .foregroundColor(.secondary)
                        
                        Text("Profit/Loss: \(profit, format: .currency(code: currencySettings.selectedCurrency.rawValue))")
                            .foregroundColor(profit >= 0 ? .green : .red)
                        
                        Text("Returns: \(returns, format: .percent)")
                            .foregroundColor(returns >= 0 ? .green : .red)
                    } else {
                        HStack {
                            TextField("Current Balance", text: $balance)
                                .keyboardType(.decimalPad)
                            Picker("Currency", selection: $currencySettings.selectedCurrency) {
                                ForEach(Currency.allCases, id: \.self) { currency in
                                    Text(currency.symbol).tag(currency)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        if account.accountType == AccountType.creditCard.rawValue {
                            HStack {
                                TextField("Credit Limit", text: $creditLimit)
                                    .keyboardType(.decimalPad)
                                Picker("Currency", selection: $currencySettings.selectedCurrency) {
                                    ForEach(Currency.allCases, id: \.self) { currency in
                                        Text(currency.symbol).tag(currency)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAccount() }
                }
            }
            .alert("Invalid Input", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please check your input values")
            }
        }
    }
    
    private func saveAccount() {
        guard let balanceValue = Double(balance),
              accountName.isEmpty == false else {
            showingError = true
            return
        }
        
        let creditLimitValue = Double(creditLimit) ?? 0.0
        
        viewModel.updateAccount(
            account,
            name: accountName,
            balance: balanceValue,
            creditLimit: !account.wrappedAccountType.isAsset ? creditLimitValue : account.creditLimit
        )
        
        dismiss()
    }
}

#if DEBUG
struct EditAccountView_Previews: PreviewProvider {
    static var previews: some View {
        EditAccountView(
            viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext),
            account: PreviewHelper.shared.sampleAccount()
        )
    }
}
#endif 