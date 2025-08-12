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
    @State private var interestRate: String = ""
    @State private var lastInterestDate: Date = Date()
    @State private var loanDate: Date = Date()
    @State private var amfiSchemeCode: String = ""
    @State private var fundSearchText: String = ""
    @State private var showFundSuggestions: Bool = false
    @State private var isFundListLoading: Bool = false
    
    init(viewModel: ExpenseViewModel, account: CDAccount) {
        self.viewModel = viewModel
        self.account = account
        
        _accountName = State(initialValue: account.accountName ?? "")
        _balance = State(initialValue: String(account.balance))
        _creditLimit = State(initialValue: String(account.creditLimit))
        let metadata = account.metadataDictionary
        _interestRate = State(initialValue: metadata["interestRate"] ?? "")
        if let dateString = metadata["lastInterestCalculationDate"], let date = ISO8601DateFormatter().date(from: dateString) {
            _lastInterestDate = State(initialValue: date)
        } else {
            _lastInterestDate = State(initialValue: Date())
        }
        
        if let dateString = metadata["loanDate"], let date = ISO8601DateFormatter().date(from: dateString) {
            _loanDate = State(initialValue: date)
        } else {
            _loanDate = State(initialValue: Date())
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Account Details") {
                    TextField("Account Name", text: $accountName)
                    
                    if account.accountType == AccountType.mutualFund.rawValue {
                        VStack(alignment: .leading) {
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
                            VStack(alignment: .leading) {
                                TextField("Search Mutual Fund Name or Code", text: $fundSearchText, onEditingChanged: { editing in
                                    showFundSuggestions = editing
                                    if editing && viewModel.amfiFundList.isEmpty && !isFundListLoading {
                                        isFundListLoading = true
                                        viewModel.fetchAMFIFundList {
                                            isFundListLoading = false
                                        }
                                    }
                                })
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onChange(of: fundSearchText) { _ in showFundSuggestions = true }
                                .onSubmit { showFundSuggestions = false }
                                .textInputAutocapitalization(.never)
                                .keyboardType(.default)
                                .onAppear {
                                    if viewModel.amfiFundList.isEmpty && !isFundListLoading {
                                        isFundListLoading = true
                                        viewModel.fetchAMFIFundList {
                                            isFundListLoading = false
                                        }
                                    }
                                }
                                if isFundListLoading {
                                    ProgressView("Loading fund list...")
                                        .padding(.vertical, 8)
                                } else if showFundSuggestions && !fundSearchText.isEmpty {
                                    let suggestions = viewModel.amfiFundList.filter {
                                        $0.name.localizedCaseInsensitiveContains(fundSearchText.trimmingCharacters(in: .whitespacesAndNewlines)) ||
                                        $0.code.contains(fundSearchText.trimmingCharacters(in: .whitespacesAndNewlines))
                                    }.prefix(10)
                                    if !suggestions.isEmpty {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 0) {
                                                ForEach(Array(suggestions), id: \.code) { fund in
                                                    Button(action: {
                                                        accountName = fund.name
                                                        amfiSchemeCode = fund.code
                                                        fundSearchText = fund.name
                                                        showFundSuggestions = false
                                                    }) {
                                                        VStack(alignment: .leading) {
                                                            Text(fund.name).font(.body)
                                                            Text("Code: \(fund.code)").font(.caption).foregroundColor(.secondary)
                                                        }
                                                        .padding(.vertical, 6)
                                                        .padding(.horizontal, 8)
                                                    }
                                                    .background(Color(.systemBackground))
                                                }
                                            }
                                        }
                                        .frame(maxHeight: 200)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .shadow(radius: 2)
                                    } else {
                                        Text("No matching funds found.")
                                            .foregroundColor(.secondary)
                                            .padding(.vertical, 8)
                                    }
                                }
                            }
                            let investedAmount = Double(creditLimit) ?? 0
                            let currentValue = Double(balance) ?? 0
                            let profit = currentValue - investedAmount
                            let returns = investedAmount > 0 ? (profit / investedAmount) * 100 : 0
                            Text("Initial Investment: \(investedAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))")
                                .foregroundColor(.secondary)
                            Text("Profit/Loss: \(profit, format: .currency(code: currencySettings.selectedCurrency.rawValue))")
                                .foregroundColor(profit >= 0 ? .green : .red)
                            Text("Returns: \(returns, format: .percent)")
                                .foregroundColor(returns >= 0 ? .green : .red)
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
                        
                        if account.accountType == AccountType.loan.rawValue {
                            HStack {
                                TextField("Interest Rate (%)", text: $interestRate)
                                    .keyboardType(.decimalPad)
                                Text("% per year")
                            }
                            
                            HStack {
                                TextField("Principal Amount", text: $creditLimit)
                                    .keyboardType(.decimalPad)
                                Picker("Currency", selection: $currencySettings.selectedCurrency) {
                                    ForEach(Currency.allCases, id: \.self) { currency in
                                        Text(currency.symbol).tag(currency)
                                    }
                                }
                                .labelsHidden()
                            }
                            
                            DatePicker("Loan Date", selection: $loanDate, displayedComponents: .date)
                        }
                    }
                }
            }
            .toolbar(content: {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAccount() }
                }
            })
            .navigationTitle("Edit Account")
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
        var metadata = account.metadataDictionary
        if account.accountType == AccountType.loan.rawValue {
            guard let rate = Double(interestRate),
                  let principal = Double(creditLimit) else {
                showingError = true
                return
            }
            metadata["principalAmount"] = String(principal)
            metadata["interestRate"] = String(rate)
            metadata["loanDate"] = ISO8601DateFormatter().string(from: loanDate)
            metadata["lastInterestCalculationDate"] = ISO8601DateFormatter().string(from: lastInterestDate)
        }
        if account.accountType == AccountType.mutualFund.rawValue {
            metadata["amfiSchemeCode"] = amfiSchemeCode
        }
        viewModel.updateAccount(
            account,
            name: accountName,
            balance: balanceValue,
            creditLimit: creditLimitValue,
            metadata: metadata
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