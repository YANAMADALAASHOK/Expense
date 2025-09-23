import SwiftUI
import Charts

// MARK: - Enhanced Dashboard View
struct EnhancedDashboardView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var selectedTimeRange: TimeRange = .month
    @State private var showingInsights = false
    @State private var pendingBillsAmount: Double = 0
    @State private var upcomingInsuranceAmount: Double = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header with Net Worth
                    NetWorthCard(viewModel: viewModel, currencySettings: currencySettings)
                    
                    // Time Range Selector
                    TimeRangeSelector(selectedRange: $selectedTimeRange)
                    
            // Summary Cards (respect dashboard exclusions)
            SummaryCardsGrid(viewModel: viewModel, timeRange: selectedTimeRange)
                    
                    // Spending Chart
                    SpendingChartView(transactions: viewModel.dashboardTransactions, timeRange: selectedTimeRange)
                    
                    // Upcoming Bills Section
                    UpcomingBillsSection(
                        pendingBillsAmount: pendingBillsAmount,
                        upcomingInsuranceAmount: upcomingInsuranceAmount,
                        currencySettings: currencySettings,
                        viewModel: viewModel
                    )
                    
                    // Recent Transactions
                    RecentTransactionsSection(transactions: viewModel.dashboardTransactions, viewModel: viewModel)
                    
                    // Insights Button
                    InsightsButton(showingInsights: $showingInsights)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.md)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                calculatePendingBills()
                calculateUpcomingInsurance()
            }
            .refreshable {
                calculatePendingBills()
                calculateUpcomingInsurance()
            }
            .sheet(isPresented: $showingInsights) {
                FinancialInsightsView(viewModel: viewModel)
            }
        }
    }
    
    private func calculatePendingBills() {
        // Calculate total pending credit card bills
        let creditCardAccounts = viewModel.accounts.filter { $0.wrappedAccountType == .creditCard }
        var totalPending: Double = 0
        
        print("DEBUG: Dashboard - Starting bill calculation for \(creditCardAccounts.count) credit card accounts")
        
        for account in creditCardAccounts {
            let metadata = account.metadataDictionary
            let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
            
            print("DEBUG: Dashboard - Account: \(account.wrappedAccountName), Bills found: \(billHistoryKeys.count)")
            
            // Find the latest unpaid bill
            let dateFormatter = ISO8601DateFormatter()
            var latestStatementDate: Date?
            var latestBillAmount: Double = 0
            var latestBillKey: String?
            
            for key in billHistoryKeys {
                if let statementJsonString = metadata[key],
                   let statementJsonData = statementJsonString.data(using: .utf8),
                   let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String],
                   let statementDateString = statementData["statementDate"],
                   let statementDate = dateFormatter.date(from: statementDateString) {
                    
                    let dueAmount = statementData["dueAmount"].flatMap { Double($0) } ?? 0.0
                    let isManuallyPaid = statementData["manuallyPaid"] == "true"
                    
                    print("DEBUG: Dashboard - Bill: \(statementDate), Amount: ₹\(dueAmount), Manually Paid: \(isManuallyPaid)")
                    
                    // Check if this is the latest statement and not manually paid
                    if (latestStatementDate == nil || statementDate > latestStatementDate!) &&
                       !isManuallyPaid {
                        latestStatementDate = statementDate
                        latestBillAmount = dueAmount
                        latestBillKey = key
                        print("DEBUG: Dashboard - Updated latest unpaid bill: ₹\(dueAmount)")
                    }
                }
            }
            
            // Only add if this is truly the latest bill (unpaid)
            if let latestDate = latestStatementDate, let latestKey = latestBillKey {
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
                    print("DEBUG: Dashboard - Added to total: ₹\(latestBillAmount) for account \(account.wrappedAccountName)")
                } else {
                    print("DEBUG: Dashboard - Skipped (not latest): ₹\(latestBillAmount) for account \(account.wrappedAccountName)")
                }
            } else {
                print("DEBUG: Dashboard - No unpaid bills found for account \(account.wrappedAccountName)")
            }
        }
        
        pendingBillsAmount = totalPending
        print("DEBUG: Dashboard - Final calculated pending bills: ₹\(totalPending)")
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

// MARK: - Net Worth Card
struct NetWorthCard: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @ObservedObject var currencySettings: CurrencySettings
    
    var netWorth: Double {
        viewModel.accounts.reduce(0) { $0 + ($1.wrappedAccountType.isAsset ? $1.balance : -$1.balance) }
    }
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Net Worth")
                        .font(DesignSystem.Typography.labelLarge)
                        .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                    
                    Text(netWorth, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        .font(DesignSystem.Typography.displaySmall)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.onSurface)
                }
                
                Spacer()
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 40))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            
            // Assets vs Liabilities breakdown
            HStack(spacing: DesignSystem.Spacing.lg) {
                AssetLiabilityItem(
                    title: "Assets",
                    amount: viewModel.accounts.filter { $0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance },
                    color: DesignSystem.Colors.success,
                    currencySettings: currencySettings
                )
                
                AssetLiabilityItem(
                    title: "Liabilities",
                    amount: viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance },
                    color: DesignSystem.Colors.error,
                    currencySettings: currencySettings
                )
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .cardStyle()
    }
}

// MARK: - Asset/Liability Item
struct AssetLiabilityItem: View {
    let title: String
    let amount: Double
    let color: Color
    @ObservedObject var currencySettings: CurrencySettings
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.labelMedium)
                .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
            
            Text(amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                .font(DesignSystem.Typography.titleMedium)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Time Range Selector
struct TimeRangeSelector: View {
    @Binding var selectedRange: TimeRange
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: { selectedRange = range }) {
                    Text(range.displayName)
                        .font(DesignSystem.Typography.labelMedium)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(selectedRange == range ? DesignSystem.Colors.primary : DesignSystem.Colors.surfaceVariant)
                        .foregroundColor(selectedRange == range ? DesignSystem.Colors.onPrimary : DesignSystem.Colors.onSurfaceVariant)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                }
            }
        }
    }
}

// MARK: - Summary Cards Grid
struct SummaryCardsGrid: View {
    @ObservedObject var viewModel: ExpenseViewModel
    let timeRange: TimeRange
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.Spacing.md) {
            EnhancedSummaryCard(
                title: "Income",
                value: calculateIncome(for: timeRange),
                icon: "arrow.up.circle.fill",
                color: DesignSystem.Colors.success,
                currencySettings: currencySettings
            )
            
            EnhancedSummaryCard(
                title: "Expenses",
                value: calculateExpenses(for: timeRange),
                icon: "arrow.down.circle.fill",
                color: DesignSystem.Colors.error,
                currencySettings: currencySettings
            )
            
            EnhancedSummaryCard(
                title: "Savings",
                value: calculateSavings(for: timeRange),
                icon: "banknote.fill",
                color: DesignSystem.Colors.info,
                currencySettings: currencySettings
            )
            
            EnhancedSummaryCard(
                title: "Transactions",
                value: Double(calculateTransactionCount(for: timeRange)),
                icon: "list.bullet",
                color: DesignSystem.Colors.warning,
                currencySettings: currencySettings,
                isCurrency: false
            )
        }
    }
    
    private func calculateIncome(for timeRange: TimeRange) -> Double {
        let filteredTransactions = filterTransactionsByTimeRange(viewModel.dashboardTransactions, timeRange: timeRange)
        return filteredTransactions
            .filter { $0.isCredit && isIncomeCategory($0) }
            .reduce(0) { $0 + $1.amount }
    }
    
    private func calculateExpenses(for timeRange: TimeRange) -> Double {
        let filteredTransactions = filterTransactionsByTimeRange(viewModel.dashboardTransactions, timeRange: timeRange)
        return filteredTransactions.filter { !$0.isCredit }.reduce(0) { $0 + $1.amount }
    }
    
    private func calculateSavings(for timeRange: TimeRange) -> Double {
        return calculateIncome(for: timeRange) - calculateExpenses(for: timeRange)
    }
    
    private func calculateTransactionCount(for timeRange: TimeRange) -> Int {
        return filterTransactionsByTimeRange(viewModel.dashboardTransactions, timeRange: timeRange).count
    }
    
    private func filterTransactionsByTimeRange(_ transactions: [CDTransaction], timeRange: TimeRange) -> [CDTransaction] {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeRange {
        case .week:
            let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return transactions.filter { $0.date ?? now >= weekAgo }
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return transactions.filter { $0.date ?? now >= monthAgo }
        case .year:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return transactions.filter { $0.date ?? now >= yearAgo }
        }
    }

    private func isIncomeCategory(_ transaction: CDTransaction) -> Bool {
        // Only treat explicit Salary (or categories containing the word "Income") as income
        let cat = transaction.wrappedCategory
        if cat == TransactionCategory.salary.rawValue { return true }
        if cat.localizedCaseInsensitiveContains("income") { return true }
        return false
    }
}

// MARK: - Enhanced Summary Card
struct EnhancedSummaryCard: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color
    @ObservedObject var currencySettings: CurrencySettings
    var isCurrency: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(title)
                .font(DesignSystem.Typography.labelMedium)
                .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
            
            if isCurrency {
                Text(value, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(DesignSystem.Typography.titleLarge)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Text("\(Int(value))")
                    .font(DesignSystem.Typography.titleLarge)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.onSurface)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Spending Chart View
struct SpendingChartView: View {
    let transactions: [CDTransaction]
    let timeRange: TimeRange
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Spending Trend")
                .font(DesignSystem.Typography.titleMedium)
                .foregroundColor(DesignSystem.Colors.onSurface)
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(chartData, id: \.date) { dataPoint in
                        LineMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Amount", dataPoint.amount)
                        )
                        .foregroundStyle(DesignSystem.Colors.primary)
                        .interpolationMethod(.catmullRom)
                        
                        AreaMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Amount", dataPoint.amount)
                        )
                        .foregroundStyle(DesignSystem.Colors.primary.opacity(0.1))
                    }
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .font(DesignSystem.Typography.labelSmall)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month().day())
                                    .font(DesignSystem.Typography.labelSmall)
                            }
                        }
                    }
                }
            } else {
                // Fallback for older iOS versions
                Text("Charts available in iOS 16+")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(DesignSystem.Colors.surfaceVariant)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }
    
    private var chartData: [ChartDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        var dataPoints: [ChartDataPoint] = []
        
        let numberOfPoints: Int
        switch timeRange {
        case .week: numberOfPoints = 7
        case .month: numberOfPoints = 30
        case .year: numberOfPoints = 12
        }
        
        for i in 0..<numberOfPoints {
            let date: Date
            switch timeRange {
            case .week:
                date = calendar.date(byAdding: .day, value: -i, to: now) ?? now
            case .month:
                date = calendar.date(byAdding: .day, value: -i, to: now) ?? now
            case .year:
                date = calendar.date(byAdding: .month, value: -i, to: now) ?? now
            }
            
            let dayTransactions = transactions.filter { transaction in
                guard let transactionDate = transaction.date else { return false }
                return calendar.isDate(transactionDate, inSameDayAs: date) && !transaction.isCredit
            }
            
            let totalAmount = dayTransactions.reduce(0) { $0 + $1.amount }
            dataPoints.append(ChartDataPoint(date: date, amount: totalAmount))
        }
        
        return dataPoints.reversed()
    }
}

// MARK: - Category Breakdown View
struct CategoryBreakdownView: View {
    let transactions: [CDTransaction]
    let timeRange: TimeRange
    let onCategoryTap: (String) -> Void
    @StateObject private var currencySettings = CurrencySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Spending by Category")
                .font(DesignSystem.Typography.titleMedium)
                .foregroundColor(DesignSystem.Colors.onSurface)
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(categoryData, id: \.category) { dataPoint in
                        SectorMark(
                            angle: .value("Amount", dataPoint.amount),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Category", dataPoint.category))
                    }
                }
                .frame(height: 200)
                .chartLegend(position: .bottom, alignment: .center)

                // Tappable list below chart
                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(categoryData, id: \.category) { dataPoint in
                        HStack {
                            Text(dataPoint.category)
                                .font(DesignSystem.Typography.bodyMedium)
                            Spacer()
                            Text(dataPoint.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .font(DesignSystem.Typography.bodyMedium)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { onCategoryTap(dataPoint.category) }
                    }
                }
            } else {
                // Fallback for older iOS versions
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(categoryData.prefix(5), id: \.category) { dataPoint in
                        HStack {
                            Circle()
                                .fill(DesignSystem.Colors.chartColors[categoryData.firstIndex(of: dataPoint) ?? 0])
                                .frame(width: 12, height: 12)
                            
                            Text(dataPoint.category)
                                .font(DesignSystem.Typography.bodyMedium)
                            
                            Spacer()
                            
                            Text(dataPoint.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onCategoryTap(dataPoint.category) }
                    }
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surfaceVariant)
                .cornerRadius(DesignSystem.CornerRadius.md)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }
    
    private var categoryData: [CategoryDataPoint] {
        // Filter by selected time range and include only expenses
        let filtered = filterTransactionsByTimeRange(transactions, timeRange: timeRange)
        let expenseTransactions = filtered.filter { !$0.isCredit }
        let grouped = Dictionary(grouping: expenseTransactions) { $0.category ?? "Uncategorized" }
        
        return grouped.map { category, transactions in
            CategoryDataPoint(
                category: category,
                amount: transactions.reduce(0) { $0 + $1.amount }
            )
        }.sorted { $0.amount > $1.amount }
    }

    private func filterTransactionsByTimeRange(_ transactions: [CDTransaction], timeRange: TimeRange) -> [CDTransaction] {
        let calendar = Calendar.current
        let now = Date()
        switch timeRange {
        case .week:
            let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return transactions.filter { ($0.date ?? now) >= weekAgo }
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return transactions.filter { ($0.date ?? now) >= monthAgo }
        case .year:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return transactions.filter { ($0.date ?? now) >= yearAgo }
        }
    }
}

// MARK: - Recent Transactions Section
struct RecentTransactionsSection: View {
    let transactions: [CDTransaction]
    let viewModel: ExpenseViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Recent Transactions")
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Spacer()
                
                NavigationLink("View All") {
                    TransactionView(viewModel: viewModel)
                }
                .font(DesignSystem.Typography.labelMedium)
                .foregroundColor(DesignSystem.Colors.primary)
            }
            
            if transactions.isEmpty {
                ContentUnavailableView("No Transactions", systemImage: "tray.fill")
                    .padding()
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(Array(transactions.prefix(5))) { transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(DesignSystem.Colors.surfaceVariant)
                            .cornerRadius(DesignSystem.CornerRadius.sm)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Insights Button
struct InsightsButton: View {
    @Binding var showingInsights: Bool
    
    var body: some View {
        Button(action: { showingInsights = true }) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(DesignSystem.Colors.warning)
                
                Text("View Financial Insights")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.labelMedium)
                    .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
            }
            .padding(DesignSystem.Spacing.md)
            .cardStyle()
        }
    }
}

// MARK: - Supporting Models
enum TimeRange: CaseIterable {
    case week
    case month
    case year
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

struct ChartDataPoint {
    let date: Date
    let amount: Double
}

struct CategoryDataPoint: Equatable {
    let category: String
    let amount: Double
}

// MARK: - Financial Insights View
struct FinancialInsightsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Spending Insights
                    InsightCard(
                        title: "Spending Insights",
                        insights: generateSpendingInsights(),
                        icon: "chart.pie.fill",
                        color: DesignSystem.Colors.primary
                    )
                    
                    // Savings Insights
                    InsightCard(
                        title: "Savings Insights",
                        insights: generateSavingsInsights(),
                        icon: "banknote.fill",
                        color: DesignSystem.Colors.success
                    )
                    
                    // Budget Insights
                    InsightCard(
                        title: "Budget Insights",
                        insights: generateBudgetInsights(),
                        icon: "target",
                        color: DesignSystem.Colors.warning
                    )
                }
                .padding(DesignSystem.Spacing.md)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Financial Insights")
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
    
    private func generateSpendingInsights() -> [String] {
        let expenses = viewModel.recentTransactions.filter { !$0.isCredit }
        let totalExpenses = expenses.reduce(0) { $0 + $1.amount }
        
        var insights: [String] = []
        
        if totalExpenses > 0 {
            let topCategory = Dictionary(grouping: expenses) { $0.category }
                .max(by: { $0.value.reduce(0) { $0 + $1.amount } < $1.value.reduce(0) { $0 + $1.amount } })
            
            if let topCategory = topCategory {
                let categoryTotal = topCategory.value.reduce(0) { $0 + $1.amount }
                let percentage = (categoryTotal / totalExpenses) * 100
                insights.append("Your biggest expense category is \(topCategory.key) at \(String(format: "%.1f", percentage))%")
            }
            
            let averageExpense = totalExpenses / Double(expenses.count)
            insights.append("Average transaction amount: \(String(format: "%.2f", averageExpense))")
        }
        
        return insights
    }
    
    private func generateSavingsInsights() -> [String] {
        let income = viewModel.recentTransactions.filter { $0.isCredit }.reduce(0) { $0 + $1.amount }
        let expenses = viewModel.recentTransactions.filter { !$0.isCredit }.reduce(0) { $0 + $1.amount }
        let savings = income - expenses
        
        var insights: [String] = []
        
        if income > 0 {
            let savingsRate = (savings / income) * 100
            insights.append("Your savings rate is \(String(format: "%.1f", savingsRate))%")
            
            if savingsRate >= 20 {
                insights.append("Great job! You're saving more than the recommended 20%")
            } else if savingsRate >= 10 {
                insights.append("Good progress! Consider increasing your savings rate")
            } else {
                insights.append("Consider reducing expenses to increase your savings rate")
            }
        }
        
        return insights
    }
    
    private func generateBudgetInsights() -> [String] {
        var insights: [String] = []
        
        // Add budget-related insights here
        insights.append("Set up budgets for better financial control")
        insights.append("Track your spending against budget goals")
        insights.append("Review and adjust budgets monthly")
        
        return insights
    }
}

// MARK: - Insight Card
struct InsightCard: View {
    let title: String
    let insights: [String]
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(insights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.success)
                        
                        Text(insight)
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.onSurface)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Upcoming Bills Section
struct UpcomingBillsSection: View {
    let pendingBillsAmount: Double
    let upcomingInsuranceAmount: Double
    @ObservedObject var currencySettings: CurrencySettings
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingBillDetails = false
    
    private var totalBillsAmount: Double {
        pendingBillsAmount + upcomingInsuranceAmount
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Upcoming Bills")
                    .font(DesignSystem.Typography.headlineSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Spacer()
                
                // Total Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total")
                        .font(DesignSystem.Typography.labelSmall)
                        .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                    
                    Text(totalBillsAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        .font(DesignSystem.Typography.titleMedium)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.error)
                }
            }
            
            HStack(spacing: DesignSystem.Spacing.md) {
                // Pending Credit Card Bills
                BillCard(
                    title: "Pending Bills",
                    amount: pendingBillsAmount,
                    icon: "creditcard.fill",
                    color: DesignSystem.Colors.error,
                    currencySettings: currencySettings
                )
                
                // Upcoming Insurance
                BillCard(
                    title: "Next Insurance",
                    amount: upcomingInsuranceAmount,
                    icon: "shield.fill",
                    color: DesignSystem.Colors.primary,
                    currencySettings: currencySettings
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .cardStyle()
        .onTapGesture {
            showingBillDetails = true
        }
        .sheet(isPresented: $showingBillDetails) {
            BillDetailsView(
                pendingBillsAmount: pendingBillsAmount,
                upcomingInsuranceAmount: upcomingInsuranceAmount,
                viewModel: viewModel,
                currencySettings: currencySettings
            )
        }
    }
}

// MARK: - Bill Card
struct BillCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    @ObservedObject var currencySettings: CurrencySettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(title)
                .font(DesignSystem.Typography.labelMedium)
                .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
            
            Text(amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                .font(DesignSystem.Typography.titleMedium)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surfaceVariant.opacity(0.3))
        .cornerRadius(DesignSystem.CornerRadius.md)
    }
}

// MARK: - Bill Details View
struct BillDetailsView: View {
    let pendingBillsAmount: Double
    let upcomingInsuranceAmount: Double
    @ObservedObject var viewModel: ExpenseViewModel
    @ObservedObject var currencySettings: CurrencySettings
    @Environment(\.dismiss) private var dismiss
    
    private var totalAmount: Double {
        pendingBillsAmount + upcomingInsuranceAmount
    }
    
    private var pendingCreditCards: [(name: String, amount: Double)] {
        let creditCardAccounts = viewModel.accounts.filter { $0.wrappedAccountType == .creditCard }
        var pendingCards: [(name: String, amount: Double)] = []
        
        for account in creditCardAccounts {
            let metadata = account.metadataDictionary
            let billHistoryKeys = metadata.keys.filter { $0.hasPrefix("statement_") }
            
            let dateFormatter = ISO8601DateFormatter()
            var latestStatementDate: Date?
            var latestBillAmount: Double = 0
            
            for key in billHistoryKeys {
                if let statementJsonString = metadata[key],
                   let statementJsonData = statementJsonString.data(using: .utf8),
                   let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String],
                   let statementDateString = statementData["statementDate"],
                   let statementDate = dateFormatter.date(from: statementDateString) {
                    
                    let dueAmount = statementData["dueAmount"].flatMap { Double($0) } ?? 0.0
                    let isManuallyPaid = statementData["manuallyPaid"] == "true"
                    
                    if (latestStatementDate == nil || statementDate > latestStatementDate!) &&
                       !isManuallyPaid {
                        latestStatementDate = statementDate
                        latestBillAmount = dueAmount
                    }
                }
            }
            
            // Verify this is the most recent statement for this account
            if let latestDate = latestStatementDate, latestBillAmount > 0 {
                let allDates = billHistoryKeys.compactMap { key -> Date? in
                    guard let statementJsonString = metadata[key],
                          let statementJsonData = statementJsonString.data(using: .utf8),
                          let statementData = try? JSONSerialization.jsonObject(with: statementJsonData) as? [String: String],
                          let statementDateString = statementData["statementDate"] else { return nil }
                    return dateFormatter.date(from: statementDateString)
                }
                
                if let maxDate = allDates.max(), Calendar.current.isDate(latestDate, inSameDayAs: maxDate) {
                    pendingCards.append((name: account.wrappedAccountName, amount: latestBillAmount))
                }
            }
        }
        
        return pendingCards
    }
    
    private var upcomingInsurancePolicies: [(name: String, amount: Double, dueDate: Date)] {
        let policies = viewModel.insurancePolicies
        let calendar = Calendar.current
        let today = Date()
        let currentDay = calendar.component(.day, from: today)
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        
        var upcomingPolicies: [(name: String, amount: Double, dueDate: Date)] = []
        
        for policy in policies where policy.isActive {
            var targetMonth = currentMonth
            var targetYear = currentYear
            
            if currentDay > policy.dayOfMonth {
                targetMonth += 1
                if targetMonth > 12 {
                    targetMonth = 1
                    targetYear += 1
                }
            }
            
            let dateComponents = DateComponents(year: targetYear, month: targetMonth, day: policy.dayOfMonth)
            if let nextDueDate = calendar.date(from: dateComponents) {
                let daysUntilDue = calendar.dateComponents([.day], from: today, to: nextDueDate).day ?? 0
                
                if daysUntilDue >= 0 && daysUntilDue <= 30 {
                    upcomingPolicies.append((name: policy.name, amount: policy.premiumAmount, dueDate: nextDueDate))
                }
            }
        }
        
        return upcomingPolicies.sorted { $0.dueDate < $1.dueDate }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Total Summary
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Text("Total Upcoming Bills")
                            .font(DesignSystem.Typography.headlineMedium)
                            .foregroundColor(DesignSystem.Colors.onSurface)
                        
                        Text(totalAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                            .font(DesignSystem.Typography.displaySmall)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(DesignSystem.Colors.error.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.lg)
                    
                    // Pending Credit Card Bills
                    if !pendingCreditCards.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            HStack {
                                Image(systemName: "creditcard.fill")
                                    .foregroundColor(DesignSystem.Colors.error)
                                Text("Pending Credit Card Bills")
                                    .font(DesignSystem.Typography.headlineSmall)
                                    .foregroundColor(DesignSystem.Colors.onSurface)
                                Spacer()
                                Text(pendingBillsAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .font(DesignSystem.Typography.titleMedium)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.error)
                            }
                            
                            ForEach(pendingCreditCards, id: \.name) { card in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(card.name)
                                            .font(DesignSystem.Typography.bodyMedium)
                                            .foregroundColor(DesignSystem.Colors.onSurface)
                                        Text("Pending Payment")
                                            .font(DesignSystem.Typography.labelSmall)
                                            .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(card.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                        .font(DesignSystem.Typography.titleSmall)
                                        .fontWeight(.medium)
                                        .foregroundColor(DesignSystem.Colors.error)
                                }
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .cardStyle()
                    }
                    
                    // Upcoming Insurance Premiums
                    if !upcomingInsurancePolicies.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            HStack {
                                Image(systemName: "shield.fill")
                                    .foregroundColor(DesignSystem.Colors.primary)
                                Text("Upcoming Insurance Premiums")
                                    .font(DesignSystem.Typography.headlineSmall)
                                    .foregroundColor(DesignSystem.Colors.onSurface)
                                Spacer()
                                Text(upcomingInsuranceAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                    .font(DesignSystem.Typography.titleMedium)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                            
                            ForEach(upcomingInsurancePolicies, id: \.name) { policy in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(policy.name)
                                            .font(DesignSystem.Typography.bodyMedium)
                                            .foregroundColor(DesignSystem.Colors.onSurface)
                                        Text("Due: \(policy.dueDate, style: .date)")
                                            .font(DesignSystem.Typography.labelSmall)
                                            .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(policy.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                        .font(DesignSystem.Typography.titleSmall)
                                        .fontWeight(.medium)
                                        .foregroundColor(DesignSystem.Colors.primary)
                                }
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .cardStyle()
                    }
                    
                    // Empty State
                    if pendingCreditCards.isEmpty && upcomingInsurancePolicies.isEmpty {
                        ContentUnavailableView(
                            "No Upcoming Bills",
                            systemImage: "checkmark.circle.fill",
                            description: Text("You're all caught up! No pending bills or upcoming insurance premiums.")
                        )
                        .foregroundColor(DesignSystem.Colors.success)
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Upcoming Bills")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
} 