import SwiftUI

struct AddMutualFundView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    
    @State private var schemeName = ""
    @State private var investedAmount = ""
    @State private var currentValue = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var amfiSchemeCode: String = ""
    @State private var fundSearchText: String = ""
    @State private var showFundSuggestions: Bool = false
    @State private var isFundListLoading: Bool = false
    
    private var profit: Double {
        (Double(currentValue) ?? 0) - (Double(investedAmount) ?? 0)
    }
    
    private var returns: Double {
        guard let invested = Double(investedAmount), invested > 0 else { return 0 }
        return (profit / invested) * 100
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Mutual Fund Details") {
                    VStack(alignment: .leading) {
                        TextField("Scheme Name", text: $schemeName)
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
                                                    schemeName = fund.name
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
                    }
                }
                
                Section("Investment Details") {
                    HStack {
                        TextField("Initial Investment", text: $investedAmount)
                            .keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencySettings.selectedCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    HStack {
                        TextField("Current Market Value", text: $currentValue)
                            .keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencySettings.selectedCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                if let invested = Double(investedAmount), 
                   let current = Double(currentValue), 
                   invested > 0 {
                    Section("Performance") {
                        HStack {
                            Text("Initial Investment:")
                            Spacer()
                            Text(invested, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        
                        HStack {
                            Text("Current Value:")
                            Spacer()
                            Text(current, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        
                        HStack {
                            Text("Profit/Loss:")
                            Spacer()
                            Text(profit, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(profit >= 0 ? .green : .red)
                        }
                        
                        HStack {
                            Text("Returns:")
                            Spacer()
                            Text(returns, format: .percent)
                                .foregroundColor(returns >= 0 ? .green : .red)
                        }
                    }
                }
            }
            .navigationTitle("Add Mutual Fund")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveMutualFund() }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveMutualFund() {
        guard let investedValue = Double(investedAmount),
              let currentMarketValue = Double(currentValue),
              !schemeName.isEmpty else {
            errorMessage = "Please fill in all required fields"
            showingError = true
            return
        }
        var metadata: [String: String]? = nil
        if !amfiSchemeCode.isEmpty {
            metadata = ["amfiSchemeCode": amfiSchemeCode]
        }
        viewModel.addAccount(
            name: schemeName,
            type: .mutualFund,
            balance: currentMarketValue,
            creditLimit: investedValue,  // Using creditLimit to store invested amount
            metadata: metadata
        )
        dismiss()
    }
} 