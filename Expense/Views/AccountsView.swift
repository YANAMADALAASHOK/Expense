import SwiftUI
import CoreData

struct AccountsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingAddAccount = false
    @State private var showingAddMutualFund = false
    @State private var showingAddPersonalLoan = false
    @State private var selectedAccount: CDAccount?
    @State private var isRefreshing = false
    @State private var selectedAccountType: AccountType?
    
    private var assetAccounts: [CDAccount] {
        viewModel.accounts.filter { $0.wrappedAccountType.isAsset }
    }
    
    private var bankAccounts: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.bankAccount.rawValue }
    }
    
    private var mutualFunds: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.mutualFund.rawValue }
    }
    
    private var liabilityAccounts: [CDAccount] {
        viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }
    }
    
    private var loans: [CDAccount] {
        liabilityAccounts.filter { $0.accountType == AccountType.loan.rawValue }
    }
    
    private var creditCards: [CDAccount] {
        liabilityAccounts.filter { $0.accountType == AccountType.creditCard.rawValue }
    }
    
    private var personalLoansGiven: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }
    }
    
    var body: some View {
        NavigationView {
            List {
                BalanceSummarySection(accounts: viewModel.accounts)
                
                Section("Assets") {
                    DisclosureGroup("Bank Accounts") {
                        ForEach(bankAccounts) { account in
                            AccountRow(account: account)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAccount = account
                                }
                        }
                    }
                    
                    DisclosureGroup("Mutual Funds") {
                        ForEach(mutualFunds) { account in
                            MutualFundRow(account: account)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAccount = account
                                }
                        }
                    }
                    
                    DisclosureGroup("Personal Loans Given") {
                        ForEach(personalLoansGiven) { account in
                            AccountRow(account: account)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAccount = account
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.deleteAccount(account)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        selectedAccount = account
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
                
                Section("Liabilities") {
                    DisclosureGroup("Credit Cards") {
                        ForEach(creditCards) { account in
                            AccountRow(account: account)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAccount = account
                                }
                        }
                    }
                    
                    DisclosureGroup("Loans") {
                        ForEach(loans) { account in
                            AccountRow(account: account)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAccount = account
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.deleteAccount(account)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        recordLoanInterest(for: account)
                                    } label: {
                                        Label("Add Interest", systemImage: "percent")
                                    }
                                    .tint(.orange)
                                    
                                    Button {
                                        selectedAccount = account
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AddAccountMenu(
                        showingAddAccount: $showingAddAccount,
                        showingAddMutualFund: $showingAddMutualFund,
                        showingAddPersonalLoan: $showingAddPersonalLoan
                    )
                }
            }
            .refreshable {
                await refreshData()
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAddMutualFund) {
                AddMutualFundView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAddPersonalLoan) {
                AddPersonalLoanGivenView(viewModel: viewModel)
            }
            .sheet(item: $selectedAccount) { account in
                if account.accountType == AccountType.personalLoanGiven.rawValue {
                    EditPersonalLoanGivenView(viewModel: viewModel, account: account)
                } else {
                    EditAccountView(viewModel: viewModel, account: account)
                }
            }
        }
    }
    
    private func refreshData() {
        isRefreshing = true
        viewModel.refreshData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRefreshing = false
        }
    }
    
    private func recordLoanInterest(for account: CDAccount) {
        guard let metadata = account.metadata,
              let rateString = metadata["interestRate"],
              let rate = Double(rateString) else {
            return
        }
        
        // Calculate interest based on current balance
        let balance = account.balance
        let monthlyRate = rate / 12.0 / 100.0  // Convert annual rate to monthly decimal
        let interest = balance * monthlyRate
        
        // Add interest transaction
        viewModel.addTransaction(
            amount: interest,
            category: .interest,
            isCredit: false,  // Debit because it increases the loan amount
            account: account,
            notes: "Monthly Interest @ \(rate)% per annum",
            date: Date()
        )
    }
}

// MARK: - Supporting Views
private struct BalanceSummarySection: View {
    let accounts: [CDAccount]
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingBalanceBreakdown = false
    @State private var showingLiabilityBreakdown = false
    
    var bankBalance: Double {
        accounts.filter { $0.accountType == AccountType.bankAccount.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var investmentBalance: Double {
        accounts.filter { $0.accountType == AccountType.mutualFund.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var totalInvestment: Double {
        accounts.filter { $0.accountType == AccountType.mutualFund.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var investmentReturns: Double {
        let returns = investmentBalance - totalInvestment
        return returns
    }
    
    var personalLoansGivenBalance: Double {
        accounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var personalLoansPrincipal: Double {
        accounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var personalLoansInterest: Double {
        personalLoansGivenBalance - personalLoansPrincipal
    }
    
    var totalBalance: Double {
        accounts.filter { $0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }
    }
    
    var totalLiabilities: Double {
        accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }
    }
    
    var creditCardBalance: Double {
        accounts.filter { $0.accountType == AccountType.creditCard.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var loanBalance: Double {
        accounts.filter { $0.accountType == AccountType.loan.rawValue }.reduce(0) { $0 + $1.balance }
    }
    
    var totalLoanAmount: Double {
        accounts.filter { $0.accountType == AccountType.loan.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var totalCreditLimit: Double {
        accounts.filter { $0.accountType == AccountType.creditCard.rawValue }.reduce(0) { $0 + $1.creditLimit }
    }
    
    var netWorth: Double { totalBalance - totalLiabilities }
    
    var body: some View {
        Section {
            Button(action: { showingBalanceBreakdown.toggle() }) {
                SummaryRow(title: "Total Balance", amount: totalBalance, color: .green)
            }
            
            if showingBalanceBreakdown {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("Available Balance:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Bank Accounts")
                                .padding(.leading)
                            Spacer()
                            Text(bankBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                    }
                    
                    Group {
                        Text("Investments:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Total Investment")
                                .padding(.leading)
                            Spacer()
                            Text(totalInvestment, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Current Value")
                                .padding(.leading)
                            Spacer()
                            Text(investmentBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Returns")
                                .padding(.leading)
                            Spacer()
                            Text(investmentReturns, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(investmentReturns >= 0 ? .green : .red)
                        }
                        .font(.caption)
                    }
                    
                    Group {
                        Text("Personal Loans Given:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Total Principal")
                                .padding(.leading)
                            Spacer()
                            Text(personalLoansPrincipal, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Interest Earned")
                                .padding(.leading)
                            Spacer()
                            Text(personalLoansInterest, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Total Amount")
                                .padding(.leading)
                            Spacer()
                            Text(personalLoansGivenBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Button(action: { showingLiabilityBreakdown.toggle() }) {
                SummaryRow(title: "Total Liabilities", amount: totalLiabilities, color: .red)
            }
            
            if showingLiabilityBreakdown {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("Credit Cards:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Outstanding Balance")
                                .padding(.leading)
                            Spacer()
                            Text(creditCardBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Total Credit Limit")
                                .padding(.leading)
                            Spacer()
                            Text(totalCreditLimit, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                    
                    Group {
                        Text("Loans:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Total Loan Amount")
                                .padding(.leading)
                            Spacer()
                            Text(totalLoanAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Outstanding Amount")
                                .padding(.leading)
                            Spacer()
                            Text(loanBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Repaid Amount")
                                .padding(.leading)
                            Spacer()
                            Text(totalLoanAmount - loanBalance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }
            
            SummaryRow(title: "Net Worth", amount: netWorth, color: netWorth >= 0 ? .green : .red)
        }
    }
}

private struct SummaryRow: View {
    @StateObject private var currencySettings = CurrencySettings.shared
    let title: String
    let amount: Double
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                .foregroundColor(color)
        }
    }
}

private struct AddAccountMenu: View {
    @Binding var showingAddAccount: Bool
    @Binding var showingAddMutualFund: Bool
    @Binding var showingAddPersonalLoan: Bool
    @State private var selectedAccountType: AccountType?
    
    var body: some View {
        Menu {
            Menu("Add Account") {
                Button(action: { 
                    selectedAccountType = .bankAccount
                    showingAddAccount = true 
                }) {
                    Label("Bank Account", systemImage: "banknote")
                }
                
                Button(action: { 
                    selectedAccountType = .creditCard
                    showingAddAccount = true 
                }) {
                    Label("Credit Card", systemImage: "creditcard")
                }
                
                Button(action: { 
                    selectedAccountType = .loan
                    showingAddAccount = true 
                }) {
                    Label("Loan", systemImage: "indianrupeesign")
                }
            }
            
            Button(action: { showingAddMutualFund = true }) {
                Label("Add Mutual Fund", systemImage: "chart.line.uptrend.xyaxis")
            }
            
            Button(action: { 
                selectedAccountType = .personalLoanGiven
                showingAddPersonalLoan = true 
            }) {
                Label("Personal Loan Given", systemImage: "person.text.rectangle")
            }
        } label: {
            Image(systemName: "plus")
        }
    }
}

#if DEBUG
struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 