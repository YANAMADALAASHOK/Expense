import SwiftUI
import CoreData
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    
    @State private var accountName = ""
    @State private var accountType: AccountType
    @State private var balance = ""
    @State private var creditLimit = ""
    @State private var interestRate = ""
    @State private var showingError = false
    
    init(viewModel: ExpenseViewModel, initialAccountType: AccountType = .bankAccount) {
        self.viewModel = viewModel
        _accountType = State(initialValue: initialAccountType)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $accountName)
                    
                    Picker("Account Type", selection: $accountType) {
                        ForEach(AccountType.allCases.filter { $0 != .mutualFund }, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    
                    if accountType == .mutualFund {
                        HStack {
                            TextField("Initial Investment", text: $creditLimit)
                                .keyboardType(.decimalPad)
                            Picker("Currency", selection: $currencySettings.selectedCurrency) {
                                ForEach(Currency.allCases, id: \.self) { currency in
                                    Text(currency.symbol).tag(currency)
                                }
                            }
                            .labelsHidden()
                        }
                        
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
                    } else if !accountType.isAsset {
                        HStack {
                            TextField("Outstanding Balance", text: $balance)
                                .keyboardType(.decimalPad)
                            Picker("Currency", selection: $currencySettings.selectedCurrency) {
                                ForEach(Currency.allCases, id: \.self) { currency in
                                    Text(currency.symbol).tag(currency)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        HStack {
                            TextField(accountType == .creditCard ? "Credit Limit" : "Original Amount", text: $creditLimit)
                                .keyboardType(.decimalPad)
                            Picker("Currency", selection: $currencySettings.selectedCurrency) {
                                ForEach(Currency.allCases, id: \.self) { currency in
                                    Text(currency.symbol).tag(currency)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        if accountType == .loan {
                            HStack {
                                TextField("Interest Rate (%)", text: $interestRate)
                                    .keyboardType(.decimalPad)
                                Text("% per year")
                            }
                        }
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
                    }
                }
            }
            .navigationTitle("Add Account")
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
        var metadata: [String: String]?
        
        if accountType == .loan {
            guard let rate = Double(interestRate) else {
                showingError = true
                return
            }
            metadata = [
                "interestRate": interestRate,
                "lastInterestDate": Date().ISO8601Format()
            ]
        }
        
        viewModel.addAccount(
            name: accountName,
            type: accountType,
            balance: balanceValue,
            creditLimit: !accountType.isAsset || accountType == .mutualFund ? creditLimitValue : nil,
            metadata: metadata
        )
        
        dismiss()
    }
} 