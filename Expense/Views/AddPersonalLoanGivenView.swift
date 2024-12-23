import SwiftUI

struct AddPersonalLoanGivenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    
    @State private var borrowerName = ""
    @State private var principalAmount = ""
    @State private var interestRate = ""
    @State private var loanDate = Date()
    @State private var notes = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var calculatedAmount: Double {
        guard let principal = Double(principalAmount),
              let rate = Double(interestRate) else { return 0 }
        
        let days = Double(Calendar.current.dateComponents([.day], from: loanDate, to: Date()).day ?? 0)
        let months = days / 30.0  // Convert days to months
        
        // Calculate interest based on rate per 100 rupees per month
        // For example: if rate is 1.5, it means 1.5 rupees per 100 rupees per month
        let interestPer100PerMonth = rate
        let interest = (principal / 100.0) * interestPer100PerMonth * months
        
        return principal + interest
    }
    
    var interestEarned: Double {
        calculatedAmount - (Double(principalAmount) ?? 0)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Loan Details") {
                    TextField("Borrower Name", text: $borrowerName)
                    
                    HStack {
                        TextField("Principal Amount", text: $principalAmount)
                            .keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencySettings.selectedCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    HStack {
                        TextField("Interest Rate (%)", text: $interestRate)
                            .keyboardType(.decimalPad)
                        Text("% per year")
                    }
                    
                    DatePicker("Loan Date", selection: $loanDate, in: ...Date(), displayedComponents: [.date])
                }
                
                Section("Additional Details") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
                
                if let principal = Double(principalAmount), principal > 0 {
                    Section("Calculation") {
                        HStack {
                            Text("Principal Amount:")
                            Spacer()
                            Text(principal, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        
                        HStack {
                            Text("Interest Earned:")
                            Spacer()
                            Text(interestEarned, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.green)
                        }
                        
                        HStack {
                            Text("Total Amount:")
                            Spacer()
                            Text(calculatedAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .fontWeight(.bold)
                        }
                    }
                }
            }
            .navigationTitle("Add Personal Loan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLoan() }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveLoan() {
        guard let principal = Double(principalAmount),
              let rate = Double(interestRate),
              !borrowerName.isEmpty else {
            errorMessage = "Please fill in all required fields"
            showingError = true
            return
        }
        
        // Store loan details in metadata
        let metadata: [String: String] = [
            "borrowerName": borrowerName,
            "interestRate": interestRate,
            "loanDate": loanDate.ISO8601Format(),
            "notes": notes
        ]
        
        viewModel.addAccount(
            name: "Loan to \(borrowerName)",
            type: .personalLoanGiven,
            balance: calculatedAmount,
            creditLimit: principal,  // Store principal amount in creditLimit
            metadata: metadata
        )
        
        dismiss()
    }
} 