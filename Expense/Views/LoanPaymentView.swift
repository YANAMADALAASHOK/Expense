import SwiftUI

struct LoanPaymentView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    
    let preSelectedLoan: CDAccount?
    
    init(viewModel: ExpenseViewModel, preSelectedLoan: CDAccount? = nil) {
        self.viewModel = viewModel
        self.preSelectedLoan = preSelectedLoan
    }
    
    @State private var amount = ""
    @State private var selectedFromAccount: CDAccount?
    @State private var selectedLoanAccount: CDAccount?
    @State private var notes = ""
    @State private var transactionDate = Date()
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Payment Details") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    
                    DatePicker("Date", selection: $transactionDate, displayedComponents: .date)
                }
                
                Section("From Account (Bank Account)") {
                    Picker("Select Bank Account", selection: $selectedFromAccount) {
                        Text("Select Account").tag(nil as CDAccount?)
                        ForEach(bankAccounts) { account in
                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                        }
                    }
                }
                
                Section("To Loan Account") {
                    Picker("Select Loan", selection: $selectedLoanAccount) {
                        Text("Select Loan").tag(nil as CDAccount?)
                        ForEach(loanAccounts) { account in
                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                        }
                    }
                    
                    if let loan = selectedLoanAccount {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Outstanding: \(loan.balance, format: .currency(code: "INR"))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let amountValue = Double(amount), amountValue > 0 {
                                let newBalance = loan.balance - amountValue
                                Text("New Outstanding: \(newBalance, format: .currency(code: "INR"))")
                                    .font(.caption)
                                    .foregroundColor(newBalance >= 0 ? .green : .red)
                            }
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (Optional)", text: $notes)
                }
            }
            .navigationTitle("Loan Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pay") { processLoanPayment() }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
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
    
    private var loanAccounts: [CDAccount] {
        viewModel.accounts.filter { account in
            let type = account.accountType ?? ""
            return type == AccountType.loan.rawValue ||
                   type == AccountType.mortgage.rawValue
        }
    }
    
    private func processLoanPayment() {
        // Validate inputs
        guard let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Please enter a valid amount"
            showingError = true
            return
        }
        
        guard let fromAccount = selectedFromAccount else {
            errorMessage = "Please select a bank account to pay from"
            showingError = true
            return
        }
        
        guard let loanAccount = selectedLoanAccount else {
            errorMessage = "Please select a loan account"
            showingError = true
            return
        }
        
        // Check if bank account has sufficient balance
        if fromAccount.balance < amountValue {
            errorMessage = "Insufficient balance in \(fromAccount.wrappedAccountName)"
            showingError = true
            return
        }
        
        // Check if loan payment is valid
        if loanAccount.balance < amountValue {
            errorMessage = "Payment amount cannot exceed outstanding loan amount"
            showingError = true
            return
        }
        
        // Process the loan payment
        viewModel.processLoanPayment(
            amount: amountValue,
            fromAccount: fromAccount,
            toLoanAccount: loanAccount,
            notes: notes.isEmpty ? "Loan Payment" : notes,
            date: transactionDate
        )
        
        dismiss()
    }
}

#if DEBUG
struct LoanPaymentView_Previews: PreviewProvider {
    static var previews: some View {
        LoanPaymentView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 