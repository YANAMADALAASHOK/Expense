import SwiftUI

struct AddLoanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var loanManager = LoanManager.shared
    @StateObject private var currencySettings = CurrencySettings.shared
    
    // Optional account for editing mode
    let editingAccount: CDAccount?
    
    // Computed properties for edit mode
    var isEditMode: Bool { editingAccount != nil }
    var navigationTitle: String { 
        if isEditMode {
            return isPersonalLoanGiven ? "Edit Personal Loan" : "Edit Loan"
        } else {
            return isPersonalLoanGiven ? "Add Personal Loan" : "Add Loan"
        }
    }
    
    @State private var loanName = ""
    @State private var principalAmount = ""
    @State private var outstandingAmount = ""
    @State private var interestRate = ""
    @State private var loanTenure = 60 // Default 5 years (total months)
    @State private var loanStartDate = Date()
    @State private var loanDate = Date() // Current date for record keeping
    @State private var notes = ""
    @State private var isPersonalLoanGiven = false
    @State private var showingError = false
    @State private var errorMessage = ""
    // Repayment configuration
    @State private var repaymentType: String = "EMI" // "EMI" or "ONE_TIME"
    @State private var emiDayOfMonth: Int = 5
    @State private var interestDayOfMonth: Int = 1
    @State private var customEmiAmount: String = ""
    @State private var selectedFundingAccount: CDAccount?
    
    // Initializers
    init(viewModel: ExpenseViewModel, editingAccount: CDAccount? = nil) {
        self.viewModel = viewModel
        self.editingAccount = editingAccount
    }
    
    var monthsElapsed: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: loanStartDate, to: Date())
        return max(0, components.month ?? 0)
    }
    
    var remainingPayments: Int {
        return max(0, loanTenure - monthsElapsed)
    }
    
    var nextInterestDate: Date {
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        let currentDay = calendar.component(.day, from: today)
        
        // If interest day hasn't passed this month, use this month
        if currentDay < interestDayOfMonth {
            return calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: interestDayOfMonth)) ?? today
        } else {
            // Otherwise, use next month
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
            let nextMonthComponents = calendar.dateComponents([.year, .month], from: nextMonth)
            return calendar.date(from: DateComponents(year: nextMonthComponents.year, month: nextMonthComponents.month, day: interestDayOfMonth)) ?? today
        }
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
                
                Section("Loan Details 📋") {
                    TextField(isPersonalLoanGiven ? "Person's Name" : "Loan Name", text: $loanName)
                    
                    HStack {
                        TextField(isPersonalLoanGiven ? "Amount Given" : "Original Principal Amount", text: $principalAmount)
                            .keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencySettings.selectedCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    HStack {
                        TextField("Current Outstanding Amount", text: $outstandingAmount)
                            .keyboardType(.decimalPad)
                        Text(currencySettings.selectedCurrency.symbol)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        TextField("Interest Rate", text: $interestRate)
                            .keyboardType(.decimalPad)
                        Text("% per year")
                    }
                    
                    // Only show tenure, repayment, and EMI fields for loans taken
                    if !isPersonalLoanGiven {
                        Picker("Original Loan Tenure", selection: $loanTenure) {
                            Text("1 Year (12 months)").tag(12)
                            Text("2 Years (24 months)").tag(24)
                            Text("3 Years (36 months)").tag(36)
                            Text("4 Years (48 months)").tag(48)
                            Text("5 Years (60 months)").tag(60)
                            Text("7 Years (84 months)").tag(84)
                            Text("10 Years (120 months)").tag(120)
                        }
                    }
                    
                    DatePicker(isPersonalLoanGiven ? "Date Given" : "Loan Start Date", selection: $loanStartDate, in: ...Date(), displayedComponents: [.date])
                    
                    DatePicker("Record Date", selection: $loanDate, in: ...Date(), displayedComponents: [.date])
                }

                // Repayment configuration - Only for loans taken
                if !isPersonalLoanGiven {
                    Section("Repayment") {
                        Picker("Repayment Type", selection: $repaymentType) {
                            Text("EMI").tag("EMI")
                            Text("One-time").tag("ONE_TIME")
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        if repaymentType == "EMI" {
                            Picker("EMI Debit Day", selection: $emiDayOfMonth) {
                                ForEach(1...31, id: \.self) { day in
                                    Text("Day \(day)").tag(day)
                                }
                            }

                            TextField("EMI Amount", text: $customEmiAmount)
                                .keyboardType(.decimalPad)

                            Picker("Funding Account", selection: $selectedFundingAccount) {
                                Text("Select Account").tag(nil as CDAccount?)
                                ForEach(bankAccounts) { account in
                                    Text(account.wrappedAccountName).tag(account as CDAccount?)
                                }
                            }
                        }
                    }
                    
                    Section("Interest Configuration") {
                        Picker("Interest Generation Day", selection: $interestDayOfMonth) {
                            ForEach(1...31, id: \.self) { day in
                                Text("Day \(day)").tag(day)
                            }
                        }
                        
                        HStack {
                            Text("Next Interest Date:")
                            Spacer()
                            Text(nextInterestDate, format: .dateTime.day().month().year())
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                        }
                    }
                }
                
                
                Section("Additional Details") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if isEditMode {
                    populateFieldsForEditing()
                }
            }
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
    
    private func populateFieldsForEditing() {
        guard let account = editingAccount else { return }
        
        loanName = account.wrappedAccountName
        outstandingAmount = String(account.balance)
        isPersonalLoanGiven = account.wrappedAccountType == .personalLoanGiven
        
        // Get loan details from metadata
        if let details = loanManager.getLoanDetails(account) {
            principalAmount = String(details.principalAmount)
            interestRate = String(details.interestRate)
            loanTenure = details.loanTenure
            loanStartDate = details.loanDate
            notes = details.notes ?? ""
            
            if let emi = details.emiAmount {
                customEmiAmount = String(emi)
                repaymentType = "EMI"
            } else {
                repaymentType = details.repaymentType ?? "ONE_TIME"
            }
            
            if let interestDay = details.interestDayOfMonth {
                interestDayOfMonth = interestDay
            }
        }
        
        // Get additional metadata
        let metadata = account.metadataDictionary
        if let emiDay = metadata["emiDayOfMonth"], let day = Int(emiDay) {
            emiDayOfMonth = day
        }
        
        if let fundingId = metadata["emiFundingAccountId"], let uuid = UUID(uuidString: fundingId) {
            selectedFundingAccount = viewModel.accounts.first { $0.id == uuid }
        }
    }

    private func saveLoan() {
        guard let principal = Double(principalAmount),
              let outstanding = Double(outstandingAmount),
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
        
        guard outstanding > 0 else {
            errorMessage = "Outstanding amount must be greater than 0"
            showingError = true
            return
        }
        
        guard outstanding <= principal else {
            errorMessage = "Outstanding amount cannot be greater than principal amount"
            showingError = true
            return
        }
        
        guard rate >= 0 else {
            errorMessage = "Interest rate cannot be negative"
            showingError = true
            return
        }

        // Validate EMI settings if EMI selected (only for loans taken, not personal loans given)
        var emiAmountToSave: Double? = nil
        var fundingAccountId: UUID? = nil
        if !isPersonalLoanGiven && repaymentType == "EMI" {
            guard let emiValue = Double(customEmiAmount), emiValue > 0 else {
                errorMessage = "Please enter a valid EMI amount"
                showingError = true
                return
            }
            guard let funding = selectedFundingAccount, let fid = funding.id else {
                errorMessage = "Please select a funding bank account for EMI"
                showingError = true
                return
            }
            emiAmountToSave = emiValue
            fundingAccountId = fid
        }
        
        let account: CDAccount
        
        if isEditMode {
            // Update existing account
            account = editingAccount!
            account.accountName = loanName
            account.accountType = isPersonalLoanGiven ? AccountType.personalLoanGiven.rawValue : AccountType.loan.rawValue
            account.balance = outstanding
            account.creditLimit = principal
            
            // Update metadata
            var metadata: [String: String] = [
                "principalAmount": String(principal),
                "interestRate": String(rate),
                "loanDate": ISO8601DateFormatter().string(from: loanStartDate),
                "notes": notes
            ]
            
            // Only add EMI and repayment-related fields for loans taken (not personal loans given)
            if !isPersonalLoanGiven {
                metadata["loanTenure"] = String(loanTenure)
                
                if let emi = emiAmountToSave {
                    metadata["emiAmount"] = String(emi)
                }
                if let repaymentType = repaymentType.isEmpty ? nil : repaymentType {
                    metadata["repaymentType"] = repaymentType
                }
                if repaymentType == "EMI" {
                    metadata["emiDayOfMonth"] = String(emiDayOfMonth)
                }
                metadata["interestDayOfMonth"] = String(interestDayOfMonth)
                if let fundingId = fundingAccountId {
                    metadata["emiFundingAccountId"] = fundingId.uuidString
                }
                metadata["monthsElapsed"] = String(monthsElapsed)
                metadata["remainingPayments"] = String(remainingPayments)
            }
            
            account.metadataDictionary = metadata
        } else {
            // Create new loan account
            // Only pass EMI-related parameters for loans taken
            account = loanManager.createLoanAccount(
                name: loanName,
                principalAmount: principal,
                interestRate: rate,
                loanDate: loanStartDate, // Use loan start date for calculations
                notes: notes,
                isPersonalLoanGiven: isPersonalLoanGiven,
                emiAmount: isPersonalLoanGiven ? nil : emiAmountToSave,
                loanTenure: isPersonalLoanGiven ? 0 : loanTenure,
                repaymentType: isPersonalLoanGiven ? nil : repaymentType,
                emiDayOfMonth: isPersonalLoanGiven ? nil : (repaymentType == "EMI" ? emiDayOfMonth : nil),
                interestDayOfMonth: isPersonalLoanGiven ? nil : interestDayOfMonth,
                emiFundingAccountId: isPersonalLoanGiven ? nil : fundingAccountId,
                monthsElapsed: isPersonalLoanGiven ? 0 : monthsElapsed,
                remainingPayments: isPersonalLoanGiven ? 0 : remainingPayments,
                in: context
            )
            
            // Set the current outstanding amount as the balance
            account.balance = outstanding
            
            // Add to viewModel accounts
            viewModel.accounts.append(account)
        }
        
        // Save context
        do {
            try context.save()
            print("Loan created: \(loanName), Principal: \(principal), Outstanding: \(outstanding), Rate: \(rate)%")
            dismiss()
        } catch {
            errorMessage = "Failed to save loan: \(error.localizedDescription)"
            showingError = true
        }
    }

    private var bankAccounts: [CDAccount] {
        viewModel.accounts.filter { account in
            let type = account.accountType ?? ""
            return type == AccountType.bankAccount.rawValue ||
                   type == AccountType.savings.rawValue ||
                   type == AccountType.cash.rawValue
        }
    }
}

#if DEBUG
struct AddLoanView_Previews: PreviewProvider {
    static var previews: some View {
        AddLoanView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext), editingAccount: nil)
    }
}
#endif 