import SwiftUI
import Charts

struct ReportsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var selectedPeriod = TimePeriod.currentWeek
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
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
        return viewModel.recentTransactions.filter { transaction in
            guard let date = transaction.date else { return false }
            return interval.contains(date)
        }
    }
    
    var categoryTotals: [(category: String, amount: Double)] {
        Dictionary(grouping: filteredTransactions) { $0.wrappedCategory }
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
                    ForEach(categoryTotals, id: \.category) { item in
                        HStack {
                            Text(item.category)
                            Spacer()
                            Text(item.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(item.amount >= 0 ? .green : .red)
                        }
                    }
                }
            }
            .navigationTitle("Reports")
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

#if DEBUG
struct ReportsView_Previews: PreviewProvider {
    static var previews: some View {
        ReportsView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 