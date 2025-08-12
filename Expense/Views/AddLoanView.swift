import SwiftUI

struct AddLoanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var loanManager = LoanManager.shared
    @StateObject private var currencySettings = CurrencySettings.shared
    
    @State private var loanName = ""
    @State private var principalAmount = ""
    @State private var interestRate = ""
    @State private var loanTenure = 60 // Default 5 years
    @State private var loanDate = Date()
    @State private var notes = ""
    @State private var isPersonalLoanGiven = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var calculatedEMI: Double {
        guard let principal = Double(principalAmount),
              let rate = Double(interestRate),
              rate > 0 else { return 0 }
        
        let monthlyRate = rate / 12.0 / 100.0
        
        if monthlyRate == 0 { return principal / Double(loanTenure) }
        
        let numerator = principal * monthlyRate * pow(1 + monthlyRate, Double(loanTenure))
        let denominator = pow(1 + monthlyRate, Double(loanTenure)) - 1
        
        return numerator / denominator
    }
    
    var totalInterestPayable: Double {
        (calculatedEMI * Double(loanTenure)) - (Double(principalAmount) ?? 0)
    }
    
    var totalAmountPayable: Double {
        calculatedEMI * Double(loanTenure)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Loan Type") {
                    Picker("Loan Type", selection: $isPersonalLoanGiven) {
                        Text("Loan Taken").tag(false)
                        Text("Personal Loan Given").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Loan Details") {
                    TextField("Loan Name", text: $loanName)
                    
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
                        TextField("Interest Rate", text: $interestRate)
                            .keyboardType(.decimalPad)
                        Text("% per year")
                    }
                    
                    Picker("Loan Tenure", selection: $loanTenure) {
                        Text("1 Year (12 months)").tag(12)
                        Text("2 Years (24 months)").tag(24)
                        Text("3 Years (36 months)").tag(36)
                        Text("4 Years (48 months)").tag(48)
                        Text("5 Years (60 months)").tag(60)
                        Text("7 Years (84 months)").tag(84)
                        Text("10 Years (120 months)").tag(120)
                    }
                    
                    DatePicker("Loan Date", selection: $loanDate, in: ...Date(), displayedComponents: [.date])
                }
                
                if let principal = Double(principalAmount), principal > 0,
                   let rate = Double(interestRate), rate > 0 {
                    Section("EMI Calculation") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Principal Amount:")
                                Spacer()
                                Text(principal, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Interest Rate:")
                                Spacer()
                                Text("\(rate, specifier: "%.2f")% p.a.")
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Loan Tenure:")
                                Spacer()
                                Text("\(loanTenure) months")
                                    .fontWeight(.medium)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Monthly EMI:")
                                Spacer()
                                Text(calculatedEMI, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            
                            HStack {
                                Text("Total Interest:")
                                Spacer()
                                Text(totalInterestPayable, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                            }
                            
                            HStack {
                                Text("Total Amount:")
                                Spacer()
                                Text(totalAmountPayable, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .fontWeight(.bold)
                                    .foregroundColor(isPersonalLoanGiven ? .green : .red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Additional Details") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle(isPersonalLoanGiven ? "Add Personal Loan" : "Add Loan")
            .navigationBarTitleDisplayMode(.inline)
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
              !loanName.isEmpty else {
            errorMessage = "Please fill in all required fields"
            showingError = true
            return
        }
        
        guard principal > 0 else {
            errorMessage = "Principal amount must be greater than 0"
            showingError = true
            return
        }
        
        guard rate >= 0 else {
            errorMessage = "Interest rate cannot be negative"
            showingError = true
            return
        }
        
        // Create loan account with EMI calculation
        let account = loanManager.createLoanAccount(
            name: loanName,
            principalAmount: principal,
            interestRate: rate,
            loanDate: loanDate,
            notes: notes,
            isPersonalLoanGiven: isPersonalLoanGiven,
            emiAmount: calculatedEMI,
            loanTenure: loanTenure,
            in: context
        )
        
        // Add to viewModel accounts
        viewModel.accounts.append(account)
        
        // Save context
        do {
            try context.save()
            print("Loan created: \(loanName), Amount: \(principal), Rate: \(rate)%, EMI: \(calculatedEMI)")
            dismiss()
        } catch {
            errorMessage = "Failed to save loan: \(error.localizedDescription)"
            showingError = true
        }
    }
}

#if DEBUG
struct AddLoanView_Previews: PreviewProvider {
    static var previews: some View {
        AddLoanView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 