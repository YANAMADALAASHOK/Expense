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
                    TextField("Scheme Name", text: $schemeName)
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
        
        viewModel.addAccount(
            name: schemeName,
            type: .mutualFund,
            balance: currentMarketValue,
            creditLimit: investedValue  // Using creditLimit to store invested amount
        )
        
        dismiss()
    }
} 