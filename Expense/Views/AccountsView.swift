import SwiftUI
import CoreData

struct AccountsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingAddAccount = false
    @State private var showingAddMutualFund = false
    @State private var showingAddPersonalLoan = false
    @State private var showingLoanPayment = false
    @State private var showingAccountTransactions = false
    @State private var selectedAccount: CDAccount?
    @State private var selectedAccountForTransactions: CDAccount?
    @State private var isRefreshing = false
    @State private var selectedAccountType: AccountType?
    @State private var isUpdatingNAVs = false
    @State private var showingAddInsurance = false
    @State private var editingInsurance: InsurancePolicy?
    @State private var insurancePolicies: [InsurancePolicy] = []
    
    private var assetAccounts: [CDAccount] {
        viewModel.accounts.filter { $0.wrappedAccountType.isAsset }
    }
    
    private var bankAccounts: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.bankAccount.rawValue }
    }
    private var bankAccountsTotal: Double { bankAccounts.reduce(0) { $0 + $1.balance } }
    
    private var mutualFunds: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.mutualFund.rawValue }
    }
    private var mutualFundsTotal: Double { mutualFunds.reduce(0) { $0 + $1.balance } }
    
    private var liabilityAccounts: [CDAccount] {
        viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }
    }
    
    private var loans: [CDAccount] {
        liabilityAccounts.filter { $0.accountType == AccountType.loan.rawValue }
    }
    private var loansOutstanding: Double { loans.reduce(0) { $0 + $1.balance } }
    
    private var creditCards: [CDAccount] {
        liabilityAccounts.filter { $0.accountType == AccountType.creditCard.rawValue }
    }
    private var creditCardsOutstanding: Double { creditCards.reduce(0) { $0 + $1.balance } }
    
    private var personalLoansGiven: [CDAccount] {
        assetAccounts.filter { $0.accountType == AccountType.personalLoanGiven.rawValue }
    }
    private var personalLoansOutstanding: Double { personalLoansGiven.reduce(0) { $0 + $1.balance } }
    
    var body: some View {
        NavigationView {
            List {
                Section { BalanceSummarySection(accounts: viewModel.accounts) }
                assetsSection
                liabilitiesSection
                insurancesSection
            }
            .background(Color(.systemGroupedBackground))
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
            .onAppear {
                loadInsurancePolicies()
                processInsurancePremiums()
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(viewModel: viewModel)
                    .onDisappear {
                        selectedAccountType = nil
                    }
            }
            .sheet(isPresented: $showingAddMutualFund) {
                AddMutualFundView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAddPersonalLoan) {
                AddPersonalLoanGivenView(viewModel: viewModel)
                    .onDisappear {
                        selectedAccountType = nil
                    }
            }
            .sheet(item: $selectedAccount) { account in
                if account.accountType == AccountType.personalLoanGiven.rawValue {
                    EditPersonalLoanGivenView(viewModel: viewModel, account: account)
                } else {
                    EditAccountView(viewModel: viewModel, account: account)
                }
            }
            .sheet(isPresented: $showingLoanPayment) {
                LoanPaymentView(viewModel: viewModel, preSelectedLoan: selectedAccount)
            }
            .sheet(isPresented: $showingAccountTransactions) {
                if let account = selectedAccountForTransactions {
                    AccountTransactionsView(viewModel: viewModel, account: account)
                }
            }
            .sheet(isPresented: $showingAddInsurance) {
                AddInsurancePolicyView(
                    accounts: viewModel.accounts,
                    initial: nil,
                    onSave: addInsurancePolicy,
                    onDelete: nil
                )
            }
            .sheet(item: $editingInsurance) { policy in
                AddInsurancePolicyView(
                    accounts: viewModel.accounts,
                    initial: policy,
                    onSave: updateInsurancePolicy,
                    onDelete: deleteInsurancePolicy
                )
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
        let metadata = account.metadataDictionary
        guard let rateString = metadata["interestRate"],
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
extension AccountsView {
    @ViewBuilder
    private var assetsSection: some View {
        Section("Assets") {
            bankAccountsGroup
            mutualFundsGroup
            personalLoansGroup
        }
    }
    
    @ViewBuilder
    private var bankAccountsGroup: some View {
        DisclosureGroup {
            ForEach(bankAccounts) { account in
                AccountRow(account: account)
                    .onTapGesture { openTransactions(for: account) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { openTransactions(for: account) } label: { Label("Transactions", systemImage: "list.bullet") }
                            .tint(.blue)
                        Button { editAccount(account) } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.orange)
                        Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        } label: {
            HStack {
                Text("Bank Accounts")
                Spacer()
                Text(bankAccountsTotal, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var mutualFundsGroup: some View {
        DisclosureGroup {
            ForEach(mutualFunds) { account in
                MutualFundRow(account: account)
                    .onTapGesture { editAccount(account) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { openTransactions(for: account) } label: { Label("Transactions", systemImage: "list.bullet") }.tint(.blue)
                        Button { editAccount(account) } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                        Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        } label: {
            HStack {
                Text("Mutual Funds")
                Spacer()
                Text(mutualFundsTotal, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var personalLoansGroup: some View {
        DisclosureGroup {
            ForEach(personalLoansGiven) { account in
                NavigationLink(destination: LoanDetailsView(viewModel: viewModel, account: account)) {
                    AccountRow(account: account)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { selectedAccount = account } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                    Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } label: {
            HStack {
                Text("Personal Loans Given")
                Spacer()
                Text(personalLoansOutstanding, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var liabilitiesSection: some View {
        Section("Liabilities") {
            creditCardsGroup
            loansGroup
        }
    }
    @ViewBuilder
    private var creditCardsGroup: some View {
        DisclosureGroup {
            ForEach(creditCards) { account in
                AccountRow(account: account)
                    .onTapGesture { openTransactions(for: account) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { openTransactions(for: account) } label: { Label("Transactions", systemImage: "list.bullet") }.tint(.blue)
                        Button { selectedAccount = account } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                        Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        } label: {
            HStack {
                Text("Credit Cards")
                Spacer()
                Text(creditCardsOutstanding, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    @ViewBuilder
    private var loansGroup: some View {
        DisclosureGroup {
            ForEach(loans) { account in
                NavigationLink(destination: LoanDetailsView(viewModel: viewModel, account: account)) {
                    AccountRow(account: account)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { selectedAccount = account; showingLoanPayment = true } label: { Label("Pay Loan", systemImage: "indianrupeesign.circle") }.tint(.green)
                    Button(role: .destructive) { viewModel.deleteAccount(account) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } label: {
            HStack {
                Text("Loans")
                Spacer()
                Text(loansOutstanding, format: .currency(code: currencySettings.selectedCurrency.rawValue)).foregroundColor(.secondary)
            }
        }
    }
    
    // Small helpers to keep closures simple
    private func openTransactions(for account: CDAccount) {
        selectedAccount = nil
        showingAddAccount = false
        showingAddMutualFund = false
        showingAddPersonalLoan = false
        showingLoanPayment = false
        selectedAccountForTransactions = account
        DispatchQueue.main.async { showingAccountTransactions = true }
    }
    private func editAccount(_ account: CDAccount) {
        selectedAccountForTransactions = nil
        showingAccountTransactions = false
        selectedAccount = account
    }
    
    // Insurance management methods
    private func loadInsurancePolicies() {
        let insuranceManager = InsuranceManager.shared
        insurancePolicies = insuranceManager.loadPolicies()
    }
    
    private func processInsurancePremiums() {
        let insuranceManager = InsuranceManager.shared
        insuranceManager.processInsurancePremiums(context: viewModel.viewContext, accounts: viewModel.accounts)
    }
    
    private func addInsurancePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.append(policy)
        saveInsurancePolicies()
    }
    
    private func updateInsurancePolicy(_ policy: InsurancePolicy) {
        if let index = insurancePolicies.firstIndex(where: { $0.id == policy.id }) {
            insurancePolicies[index] = policy
            saveInsurancePolicies()
        }
    }
    
    private func deleteInsurancePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.removeAll { $0.id == policy.id }
        saveInsurancePolicies()
        
        // Clean up the last processed date
        let lastProcessedKey = "insurance_\(policy.id)_lastProcessed"
        UserDefaults.standard.removeObject(forKey: lastProcessedKey)
    }
    
    private func saveInsurancePolicies() {
        let insuranceManager = InsuranceManager.shared
        insuranceManager.savePolicies(insurancePolicies)
    }
    
    @ViewBuilder
    private var insurancesSection: some View {
        Section("Insurance Policies") {
            if insurancePolicies.isEmpty {
                Text("No insurance policies added yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(insurancePolicies) { policy in
                    InsurancePolicyRowView(
                        policy: policy,
                        accounts: viewModel.accounts
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingInsurance = policy }
                    .swipeActions(edge: .trailing) {
                        Button("Edit") { editingInsurance = policy }
                            .tint(.orange)
                        Button("Delete", role: .destructive) { deleteInsurancePolicy(policy) }
                    }
                }
            }
            
            Button {
                showingAddInsurance = true
            } label: {
                Label("Add Insurance Policy", systemImage: "plus")
            }
        }
    }
    
}

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
                    DispatchQueue.main.async {
                        showingAddAccount = true 
                    }
                }) {
                    Label("Bank Account", systemImage: "banknote")
                }
                
                Button(action: { 
                    selectedAccountType = .creditCard
                    DispatchQueue.main.async {
                        showingAddAccount = true 
                    }
                }) {
                    Label("Credit Card", systemImage: "creditcard")
                }
                
                Button(action: { 
                    selectedAccountType = .loan
                    DispatchQueue.main.async {
                        showingAddAccount = true 
                    }
                }) {
                    Label("Loan", systemImage: "indianrupeesign")
                }
            }
            
            Button(action: { 
                DispatchQueue.main.async {
                    showingAddMutualFund = true 
                }
            }) {
                Label("Add Mutual Fund", systemImage: "chart.line.uptrend.xyaxis")
            }
            
            Button(action: { 
                selectedAccountType = .personalLoanGiven
                DispatchQueue.main.async {
                    showingAddPersonalLoan = true 
                }
            }) {
                Label("Personal Loan Given", systemImage: "person.text.rectangle")
            }
        } label: {
            Image(systemName: "plus")
        }
    }
}

// Simple insurance policy row for AccountsView
private struct InsurancePolicyRowView: View {
    let policy: InsurancePolicy
    let accounts: [CDAccount]
    @StateObject private var currencySettings = CurrencySettings.shared
    
    private var accountName: String {
        accounts.first(where: { $0.id == policy.accountId })?.wrappedAccountName ?? "Unknown Account"
    }
    
    private var nextDueDate: String {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.day, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        var targetMonth = currentMonth
        var targetYear = currentYear
        
        // If we've passed this month's due date, show next month
        if currentDay > policy.dayOfMonth {
            targetMonth += 1
            if targetMonth > 12 {
                targetMonth = 1
                targetYear += 1
            }
        }
        
        let dateComponents = DateComponents(year: targetYear, month: targetMonth, day: policy.dayOfMonth)
        if let nextDate = calendar.date(from: dateComponents) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: nextDate)
        }
        
        return "Day \(policy.dayOfMonth)"
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(policy.name)
                    .font(.headline)
                Text("Next due: \(nextDueDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !policy.isActive {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(policy.premiumAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(.headline)
                    .foregroundColor(.red)
                Text(accountName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 