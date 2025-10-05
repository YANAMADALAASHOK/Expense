import SwiftUI

// MARK: - Pay Bill View
struct PayBillView: View {
    @Environment(\.dismiss) private var dismiss
    let bill: CreditCardBill
    let account: CDAccount
    let viewModel: ExpenseViewModel
    let onPaymentComplete: () -> Void
    
    @State private var selectedPaymentAccount: CDAccount?
    @State private var paymentAmount: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private var bankAccounts: [CDAccount] {
        viewModel.accounts.filter { $0.wrappedAccountType == .bankAccount }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Bill Info Section
                Section("Bill Details") {
                    HStack {
                        Text("Statement Date")
                        Spacer()
                        Text(bill.statementDate, style: .date)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Due Date")
                        Spacer()
                        Text(bill.dueDate, style: .date)
                            .foregroundColor(.red)
                    }
                    
                    HStack {
                        Text("Total Amount Due")
                        Spacer()
                        Text(bill.totalAmount, format: .currency(code: "INR"))
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    
                    HStack {
                        Text("Minimum Amount Due")
                        Spacer()
                        Text(bill.minimumDue, format: .currency(code: "INR"))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Payment Amount Section
                Section("Payment Amount") {
                    TextField("Enter Amount", text: $paymentAmount)
                        .keyboardType(.decimalPad)
                    
                    HStack {
                        Button("Pay Minimum") {
                            paymentAmount = String(format: "%.2f", bill.minimumDue)
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Pay Full") {
                            paymentAmount = String(format: "%.2f", bill.totalAmount)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                // Select Payment Account Section
                Section("Pay From") {
                    if bankAccounts.isEmpty {
                        Text("No bank accounts available")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(bankAccounts) { bankAccount in
                            Button(action: {
                                selectedPaymentAccount = bankAccount
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bankAccount.wrappedAccountName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("Balance: \(bankAccount.balance, format: .currency(code: "INR"))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedPaymentAccount?.id == bankAccount.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Payment Summary
                if let paymentAccount = selectedPaymentAccount,
                   let amount = Double(paymentAmount), amount > 0 {
                    Section("Payment Summary") {
                        HStack {
                            Text("From")
                            Spacer()
                            Text(paymentAccount.wrappedAccountName)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("To")
                            Spacer()
                            Text(account.wrappedAccountName)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Amount")
                            Spacer()
                            Text(amount, format: .currency(code: "INR"))
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: processBillPayment) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Confirm Payment")
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                }
            }
            .navigationTitle("Pay Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func processBillPayment() {
        guard let paymentAccount = selectedPaymentAccount else {
            errorMessage = "Please select a payment account"
            showingError = true
            return
        }
        
        guard let amount = Double(paymentAmount), amount > 0 else {
            errorMessage = "Please enter a valid payment amount"
            showingError = true
            return
        }
        
        guard amount <= paymentAccount.balance else {
            errorMessage = "Insufficient balance in payment account"
            showingError = true
            return
        }
        
        // Process payment: Debit from bank, Credit to credit card
        viewModel.processCreditCardPayment(
            amount: amount,
            fromAccount: paymentAccount,
            toCreditCardAccount: account,
            notes: "Credit Card Bill Payment"
        )
        
        // Mark bill as paid if full payment
        if amount >= bill.totalAmount {
            CreditCardBillStorage.shared.markBillAsPaid(bill.id)
        }
        
        // Call completion handler
        onPaymentComplete()
        
        // Dismiss
        dismiss()
    }
}

// MARK: - Credit Card Bill Details View
struct CreditCardBillDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let bill: CreditCardBill
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Bill Summary Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bill Summary")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Statement Date")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bill.statementDate, style: .date)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Due Date")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bill.dueDate, style: .date)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Amount Due")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bill.totalAmount, format: .currency(code: "INR"))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Minimum Due")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bill.minimumDue, format: .currency(code: "INR"))
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Credit Limit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bill.creditLimit, format: .currency(code: "INR"))
                                    .font(.subheadline)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Available Limit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bill.availableLimit, format: .currency(code: "INR"))
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        // Usage Bar
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Current Usage")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(bill.currentUsage, format: .currency(code: "INR"))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 8)
                                    
                                    let percentage = bill.creditLimit > 0 ? bill.currentUsage / bill.creditLimit : 0
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(percentage > 0.8 ? Color.red : percentage > 0.5 ? Color.orange : Color.blue)
                                        .frame(width: geometry.size.width * min(percentage, 1.0), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Transactions List
                    if !bill.transactions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transactions (\(bill.transactions.count))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            ForEach(bill.transactions.sorted { $0.date > $1.date }) { transaction in
                                CreditCardBillTransactionRowView(transaction: transaction)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .navigationTitle("Bill Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Credit Card Bill Transaction Row View
private struct CreditCardBillTransactionRowView: View {
    let transaction: BillTransaction
    
    var body: some View {
        HStack(spacing: 12) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: categoryIcon)
                    .foregroundColor(categoryColor)
                    .font(.system(size: 18))
            }
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(transaction.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(transaction.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Amount
            Text(transaction.amount, format: .currency(code: "INR"))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private var categoryIcon: String {
        switch transaction.category {
        case "Shopping": return "cart.fill"
        case "Food & Dining": return "fork.knife"
        case "Transportation": return "car.fill"
        case "Entertainment": return "tv.fill"
        default: return "creditcard.fill"
        }
    }
    
    private var categoryColor: Color {
        switch transaction.category {
        case "Shopping": return .orange
        case "Food & Dining": return .green
        case "Transportation": return .blue
        case "Entertainment": return .purple
        default: return .gray
        }
    }
}
