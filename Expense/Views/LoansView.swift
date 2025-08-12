import SwiftUI

struct LoansView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var loanManager = LoanManager.shared
    @StateObject private var currencySettings = CurrencySettings.shared
    
    @State private var showingAddLoan = false
    @State private var showingInterestCalculation = false
    @State private var selectedLoan: CDAccount?
    
    var loanAccounts: [CDAccount] {
        viewModel.getLoanAccounts()
    }
    
    var loansTaken: [CDAccount] {
        loanAccounts.filter { $0.accountType == AccountType.loan.rawValue }
    }
    
    var personalLoansGiven: [CDAccount] {
        loanAccounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }
    }
    
    var totalLoansTaken: Double {
        loansTaken.reduce(0) { $0 + $1.balance }
    }
    
    var totalPersonalLoansGiven: Double {
        personalLoansGiven.reduce(0) { $0 + $1.balance }
    }
    
    var totalInterestAccrued: Double {
        loanAccounts.reduce(0) { total, account in
            total + loanManager.calculateInterestForLoan(account)
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary Cards
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            LoanSummaryCard(
                                title: "Loans Taken",
                                value: totalLoansTaken,
                                icon: "arrow.down.circle.fill",
                                color: .red
                            )
                            
                            LoanSummaryCard(
                                title: "Loans Given",
                                value: totalPersonalLoansGiven,
                                icon: "arrow.up.circle.fill",
                                color: .green
                            )
                        }
                        
                        LoanSummaryCard(
                            title: "Interest Accrued",
                            value: totalInterestAccrued,
                            icon: "percent.circle.fill",
                            color: .orange
                        )
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: { showingAddLoan = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add New Loan")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button(action: { 
                            viewModel.calculateInterestForAllLoans()
                        }) {
                            HStack {
                                Image(systemName: "percent.circle.fill")
                                Text("Calculate All Interest")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    // Loans Taken Section
                    if !loansTaken.isEmpty {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Loans Taken")
                                    .font(.headline)
                                Spacer()
                                Text("\(loansTaken.count) loans")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            LazyVStack(spacing: 12) {
                                ForEach(loansTaken) { account in
                                    LoanCardView(
                                        account: account,
                                        loanManager: loanManager,
                                        onTap: {
                                            selectedLoan = account
                                        }
                                    )
                                }
                            }
                        }
                    }
                    
                    // Personal Loans Given Section
                    if !personalLoansGiven.isEmpty {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Personal Loans Given")
                                    .font(.headline)
                                Spacer()
                                Text("\(personalLoansGiven.count) loans")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            LazyVStack(spacing: 12) {
                                ForEach(personalLoansGiven) { account in
                                    LoanCardView(
                                        account: account,
                                        loanManager: loanManager,
                                        onTap: {
                                            selectedLoan = account
                                        }
                                    )
                                }
                            }
                        }
                    }
                    
                    if loanAccounts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "creditcard.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("No Loans Yet")
                                .font(.title2)
                                .fontWeight(.medium)
                            
                            Text("Add your first loan to start tracking interest and payments")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Add Loan") {
                                showingAddLoan = true
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.top, 50)
                    }
                }
                .padding()
            }
            .navigationTitle("Loans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddLoan = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddLoan) {
                AddLoanView(viewModel: viewModel)
            }
            .sheet(item: $selectedLoan) { account in
                LoanDetailsView(viewModel: viewModel, account: account)
            }
        }
    }
}

struct LoanSummaryCard: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(value, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct LoanCardView: View {
    let account: CDAccount
    let loanManager: LoanManager
    let onTap: () -> Void
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var loanDetails: LoanDetails? {
        loanManager.getLoanDetails(account)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.wrappedAccountName)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text(account.wrappedAccountType.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(account.balance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(account.wrappedAccountType.isAsset ? .green : .red)
                        
                        if let details = loanDetails, details.calculatedInterest > 0 {
                            Text("+\(details.calculatedInterest, format: .currency(code: currencySettings.selectedCurrency.rawValue)) interest")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                if let details = loanDetails {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Principal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(details.principalAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .center, spacing: 4) {
                            Text("Rate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(details.interestRate, specifier: "%.2f")%")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Calendar.current.dateComponents([.day], from: details.lastInterestCalculationDate, to: Date()).day ?? 0)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#if DEBUG
struct LoansView_Previews: PreviewProvider {
    static var previews: some View {
        LoansView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 