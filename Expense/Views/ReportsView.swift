import SwiftUI
import Charts

struct ReportsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var selectedPeriod: TimePeriod = .currentMonth
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var selectedCategory: String?
    
    enum TimePeriod: String, CaseIterable {
        case currentWeek = "This Week"
        case lastWeek = "Last Week"
        case twoWeeksAgo = "2 Weeks Ago"
        case threeWeeksAgo = "3 Weeks Ago"
        case currentMonth = "This Month"
        case lastMonth = "Last Month"
        case year = "This Year"
        case custom = "Custom Range"
    }
    
    var dateInterval: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedPeriod {
        case .currentWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)!
        case .lastWeek:
            let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
            return calendar.dateInterval(of: .weekOfYear, for: lastWeek)!
        case .twoWeeksAgo:
            let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now)!
            return calendar.dateInterval(of: .weekOfYear, for: twoWeeksAgo)!
        case .threeWeeksAgo:
            let threeWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -3, to: now)!
            return calendar.dateInterval(of: .weekOfYear, for: threeWeeksAgo)!
        case .currentMonth:
            return calendar.dateInterval(of: .month, for: now)!
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            return calendar.dateInterval(of: .month, for: lastMonth)!
        case .year:
            return calendar.dateInterval(of: .year, for: now)!
        case .custom:
            return DateInterval(
                start: Calendar.current.startOfDay(for: customStartDate),
                end: Calendar.current.endOfDay(for: customEndDate)
            )
        }
    }
    
    var filteredTransactions: [CDTransaction] {
        let interval = dateInterval
        return viewModel.dashboardTransactions.filter { transaction in
            guard let date = transaction.date else { return false }
            // Exclude self transfers from charts and totals
            if TransactionCategory(rawValue: transaction.wrappedCategory) == .selfTransfer { return false }
            return interval.contains(date)
        }
    }
    
    var categoryTotals: [(category: String, amount: Double)] {
        // Group by parent category (before ::)
        Dictionary(grouping: filteredTransactions) { txn in
            let raw = txn.wrappedCategory
            if let range = raw.range(of: "::"), !raw.hasPrefix("::"), !raw.hasSuffix("::") {
                return String(raw[..<range.lowerBound])
            }
            return raw
        }
        .map { (category, transactions) in
            let total = transactions.reduce(0) { sum, transaction in
                sum + (transaction.isCredit ? transaction.amount : -transaction.amount)
            }
            return (category: category, amount: total)
        }
        .sorted { abs($0.amount) > abs($1.amount) }
    }
    
    var totalIncome: Double {
        filteredTransactions.filter(\.isCredit).reduce(0) { $0 + $1.amount }
    }
    
    var totalExpenses: Double {
        filteredTransactions.filter { !$0.isCredit }.reduce(0) { $0 + $1.amount }
    }
    
    var categoryTransactions: [CDTransaction] {
        guard let category = selectedCategory else { return [] }
        return filteredTransactions.filter { txn in
            let raw = txn.wrappedCategory
            if let range = raw.range(of: "::"), !raw.hasPrefix("::"), !raw.hasSuffix("::") {
                let parent = String(raw[..<range.lowerBound])
                return parent == category
            }
            return raw == category
        }
        .sorted { $0.wrappedDate > $1.wrappedDate }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("Time Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    
                    if selectedPeriod == .custom {
                        DatePicker("Start Date", selection: $customStartDate, in: ...Date(), displayedComponents: [.date])
                        DatePicker("End Date", selection: $customEndDate, in: customStartDate...Date(), displayedComponents: [.date])
                    }
                }
                

                Section("Summary") {
                    HStack {
                        Text("Total Income")
                        Spacer()
                        Text(totalIncome, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("Total Expenses")
                        Spacer()
                        Text(totalExpenses, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                            .foregroundColor(.red)
                    }
                    
                    HStack {
                        Text("Net Savings")
                        Spacer()
                        Text(totalIncome - totalExpenses, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                            .foregroundColor(totalIncome - totalExpenses >= 0 ? .green : .red)
                    }
                }
                
                Section("Category Breakdown") {
                    Chart(categoryTotals, id: \.category) { item in
                        SectorMark(
                            angle: .value("Amount", abs(item.amount)),
                            innerRadius: .ratio(0.618),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Category", item.category))
                        .cornerRadius(5)
                    }
                    .frame(height: 300)
                    .chartLegend(position: .bottom, alignment: .center)
                    
                    ForEach(categoryTotals, id: \.category) { item in
                        HStack {
                            Text(item.category)
                            Spacer()
                            Text(item.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(item.amount >= 0 ? .green : .red)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = item.category
                        }
                    }
                }
            }
            .navigationTitle("Reports")
            .sheet(item: $selectedCategory) { category in
                CategoryDetailView(
                    category: category,
                    transactions: categoryTransactions,
                    currencyCode: currencySettings.selectedCurrency.rawValue,
                    onDismiss: { selectedCategory = nil }
                )
            }
        }
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return self.date(byAdding: components, to: startOfDay(for: date))!
    }
}

extension String: Identifiable {
    public var id: String { self }
}

// MARK: - Category Detail View with Subcategory Filtering
struct CategoryDetailView: View {
    let category: String
    let transactions: [CDTransaction]
    let currencyCode: String
    let onDismiss: () -> Void
    
    @State private var selectedSubcategory: String? = nil
    @State private var showingFilter = false
    
    // Extract unique subcategories from transactions
    private var subcategories: [String] {
        let subcats = transactions.compactMap { transaction -> String? in
            let raw = transaction.wrappedCategory
            if let range = raw.range(of: "::"), !raw.hasPrefix("::"), !raw.hasSuffix("::") {
                let subcategory = String(raw[range.upperBound...])
                return subcategory.isEmpty ? nil : subcategory
            }
            return nil
        }
        return Array(Set(subcats)).sorted()
    }
    
    // Filter transactions by selected subcategory
    private var filteredTransactions: [CDTransaction] {
        guard let selectedSubcategory = selectedSubcategory else { return transactions }
        return transactions.filter { transaction in
            let raw = transaction.wrappedCategory
            if let range = raw.range(of: "::"), !raw.hasPrefix("::"), !raw.hasSuffix("::") {
                let subcategory = String(raw[range.upperBound...])
                return subcategory == selectedSubcategory
            }
            return false
        }
    }
    
    // Calculate total for filtered transactions
    private var filteredTotal: Double {
        filteredTransactions.reduce(0) { sum, transaction in
            sum + (transaction.isCredit ? transaction.amount : -transaction.amount)
        }
    }
    
    private var totalCount: Int { filteredTransactions.count }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Summary section
                summarySection
                
                // Transaction list
                transactionsList
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !subcategories.isEmpty {
                        Button {
                            showingFilter = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .confirmationDialog("Filter by Subcategory", isPresented: $showingFilter) {
            Button("All Subcategories") {
                selectedSubcategory = nil
            }
            
            ForEach(subcategories, id: \.self) { subcategory in
                Button(subcategory) {
                    selectedSubcategory = subcategory
                }
            }
            
            Button("Cancel", role: .cancel) { }
        }
    }
    
    @ViewBuilder
    private var summarySection: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(filteredTotal, format: .currency(code: currencyCode))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(filteredTotal >= 0 ? .green : .red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Transactions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(totalCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
            
            if let selectedSubcategory = selectedSubcategory {
                HStack {
                    Text("Filtered by: \(selectedSubcategory)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear Filter") {
                        self.selectedSubcategory = nil
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    @ViewBuilder
    private var transactionsList: some View {
        List {
            if filteredTransactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "doc.text",
                    description: Text(selectedSubcategory != nil ? "No transactions found for this subcategory" : "No transactions in this category")
                )
            } else {
                ForEach(filteredTransactions) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
    }
}

#if DEBUG
struct ReportsView_Previews: PreviewProvider {
    static var previews: some View {
        ReportsView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 