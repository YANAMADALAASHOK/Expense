import SwiftUI

struct LoanDetailsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var loanManager = LoanManager.shared
    @StateObject private var currencySettings = CurrencySettings.shared
    let account: CDAccount
    
    @State private var showingPaymentSheet = false
    @State private var showingEditSheet = false
    
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
                            
                            // Enhanced loan information display
                            if details.isEMILoan {
                                Divider()
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("EMI Amount")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(details.effectiveEMI, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 8) {
                                        Text("Payments Left")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(details.calculatedRemainingPayments)")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                    }
                                }
                                
                                Divider()
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Loan Progress")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(Int(details.loanProgress * 100))%")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 8) {
                                        Text("Tenure")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(details.calculatedMonthsElapsed)/\(details.loanTenure) months")
                                            .font(.headline)
                                    }
                                }
                                
                                // Progress bar
                                ProgressView(value: details.loanProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                    .scaleEffect(x: 1, y: 0.8)
                                    .padding(.vertical, 4)
                            }
                        
                        // Interest information
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Interest Paid")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(details.totalInterestAccumulated, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text(details.isEMILoan ? "Total with Interest" : "Next Interest")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(details.isEMILoan ? details.totalAmountWithInterest : details.calculatedInterest, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .font(.headline)
                                    .foregroundColor(details.isEMILoan ? (account.wrappedAccountType.isAsset ? .green : .red) : .orange)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
                
                // Action Buttons
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
                
                // Enhanced Loan Information
                if let details = loanDetails {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Loan Information")
                                .font(.headline)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            InfoRow(title: "Loan Start Date", value: details.loanDate.formatted(date: .abbreviated, time: .omitted))
                            InfoRow(title: "Original Tenure", value: "\(details.loanTenure) months")
                            InfoRow(title: "Months Elapsed", value: "\(details.calculatedMonthsElapsed) months")
                            InfoRow(title: "Interest Rate", value: String(format: "%.2f%% per annum", details.interestRate))
                            
                            // Next Interest Date (for all loans)
                            InfoRow(title: "Next Interest Date", value: "\(details.nextInterestGenerationDate.formatted(date: .abbreviated, time: .omitted)) (in \(details.daysUntilNextInterestGeneration) days)")
                            
                            if details.isEMILoan {
                                InfoRow(title: "Repayment Type", value: "EMI")
                                InfoRow(title: "Payments Remaining", value: "\(details.calculatedRemainingPayments)")
                                InfoRow(title: "Loan Progress", value: "\(Int(details.loanProgress * 100))% completed")
                                
                                if let emiAmount = details.emiAmount {
                                    InfoRow(title: "Monthly EMI", value: emiAmount.formatted(.currency(code: currencySettings.selectedCurrency.rawValue)))
                                }
                                
                                // Next EMI Payment Date
                                if let nextEMIDate = details.nextEMIPaymentDate {
                                    if let daysUntilEMI = details.daysUntilNextEMIPayment {
                                        InfoRow(title: "Next EMI Date", value: "\(nextEMIDate.formatted(date: .abbreviated, time: .omitted)) (in \(daysUntilEMI) days)")
                                    } else {
                                        InfoRow(title: "Next EMI Date", value: nextEMIDate.formatted(date: .abbreviated, time: .omitted))
                                    }
                                }
                                
                                if let emiDay = details.emiDayOfMonth {
                                    InfoRow(title: "EMI Debit Day", value: "Day \(emiDay) of month")
                                }
                            } else {
                                InfoRow(title: "Repayment Type", value: "Interest Only")
                                InfoRow(title: "Last Interest Generated", value: details.lastInterestGeneratedText)
                            }
                            
                            InfoRow(title: "Total Interest Paid", value: details.totalInterestAccumulated.formatted(.currency(code: currencySettings.selectedCurrency.rawValue)))
                            
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
                                LoanTransactionRowView(transaction: transaction)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Loan Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingEditSheet = true }) {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingPaymentSheet) {
            LoanPaymentView(viewModel: viewModel, preSelectedLoan: account)
        }
        .sheet(isPresented: $showingEditSheet) {
            AddLoanView(viewModel: viewModel, editingAccount: account)
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

struct LoanTransactionRowView: View {
    let transaction: CDTransaction
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.wrappedCategory)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(transaction.wrappedDate.formatted(date: .abbreviated, time: .shortened))
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
                            InfoRow(title: "Interest Day of Month", value: details.interestDayOfMonth.map { "Day \($0)" } ?? "Not set")
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