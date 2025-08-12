import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Summary Cards
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        SummaryCard(title: "Net Worth", value: viewModel.accounts.reduce(0) { $0 + ($1.wrappedAccountType.isAsset ? $1.balance : -$1.balance) }, icon: "scalemass.fill", color: .green)
                        SummaryCard(title: "Total Assets", value: viewModel.accounts.filter { $0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }, icon: "arrow.up.circle.fill", color: .blue)
                        SummaryCard(title: "Total Liabilities", value: viewModel.accounts.filter { !$0.wrappedAccountType.isAsset }.reduce(0) { $0 + $1.balance }, icon: "arrow.down.circle.fill", color: .red)
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
        }
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