import SwiftUI

struct LoanDetailsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var loanManager = LoanManager.shared
    @StateObject private var currencySettings = CurrencySettings.shared
    let account: CDAccount
    
    @State private var showingPaymentSheet = false
    @State private var showingEditSheet = false
    @State private var showingInterestCalculation = false
    
    var loanDetails: LoanDetails? {
        loanManager.getLoanDetails(account)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Loan Summary Card
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.wrappedAccountName)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(account.wrappedAccountType.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(account.balance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(account.wrappedAccountType.isAsset ? .green : .red)
                            Text("Outstanding Amount")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                                            if let details = loanDetails {
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Principal Amount")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(details.principalAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                        .font(.headline)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 8) {
                                    Text("Interest Rate")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(details.interestRate, specifier: "%.2f")% p.a.")
                                        .font(.headline)
                                }
                            }
                            
                            if let emi = details.emiAmount, emi > 0 {
                                Divider()
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Monthly EMI")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(emi, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 8) {
                                        Text("Calculated EMI")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(details.calculatedEMI, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        
                        if details.calculatedInterest > 0 {
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Accrued Interest")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(details.calculatedInterest, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 8) {
                                    Text("Total with Interest")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(details.totalAmountWithInterest, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                        .font(.headline)
                                        .foregroundColor(account.wrappedAccountType.isAsset ? .green : .red)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
                
                // Action Buttons
                VStack(spacing: 12) {
                    if account.wrappedAccountType == .loan {
                        Button(action: { showingPaymentSheet = true }) {
                            HStack {
                                Image(systemName: "creditcard.fill")
                                Text("Make Payment")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    Button(action: { showingInterestCalculation = true }) {
                        HStack {
                            Image(systemName: "percent")
                            Text("Calculate Interest")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Button(action: { showingEditSheet = true }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit Loan")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                // Loan Information
                if let details = loanDetails {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Loan Information")
                                .font(.headline)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            InfoRow(title: "Loan Date", value: details.loanDate.formatted(date: .abbreviated, time: .omitted))
                            InfoRow(title: "Last Interest Calculation", value: details.lastInterestCalculationDate.formatted(date: .abbreviated, time: .omitted))
                            InfoRow(title: "Next Calculation", value: details.nextInterestCalculationDate.formatted(date: .abbreviated, time: .omitted))
                            InfoRow(title: "Days Until Next", value: "\(details.daysUntilNextCalculation) days")
                            InfoRow(title: "Interest Frequency", value: "Monthly")
                            if let notes = details.notes, !notes.isEmpty {
                                InfoRow(title: "Notes", value: notes)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
                
                // Recent Transactions
                VStack(spacing: 16) {
                    HStack {
                        Text("Recent Transactions")
                            .font(.headline)
                        Spacer()
                    }
                    
                    if account.transactionsArray.isEmpty {
                        Text("No transactions yet")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(account.transactionsArray.prefix(5)) { transaction in
                                TransactionRowView(transaction: transaction)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Loan Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaymentSheet) {
            LoanPaymentView(viewModel: viewModel, preSelectedLoan: account)
        }
        .sheet(isPresented: $showingEditSheet) {
            if account.wrappedAccountType == .personalLoanGiven {
                EditPersonalLoanGivenView(viewModel: viewModel, account: account)
            } else {
                EditAccountView(viewModel: viewModel, account: account)
            }
        }
        .sheet(isPresented: $showingInterestCalculation) {
            InterestCalculationView(account: account, loanManager: loanManager)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct TransactionRowView: View {
    let transaction: CDTransaction
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.wrappedCategory)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(transaction.wrappedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(transaction.isCredit ? .green : .red)
                Text(transaction.wrappedNotes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct InterestCalculationView: View {
    let account: CDAccount
    let loanManager: LoanManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var loanDetails: LoanDetails? {
        loanManager.getLoanDetails(account)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let details = loanDetails {
                    VStack(spacing: 16) {
                        Text("Interest Calculation")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(spacing: 12) {
                            InfoRow(title: "Outstanding Amount", value: details.outstandingAmount.formatted(.currency(code: currencySettings.selectedCurrency.rawValue)))
                            InfoRow(title: "Interest Rate", value: String(format: "%.2f%% p.a.", details.interestRate))
                            InfoRow(title: "Days Since Last Calculation", value: "\(Calendar.current.dateComponents([.day], from: details.lastInterestCalculationDate, to: Date()).day ?? 0)")
                            InfoRow(title: "Calculated Interest", value: details.calculatedInterest.formatted(.currency(code: currencySettings.selectedCurrency.rawValue)))
                            InfoRow(title: "Total with Interest", value: details.totalAmountWithInterest.formatted(.currency(code: currencySettings.selectedCurrency.rawValue)))
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        Button("Apply Interest") {
                            loanManager.updateLoanWithInterest(account, in: context)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        
                        Text("Unable to load loan details")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("This loan may not have the required metadata (principal amount, interest rate, or loan date). Please edit the loan to add these details.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Interest Calculation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
struct LoanDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        LoanDetailsView(
            viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext),
            account: PreviewHelper.shared.sampleAccount()
        )
    }
}
#endif 