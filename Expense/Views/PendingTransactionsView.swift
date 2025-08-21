import SwiftUI

struct PendingTransactionsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var selectedAccount: CDAccount?

    var body: some View {
        List {
            if viewModel.pendingTransactions.isEmpty {
                ContentUnavailableView("No pending items", systemImage: "tray")
            } else {
                ForEach(viewModel.pendingTransactions) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.subject).font(.headline)
                            Spacer()
                            Text(item.amount, format: .currency(code: CurrencySettings.shared.selectedCurrency.rawValue))
                                .foregroundColor(item.isCredit ? .green : .red)
                        }
                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Text("Category:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Menu(TransactionCategory(rawValue: item.suggestedCategory).displayName) {
                                ForEach(TransactionCategory.allCases, id: \.self) { cat in
                                    Button(cat.displayName) {
                                        viewModel.updatePendingTransactionCategory(id: item.id, to: cat)
                                    }
                                }
                                if !viewModel.customCategories.isEmpty {
                                    Divider()
                                    ForEach(viewModel.customCategories, id: \.self) { custom in
                                        Button(custom) {
                                            viewModel.updatePendingTransactionCategory(id: item.id, to: .custom(custom))
                                        }
                                    }
                                }
                            }
                        }
                        Text(item.notes ?? item.body.prefix(120) + (item.body.count > 120 ? "…" : ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Menu("Approve") {
                                ForEach(viewModel.accounts) { acc in
                                    Button(acc.wrappedAccountName) { viewModel.approvePendingTransaction(id: item.id, toAccount: acc) }
                                }
                            }
                            Button(role: .destructive) { viewModel.removePendingTransaction(id: item.id) } label: { Text("Dismiss") }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Pending Transactions")
    }
}


