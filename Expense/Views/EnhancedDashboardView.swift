import SwiftUI
import Charts

// MARK: - Dashboard Section Types
enum DashboardSection: String, CaseIterable, Identifiable {
    case netWorth = "netWorth"
    case summaryCards = "summaryCards"
    case spendingChart = "spendingChart"
    case upcomingBills = "upcomingBills"
    case recentTransactions = "recentTransactions"
    case insights = "insights"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .netWorth: return "Net Worth"
        case .summaryCards: return "Summary Cards"
        case .spendingChart: return "Spending Chart"
        case .upcomingBills: return "Upcoming Bills"
        case .recentTransactions: return "Recent Transactions"
        case .insights: return "Insights"
        }
    }
    
    var icon: String {
        switch self {
        case .netWorth: return "chart.line.uptrend.xyaxis"
        case .summaryCards: return "square.grid.2x2"
        case .spendingChart: return "chart.bar"
        case .upcomingBills: return "calendar.badge.exclamationmark"
        case .recentTransactions: return "list.bullet"
        case .insights: return "lightbulb"
        }
    }
}

// MARK: - Enhanced Dashboard View
struct EnhancedDashboardView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var selectedTimeRange: TimeRange = .currentMonth
    @State private var showingInsights = false
    @State private var showingDateFilter = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var pendingBillsAmount: Double = 0
    @State private var upcomingInsuranceAmount: Double = 0
    
    // Section reordering states
    @State private var isEditMode = false
    @State private var sectionOrder: [DashboardSection] = []
    
    // Computed property for filtered transactions
    private var filteredTransactions: [CDTransaction] {
        let calendar = Calendar.current
        let now = Date()
        
        let filtered: [CDTransaction]
        switch selectedTimeRange {
        case .currentWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            filtered = viewModel.dashboardTransactions.filter { $0.date ?? now >= startOfWeek }
        case .lastWeek:
            let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now) ?? now
            let lastWeekEnd = calendar.date(byAdding: .day, value: 6, to: lastWeekStart) ?? now
            filtered = viewModel.dashboardTransactions.filter { 
                guard let date = $0.date else { return false }
                return date >= lastWeekStart && date <= lastWeekEnd
            }
        case .currentMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            filtered = viewModel.dashboardTransactions.filter { $0.date ?? now >= startOfMonth }
        case .lastMonth:
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: calendar.dateInterval(of: .month, for: now)?.start ?? now) ?? now
            let lastMonthEnd = calendar.date(byAdding: .day, value: -1, to: calendar.dateInterval(of: .month, for: now)?.start ?? now) ?? now
            filtered = viewModel.dashboardTransactions.filter { 
                guard let date = $0.date else { return false }
                return date >= lastMonthStart && date <= lastMonthEnd
            }
        case .currentYear:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            filtered = viewModel.dashboardTransactions.filter { $0.date ?? now >= startOfYear }
        case .lastYear:
            let lastYearStart = calendar.date(byAdding: .year, value: -1, to: calendar.dateInterval(of: .year, for: now)?.start ?? now) ?? now
            let lastYearEnd = calendar.date(byAdding: .day, value: -1, to: calendar.dateInterval(of: .year, for: now)?.start ?? now) ?? now
            filtered = viewModel.dashboardTransactions.filter { 
                guard let date = $0.date else { return false }
                return date >= lastYearStart && date <= lastYearEnd
            }
        case .custom:
            filtered = viewModel.dashboardTransactions.filter { 
                guard let date = $0.date else { return false }
                return date >= customStartDate && date <= customEndDate
            }
        }
        
        // Filter out self-transfers
        return filtered.filter { transaction in
            let cat = transaction.wrappedCategory
            return cat != TransactionCategory.selfTransfer.rawValue
        }
    }
    
    // Helper computed properties for specific transaction lists
    private var incomeTransactions: [CDTransaction] {
        // For income, use salary cycle: 27th of previous month to 27th of current month
        let calendar = Calendar.current
        let now = Date()
        
        // Get 27th of current month
        let currentMonth27th = calendar.date(bySetting: .day, value: 27, of: now) ?? now
        
        // Get 27th of previous month
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let previousMonth27th = calendar.date(bySetting: .day, value: 27, of: previousMonth) ?? previousMonth
        
        // Filter income transactions within the salary cycle
        let salaryPeriodTransactions = viewModel.dashboardTransactions.filter { transaction in
            guard let transactionDate = transaction.date else { return false }
            
            // If we're past 27th of current month, use current 27th to next 27th
            if now >= currentMonth27th {
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
                let nextMonth27th = calendar.date(bySetting: .day, value: 27, of: nextMonth) ?? nextMonth
                return transactionDate >= currentMonth27th && transactionDate < nextMonth27th
            } else {
                // If we're before 27th of current month, use previous 27th to current 27th
                return transactionDate >= previousMonth27th && transactionDate < currentMonth27th
            }
        }
        
        // Filter for income transactions and exclude self-transfers
        return salaryPeriodTransactions.filter { transaction in
            let isIncome = transaction.isCredit && isIncomeCategory(transaction)
            let isNotSelfTransfer = !isSelfTransfer(transaction)
            return isIncome && isNotSelfTransfer
        }
    }
    
    private var expenseTransactions: [CDTransaction] {
        // Only include actual debit transactions (money going out)
        return filteredTransactions.filter { !$0.isCredit }
    }
    
    private var allTransactions: [CDTransaction] {
        return filteredTransactions
    }
    
    // Calculation methods
    private func calculateIncome(for timeRange: TimeRange) -> Double {
        return incomeTransactions.reduce(0) { $0 + $1.amount }
    }
    
    private func calculateExpenses(for timeRange: TimeRange) -> Double {
        // expenseTransactions already contains only debit transactions
        return expenseTransactions.reduce(0) { $0 + $1.amount }
    }
    
    private func calculateSavings(for timeRange: TimeRange) -> Double {
        return calculateIncome(for: timeRange) - calculateExpenses(for: timeRange)
    }
    
    private func calculateTransactionCount(for timeRange: TimeRange) -> Int {
        return allTransactions.count
    }
    
    private func isIncomeCategory(_ transaction: CDTransaction) -> Bool {
        // Only treat explicit Salary (or categories containing the word "Income") as income
        let cat = transaction.wrappedCategory
        if cat == TransactionCategory.salary.rawValue { return true }
        if cat.localizedCaseInsensitiveContains("income") { return true }
        return false
    }
    
    private func isSelfTransfer(_ transaction: CDTransaction) -> Bool {
        let cat = transaction.wrappedCategory
        return cat == TransactionCategory.selfTransfer.rawValue
    }
    
    // MARK: - Section Order Management
    private func loadSectionOrder() {
        if let savedOrder = UserDefaults.standard.array(forKey: "DashboardSectionOrder") as? [String] {
            sectionOrder = savedOrder.compactMap { DashboardSection(rawValue: $0) }
        } else {
            sectionOrder = DashboardSection.allCases
        }
    }
    
    private func saveSectionOrder() {
        let orderStrings = sectionOrder.map { $0.rawValue }
        UserDefaults.standard.set(orderStrings, forKey: "DashboardSectionOrder")
    }
    
    private func moveSections(from source: IndexSet, to destination: Int) {
        sectionOrder.move(fromOffsets: source, toOffset: destination)
    }
    
    @ViewBuilder
    private func sectionView(for section: DashboardSection) -> some View {
        switch section {
        case .netWorth:
            NetWorthCard(viewModel: viewModel, currencySettings: currencySettings)
        case .summaryCards:
            SummaryCardsGrid(
                viewModel: viewModel,
                timeRange: selectedTimeRange,
                incomeAmount: calculateIncome(for: selectedTimeRange),
                expenseAmount: calculateExpenses(for: selectedTimeRange),
                savingsAmount: calculateSavings(for: selectedTimeRange),
                transactionCount: calculateTransactionCount(for: selectedTimeRange),
                incomeTransactions: incomeTransactions,
                expenseTransactions: expenseTransactions,
                allTransactions: allTransactions
            )
        case .spendingChart:
            SpendingChartView(transactions: filteredTransactions, timeRange: selectedTimeRange)
        case .upcomingBills:
            UpcomingBillsSection(
                pendingBillsAmount: pendingBillsAmount,
                upcomingInsuranceAmount: upcomingInsuranceAmount,
                currencySettings: currencySettings,
                viewModel: viewModel
            )
        case .recentTransactions:
            RecentTransactionsSection(transactions: filteredTransactions, viewModel: viewModel)
        case .insights:
            InsightsButton(showingInsights: $showingInsights)
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isEditMode {
                    // Edit mode with List for proper drag and drop
                    List {
                        ForEach(sectionOrder, id: \.id) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: section.icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 20)
                                    Text(section.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                
                                sectionView(for: section)
                                    .disabled(true)
                                    .opacity(0.6)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveSections)
                    }
                    .listStyle(PlainListStyle())
                    .environment(\.editMode, .constant(.active))
                } else {
                    // Normal mode with ScrollView
                    ScrollView {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            ForEach(sectionOrder, id: \.id) { section in
                                sectionView(for: section)
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.top, DesignSystem.Spacing.md)
                    }
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if isEditMode {
                                saveSectionOrder()
                            }
                            isEditMode.toggle()
                        }
                    }) {
                        Text(isEditMode ? "Done" : "Edit")
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingDateFilter = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
            }
            .onAppear {
                loadSectionOrder()
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
            .sheet(isPresented: $showingDateFilter) {
                DateFilterSheet(
                    selectedTimeRange: $selectedTimeRange,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate
                )
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
        let assets = viewModel.accounts.filter { $0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }
        let liabilities = viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + abs($1.balance) }
        return assets - liabilities
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
                    amount: viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + abs($1.balance) },
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


// MARK: - Summary Cards Grid
struct SummaryCardsGrid: View {
    @ObservedObject var viewModel: ExpenseViewModel
    let timeRange: TimeRange
    let incomeAmount: Double
    let expenseAmount: Double
    let savingsAmount: Double
    let transactionCount: Int
    let incomeTransactions: [CDTransaction]
    let expenseTransactions: [CDTransaction]
    let allTransactions: [CDTransaction]
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingIncomeTransactions = false
    @State private var showingExpenseTransactions = false
    @State private var showingAllTransactions = false
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.Spacing.md) {
            Button(action: { showingIncomeTransactions = true }) {
                EnhancedSummaryCard(
                    title: "Income",
                    value: incomeAmount,
                    icon: "arrow.up.circle.fill",
                    color: DesignSystem.Colors.success,
                    currencySettings: currencySettings
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showingIncomeTransactions) {
                TransactionListView(
                    title: "Income Transactions",
                    transactions: incomeTransactions,
                    viewModel: viewModel
                )
            }
            
            Button(action: { showingExpenseTransactions = true }) {
                EnhancedSummaryCard(
                    title: "Expenses",
                    value: expenseAmount,
                    icon: "arrow.down.circle.fill",
                    color: DesignSystem.Colors.error,
                    currencySettings: currencySettings
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showingExpenseTransactions) {
                TransactionListView(
                    title: "Expense Transactions",
                    transactions: expenseTransactions,
                    viewModel: viewModel
                )
            }
            
            EnhancedSummaryCard(
                title: "Savings",
                value: savingsAmount,
                icon: "banknote.fill",
                color: DesignSystem.Colors.info,
                currencySettings: currencySettings
            )
            
            Button(action: { showingAllTransactions = true }) {
                EnhancedSummaryCard(
                    title: "Transactions",
                    value: Double(transactionCount),
                    icon: "list.bullet.circle.fill",
                    color: DesignSystem.Colors.primary,
                    currencySettings: currencySettings,
                    isCurrency: false
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showingAllTransactions) {
                TransactionListView(
                    title: "All Transactions",
                    transactions: allTransactions,
                    viewModel: viewModel
                )
            }
        }
    }
    
    // All methods and computed properties are now defined above the body
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
        case .currentWeek, .lastWeek: numberOfPoints = 7
        case .currentMonth, .lastMonth: numberOfPoints = 30
        case .currentYear, .lastYear: numberOfPoints = 12
        case .custom: numberOfPoints = 30 // Default for custom range
        }
        
        for i in 0..<numberOfPoints {
            let date: Date
            switch timeRange {
            case .currentWeek, .lastWeek:
                date = calendar.date(byAdding: .day, value: -i, to: now) ?? now
            case .currentMonth, .lastMonth:
                date = calendar.date(byAdding: .day, value: -i, to: now) ?? now
            case .currentYear, .lastYear:
                date = calendar.date(byAdding: .month, value: -i, to: now) ?? now
            case .custom:
                date = calendar.date(byAdding: .day, value: -i, to: now) ?? now
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
        // Use already filtered transactions and include only expenses
        let expenseTransactions = transactions.filter { !$0.isCredit && !isSelfTransfer($0) }
        let grouped = Dictionary(grouping: expenseTransactions) { $0.category ?? "Uncategorized" }
        
        return grouped.map { category, transactions in
            CategoryDataPoint(
                category: category,
                amount: transactions.reduce(0) { $0 + $1.amount }
            )
        }.sorted { $0.amount > $1.amount }
    }
    
    private func isSelfTransfer(_ transaction: CDTransaction) -> Bool {
        let cat = transaction.wrappedCategory
        return cat == TransactionCategory.selfTransfer.rawValue
    }

    // This duplicate function is removed - using the main one in EnhancedDashboardView
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
    case currentWeek
    case lastWeek
    case currentMonth
    case lastMonth
    case currentYear
    case lastYear
    case custom
    
    var displayName: String {
        switch self {
        case .currentWeek: return "This Week"
        case .lastWeek: return "Last Week"
        case .currentMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .currentYear: return "This Year"
        case .lastYear: return "Last Year"
        case .custom: return "Custom Range"
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

// MARK: - Date Filter Sheet
struct DateFilterSheet: View {
    @Binding var selectedTimeRange: TimeRange
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("Filter Transactions")
                        .font(DesignSystem.Typography.headlineSmall)
                        .fontWeight(.semibold)
                    
                    Text("Select a time period to view your financial data")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: DesignSystem.Spacing.md) {
                    ForEach(TimeRange.allCases.filter { $0 != .custom }, id: \.self) { range in
                        Button(action: {
                            selectedTimeRange = range
                            dismiss()
                        }) {
                            VStack(spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: iconForTimeRange(range))
                                    .font(.title2)
                                    .foregroundColor(selectedTimeRange == range ? DesignSystem.Colors.onPrimary : DesignSystem.Colors.primary)
                                
                                Text(range.displayName)
                                    .font(DesignSystem.Typography.labelMedium)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedTimeRange == range ? DesignSystem.Colors.onPrimary : DesignSystem.Colors.onSurface)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.md)
                            .background(selectedTimeRange == range ? DesignSystem.Colors.primary : DesignSystem.Colors.surfaceVariant)
                            .cornerRadius(DesignSystem.CornerRadius.lg)
                        }
                    }
                }
                
                // Custom Date Range Section
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(DesignSystem.Colors.primary)
                        Text("Custom Date Range")
                            .font(DesignSystem.Typography.titleSmall)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        
                        Button("Apply Custom Range") {
                            selectedTimeRange = .custom
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.primary)
                        .foregroundColor(DesignSystem.Colors.onPrimary)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surfaceVariant)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                }
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.lg)
            .navigationTitle("Date Filter")
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
    
    private func iconForTimeRange(_ range: TimeRange) -> String {
        switch range {
        case .currentWeek, .lastWeek: return "calendar.day.timeline.left"
        case .currentMonth, .lastMonth: return "calendar"
        case .currentYear, .lastYear: return "calendar.badge.plus"
        case .custom: return "calendar.badge.clock"
        }
    }
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

// MARK: - Transaction List View
struct TransactionListView: View {
    let title: String
    let transactions: [CDTransaction]
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var sortedTransactions: [CDTransaction] {
        transactions.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    var body: some View {
        NavigationView {
            List {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "tray.fill",
                        description: Text("No transactions found for the selected period.")
                    )
                } else {
                    Section {
                        Text("Total: \(transactions.reduce(0) { $0 + $1.amount }, format: .currency(code: currencySettings.selectedCurrency.rawValue))")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Section("Transactions (\(transactions.count))") {
                        ForEach(sortedTransactions) { transaction in
                            TransactionRowView(transaction: transaction)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Transaction Row View
struct TransactionRowView: View {
    let transaction: CDTransaction
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.wrappedNotes)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
                    Text(TransactionCategory(rawValue: transaction.wrappedCategory).displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(transaction.wrappedDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(transaction.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.isCredit ? .green : .primary)
                
                if let account = transaction.account {
                    Text(account.wrappedAccountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
} 