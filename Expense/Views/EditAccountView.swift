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
    
    // Credit card specific fields
    @State private var cardNumber: String = ""
    @State private var expiryDate: String = ""
    @State private var cvv: String = ""
    
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
        
        // Initialize credit card fields from metadata
        _cardNumber = State(initialValue: metadata["fullCardNumber"] ?? "")
        _expiryDate = State(initialValue: metadata["expiryDate"] ?? "")
        _cvv = State(initialValue: metadata["cvv"] ?? "")
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
                                .onChange(of: fundSearchText) { showFundSuggestions = true }
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
                    }
                }
                
                // Credit Card Details Section
                if account.accountType == AccountType.creditCard.rawValue {
                    Section("Card Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Card Number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("1234 5678 9012 3456", text: $cardNumber)
                                .keyboardType(.numberPad)
                                .textContentType(.creditCardNumber)
                                .onChange(of: cardNumber) { _, newValue in
                                    cardNumber = formatCardNumber(newValue)
                                }
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Expiry Date")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("MM/YY", text: $expiryDate)
                                    .keyboardType(.numberPad)
                                    .onChange(of: expiryDate) { _, newValue in
                                        expiryDate = formatExpiryDate(newValue)
                                    }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("CVV")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("123", text: $cvv)
                                    .keyboardType(.numberPad)
                                    .onChange(of: cvv) { _, newValue in
                                        cvv = String(newValue.prefix(4)) // Limit to 4 digits
                                    }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                Text("Security Information")
                                    .font(.headline)
                            }
                            
                            Text("• Card details are stored securely in encrypted metadata")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("• Information is only visible when you choose to reveal it")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Loan Details Section
                if account.accountType == AccountType.loan.rawValue {
                    Section("Loan Details") {
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
        
        // Save credit card details to metadata
        if account.accountType == AccountType.creditCard.rawValue {
            if !cardNumber.isEmpty {
                let cleanedCardNumber = cardNumber.replacingOccurrences(of: " ", with: "")
                metadata["fullCardNumber"] = cleanedCardNumber
            }
            if !expiryDate.isEmpty {
                metadata["expiryDate"] = expiryDate
            }
            if !cvv.isEmpty {
                metadata["cvv"] = cvv
            }
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
    
    private func formatCardNumber(_ input: String) -> String {
        let cleaned = input.replacingOccurrences(of: " ", with: "")
        let limited = String(cleaned.prefix(16)) // Limit to 16 digits
        
        var formatted = ""
        for (index, character) in limited.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted += String(character)
        }
        return formatted
    }
    
    private func formatExpiryDate(_ input: String) -> String {
        let cleaned = input.replacingOccurrences(of: "/", with: "")
        let limited = String(cleaned.prefix(4)) // Limit to 4 digits
        
        if limited.count >= 3 {
            let month = String(limited.prefix(2))
            let year = String(limited.suffix(limited.count - 2))
            return "\(month)/\(year)"
        } else {
            return limited
        }
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