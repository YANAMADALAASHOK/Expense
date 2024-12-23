import SwiftUI

struct EditPersonalLoanGivenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    let account: CDAccount
    
    @State private var borrowerName: String
    @State private var principalAmount: String
    @State private var interestRate: String
    @State private var loanDate: Date
    @State private var notes: String
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(viewModel: ExpenseViewModel, account: CDAccount) {
        self.viewModel = viewModel
        self.account = account
        
        let metadata = account.metadata ?? [:]
        _borrowerName = State(initialValue: metadata["borrowerName"] ?? "")
        _principalAmount = State(initialValue: String(account.creditLimit))
        _interestRate = State(initialValue: metadata["interestRate"] ?? "")
        _notes = State(initialValue: metadata["notes"] ?? "")
        
        if let loanDateString = metadata["loanDate"],
           let date = ISO8601DateFormatter().date(from: loanDateString) {
            _loanDate = State(initialValue: date)
        } else {
            _loanDate = State(initialValue: Date())
        }
    }
    
    var calculatedAmount: Double {
        guard let principal = Double(principalAmount),
              let rate = Double(interestRate) else { return 0 }
        
        let days = Double(Calendar.current.dateComponents([.day], from: loanDate, to: Date()).day ?? 0)
        let months = days / 30.0  // Convert days to months
        
        // Calculate interest based on rate per 100 rupees per month
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
            .navigationTitle("Edit Personal Loan")
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
        
        // Update the account
        account.accountName = "Loan to \(borrowerName)"
        account.balance = calculatedAmount
        account.creditLimit = principal
        account.metadata = metadata
        
        viewModel.saveContext()
        dismiss()
    }
} 