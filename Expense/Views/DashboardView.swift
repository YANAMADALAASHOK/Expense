import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var pendingBillsAmount: Double = 0
    @State private var upcomingInsuranceAmount: Double = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Summary Cards
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        SummaryCard(title: "Net Worth", value: {
                            let assets = viewModel.accounts.filter { $0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }
                            let liabilities = viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + abs($1.balance) }
                            return assets - liabilities
                        }(), icon: "scalemass.fill", color: .green)
                        SummaryCard(title: "Total Assets", value: viewModel.accounts.filter { $0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }, icon: "arrow.up.circle.fill", color: .blue)
                        SummaryCard(title: "Total Liabilities", value: viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + abs($1.balance) }, icon: "arrow.down.circle.fill", color: .red)
                        SummaryCard(title: "Pending Bills", value: pendingBillsAmount, icon: "creditcard.fill", color: .orange)
                        SummaryCard(title: "Next Insurance", value: upcomingInsuranceAmount, icon: "shield.fill", color: .purple)
                    }
                    .padding(.horizontal)
                    
                    // Recent Transactions
                    VStack(alignment: .leading) {
                        Text("Recent Transactions")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        if viewModel.recentTransactions.isEmpty {
                            ContentUnavailableView("No Transactions", systemImage: "tray.fill")
                                .padding()
                        } else {
                            ForEach(viewModel.recentTransactions.prefix(5)) { transaction in
                                TransactionRow(transaction: transaction)
                                    .padding(.horizontal)
                                    .background(Color.white.opacity(0.001)) // For tap gesture
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Dashboard")
            .onAppear {
                calculatePendingBills()
                calculateUpcomingInsurance()
            }
            .refreshable {
                calculatePendingBills()
                calculateUpcomingInsurance()
            }
        }
    }
    
    private func calculatePendingBills() {
        // Calculate total pending credit card bills
        let creditCardAccounts = viewModel.accounts.filter { $0.wrappedAccountType == .creditCard }
        var totalPending: Double = 0
        
        for account in creditCardAccounts {
            let metadata = account.metadataDictionary
            let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
            
            // Find the latest unpaid bill
            let dateFormatter = ISO8601DateFormatter()
            var latestStatementDate: Date?
            var latestBillAmount: Double = 0
            
            for key in billHistoryKeys {
                if let statementJsonString = metadata[key],
                   let statementJsonData = statementJsonString.data(using: .utf8),
                   let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String],
                   let statementDateString = statementData["statementDate"],
                   let statementDate = dateFormatter.date(from: statementDateString) {
                    
                    // Check if this is the latest statement and not manually paid
                    if (latestStatementDate == nil || statementDate > latestStatementDate!) &&
                       statementData["manuallyPaid"] != "true" {
                        latestStatementDate = statementDate
                        latestBillAmount = statementData["dueAmount"].flatMap { Double($0) } ?? 0.0
                    }
                }
            }
            
            // Only add if this is truly the latest bill (unpaid)
            if let latestDate = latestStatementDate {
                // Check if this is the most recent statement for this account
                let allDates = billHistoryKeys.compactMap { key -> Date? in
                    guard let statementJsonString = metadata[key],
                          let statementJsonData = statementJsonString.data(using: .utf8),
                          let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String],
                          let statementDateString = statementData["statementDate"] else { return nil }
                    return dateFormatter.date(from: statementDateString)
                }
                
                if let maxDate = allDates.max(), Calendar.current.isDate(latestDate, inSameDayAs: maxDate) {
                    totalPending += latestBillAmount
                }
            }
        }
        
        pendingBillsAmount = totalPending
        print("DEBUG: Dashboard - Calculated pending bills: ₹\(totalPending)")
    }
    
    private func calculateUpcomingInsurance() {
        // Use insurance policies from viewModel and calculate next month's premiums
        let policies = viewModel.insurancePolicies
        
        let calendar = Calendar.current
        let today = Date()
        let currentDay = calendar.component(.day, from: today)
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        
        var nextMonthTotal: Double = 0
        
        for policy in policies where policy.isActive {
            // Calculate next due date
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
            
            // Check if the next due date is within the next 30 days
            let dateComponents = DateComponents(year: targetYear, month: targetMonth, day: policy.dayOfMonth)
            if let nextDueDate = calendar.date(from: dateComponents) {
                let daysUntilDue = calendar.dateComponents([.day], from: today, to: nextDueDate).day ?? 0
                
                print("DEBUG: Dashboard - Policy: \(policy.name), Due in \(daysUntilDue) days, Amount: ₹\(policy.premiumAmount)")
                
                // Include if due within next 30 days
                if daysUntilDue >= 0 && daysUntilDue <= 30 {
                    nextMonthTotal += policy.premiumAmount
                    print("DEBUG: Dashboard - Added policy \(policy.name) to total")
                }
            }
        }
        
        upcomingInsuranceAmount = nextMonthTotal
        print("DEBUG: Dashboard - Insurance policies count: \(policies.count)")
        print("DEBUG: Dashboard - Calculated upcoming insurance: ₹\(nextMonthTotal)")
    }
}

struct SummaryCard: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(value, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
    }
} 