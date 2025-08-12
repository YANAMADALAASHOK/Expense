import SwiftUI
import CoreData

struct TransactionView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingAddTransaction = false
    @State private var showingLoanPayment = false
    @State private var selectedTransaction: CDTransaction?
    @State private var isRefreshing = false
    @State private var selectedTransactionType: TransactionType?
    @State private var selectedCategoryFilter: String? = nil
    
    var body: some View {
        NavigationView {
            List {
                // Category filter
                Section {
                    Picker("Category", selection: Binding(
                        get: { selectedCategoryFilter ?? "All" },
                        set: { selectedCategoryFilter = $0 == "All" ? nil : $0 }
                    )) {
                        Text("All").tag("All")
                        ForEach(viewModel.allCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }
                ForEach(filteredTransactions.grouped(by: \.wrappedDate), id: \.key) { date, transactions in
                    Section(header: Text(date.formatted(date: .abbreviated, time: .omitted))) {
                        ForEach(transactions, id: \.id) { transaction in
                            TransactionRow(transaction: transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTransaction = transaction
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.deleteTransaction(transaction)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        selectedTransaction = transaction
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
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
                    Menu {
                        Button(action: { 
                            showingAddTransaction = true
                            selectedTransactionType = .expense
                        }) {
                            Label("Add Expense", systemImage: "arrow.down.circle")
                        }
                        
                        Button(action: { 
                            showingAddTransaction = true
                            selectedTransactionType = .income
                        }) {
                            Label("Add Income", systemImage: "arrow.up.circle")
                        }
                        
                        Button(action: { 
                            showingLoanPayment = true
                        }) {
                            Label("Loan Payment", systemImage: "indianrupeesign.circle")
                        }
                        
                        Button(action: { 
                            showingAddTransaction = true
                            selectedTransactionType = .creditCardPayment
                        }) {
                            Label("Credit Card Payment", systemImage: "creditcard.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await refreshData()
            }
            .sheet(isPresented: $showingAddTransaction) {
                if let type = selectedTransactionType {
                    AddTransactionView(viewModel: viewModel, transactionType: type)
                }
            }
            .sheet(isPresented: $showingLoanPayment) {
                LoanPaymentView(viewModel: viewModel)
            }
            .sheet(item: $selectedTransaction) { transaction in
                EditTransactionView(viewModel: viewModel, transaction: transaction)
            }
        }
    }
    
    private var filteredTransactions: [CDTransaction] {
        guard let filter = selectedCategoryFilter else { return viewModel.recentTransactions }
        return viewModel.recentTransactions.filter { $0.wrappedCategory == filter }
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