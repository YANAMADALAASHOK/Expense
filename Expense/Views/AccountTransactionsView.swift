import SwiftUI
import CoreData
import FirebaseFirestore

struct AccountTransactionsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    let account: CDAccount
    @Environment(\.dismiss) private var dismiss
    
    @State private var transactions: [CDTransaction] = []
    @State private var runningBalances: [UUID: (before: Double, after: Double)] = [:]
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Account Summary Header
                AccountSummaryHeader(account: account)
                
                // Transactions List
                List {
                    ForEach(transactions.grouped(by: \.wrappedDate), id: \.key) { date, dayTransactions in
                        Section(header: Text(date.formatted(date: .abbreviated, time: .omitted))) {
                            ForEach(dayTransactions.sorted(by: { $0.wrappedDate > $1.wrappedDate }), id: \.id) { transaction in
                                TransactionWithBalanceRow(
                                    transaction: transaction,
                                    balanceInfo: runningBalances[transaction.id ?? UUID()]
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Could add edit functionality here
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await loadTransactions()
                }
            }
            .navigationTitle(account.wrappedAccountName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await loadTransactions() } }) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                }
            }
            .onAppear {
                Task {
                    await loadTransactions()
                }
            }
        }
    }
    
    private func loadTransactions() async {
        isRefreshing = true
        
        // Fetch all transactions for this account
        let fetchRequest = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
        fetchRequest.predicate = NSPredicate(format: "account == %@", account)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDTransaction.date, ascending: false)]
        
        do {
            let allTransactions = try viewModel.viewContext.fetch(fetchRequest)
            
            // Calculate running balances
            var currentBalance = account.balance
            var balanceMap: [UUID: (before: Double, after: Double)] = [:]
            
            // Sort transactions by date (oldest first for balance calculation)
            let sortedTransactions = allTransactions.sorted { $0.wrappedDate < $1.wrappedDate }
            
            for transaction in sortedTransactions {
                let beforeBalance = currentBalance
                
                // Calculate the balance change
                let balanceChange: Double
                if transaction.isCredit {
                    // Credit increases balance for assets, decreases for liabilities
                    if account.wrappedAccountType.isAsset {
                        balanceChange = transaction.amount
                    } else {
                        balanceChange = -transaction.amount
                    }
                } else {
                    // Debit decreases balance for assets, increases for liabilities
                    if account.wrappedAccountType.isAsset {
                        balanceChange = -transaction.amount
                    } else {
                        balanceChange = transaction.amount
                    }
                }
                
                currentBalance -= balanceChange // Reverse the change to get previous balance
                
                if let id = transaction.id {
                    balanceMap[id] = (before: currentBalance, after: beforeBalance)
                }
            }
            
            await MainActor.run {
                self.transactions = allTransactions
                self.runningBalances = balanceMap
                self.isRefreshing = false
            }
        } catch {
            print("Error loading transactions: \(error)")
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }
}

// MARK: - Supporting Views

struct AccountSummaryHeader: View {
    let account: CDAccount
    
    var body: some View {
        VStack(spacing: 12) {
            Text(account.wrappedAccountName)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(account.wrappedAccountType.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(String(format: "₹%.2f", account.balance))
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(account.wrappedAccountType.isAsset ? .green : .red)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
}

struct TransactionWithBalanceRow: View {
    let transaction: CDTransaction
    let balanceInfo: (before: Double, after: Double)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Transaction details
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.wrappedCategory)
                        .font(.headline)
                    
                    if let notes = transaction.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(transaction.wrappedDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "₹%.2f", transaction.amount))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(transaction.isCredit ? .green : .red)
                    
                    Text(transaction.isCredit ? "CR" : "DR")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(transaction.isCredit ? .green : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(transaction.isCredit ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            // Balance information
            if let balanceInfo = balanceInfo {
                HStack {
                    Text("Balance: " + String(format: "₹%.2f", balanceInfo.before))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "₹%.2f", balanceInfo.after))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}



#if DEBUG
struct AccountTransactionsView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Account Transactions Preview")
    }
}
#endif 