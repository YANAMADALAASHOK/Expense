import SwiftUI
import CoreData

struct TransactionView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingAddTransaction = false
    @State private var selectedTransaction: CDTransaction?
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.recentTransactions.grouped(by: \.wrappedDate), id: \.key) { date, transactions in
                    Section(header: Text(date.formatted(date: .abbreviated, time: .omitted))) {
                        ForEach(transactions) { transaction in
                            TransactionRow(transaction: transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTransaction = transaction
                                }
                        }
                        .onDelete { indexSet in
                            let transactionsToDelete = indexSet.map { transactions[$0] }
                            transactionsToDelete.forEach { viewModel.deleteTransaction($0) }
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTransaction = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await refreshData()
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView(viewModel: viewModel)
            }
            .sheet(item: $selectedTransaction) { transaction in
                EditTransactionView(viewModel: viewModel, transaction: transaction)
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
}

// Helper extension for grouping transactions by date
extension Array where Element == CDTransaction {
    func grouped(by dateKeyPath: KeyPath<CDTransaction, Date>) -> [(key: Date, value: [CDTransaction])] {
        let grouped = Dictionary(grouping: self) { transaction in
            Calendar.current.startOfDay(for: transaction[keyPath: dateKeyPath])
        }
        return grouped.sorted { $0.key > $1.key }
    }
}

#if DEBUG
struct TransactionView_Previews: PreviewProvider {
    static var previews: some View {
        TransactionView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 