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
    @State private var selectedSubcategoryFilter: String? = nil
    @State private var selectedAccountFilter: CDAccount? = nil
    @State private var showingFilter = false
    @State private var searchKeywords: String = ""
    
    var body: some View {
        let _ = PerformanceMonitor.shared.measureViewRender("TransactionView") { }
        return NavigationView {
            List {
                ForEach(filteredTransactions.grouped(by: \.wrappedDate), id: \.key) { date, transactions in
                    Section(header: 
                        HStack {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            HStack(spacing: 8) {
                                Text("\(transactions.count) transactions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // Calculate daily sum
                                let dailySum = transactions.reduce(0.0) { sum, transaction in
                                    return sum + (transaction.isCredit ? transaction.amount : -transaction.amount)
                                }
                                
                                Text("₹\(dailySum, specifier: "%.2f")")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(dailySum >= 0 ? .green : .red)
                            }
                        }
                    ) {
                        ForEach(transactions, id: \.id) { transaction in
                            TransactionRow(transaction: transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    DispatchQueue.main.async {
                                        selectedTransaction = transaction
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.deleteTransaction(transaction)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        DispatchQueue.main.async {
                                            selectedTransaction = transaction
                                        }
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)

                                    if TransactionCategory(rawValue: transaction.wrappedCategory) == .creditCardPayment {
                                        Button {
                                            // Open edit sheet to convert into paired payment quickly
                                            DispatchQueue.main.async {
                                                selectedTransaction = transaction
                                            }
                                        } label: {
                                            Label("Convert to Payment", systemImage: "arrow.triangle.2.circlepath")
                                        }
                                        .tint(.green)
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            let transactionsToDelete = indexSet.map { transactions[$0] }
                            transactionsToDelete.forEach { viewModel.deleteTransaction($0) }
                        }
                    }
                }
                
                // Lazy loading trigger - Load more when reaching end
                if hasActiveFilter {
                    // When filter is active, all matching transactions are already loaded
                    EmptyView()
                } else if viewModel.hasMoreTransactions {
                    Section {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMoreTransactions {
                                ProgressView()
                                    .padding()
                            } else {
                                Button("Load More") {
                                    viewModel.loadMoreTransactions()
                                }
                                .padding()
                            }
                            Spacer()
                        }
                    }
                    .onAppear {
                        // Auto-load when this section appears
                        if !viewModel.isLoadingMoreTransactions {
                            viewModel.loadMoreTransactions()
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingFilter = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter")
                }
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
                            selectedTransactionType = .expense
                            DispatchQueue.main.async {
                                showingAddTransaction = true
                            }
                        }) {
                            Label("Add Expense", systemImage: "arrow.down.circle")
                        }
                        
                        Button(action: { 
                            selectedTransactionType = .income
                            DispatchQueue.main.async {
                                showingAddTransaction = true
                            }
                        }) {
                            Label("Add Income", systemImage: "arrow.up.circle")
                        }
                        
                        Button(action: { 
                            DispatchQueue.main.async {
                                showingLoanPayment = true
                            }
                        }) {
                            Label("Loan Payment", systemImage: "indianrupeesign.circle")
                        }
                        
                        Button(action: { 
                            selectedTransactionType = .creditCardPayment
                            DispatchQueue.main.async {
                                showingAddTransaction = true
                            }
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
                        .onDisappear {
                            selectedTransactionType = nil
                        }
                }
            }
            .sheet(isPresented: $showingLoanPayment) {
                LoanPaymentView(viewModel: viewModel)
            }
            .sheet(item: $selectedTransaction) { transaction in
                EditTransactionView(viewModel: viewModel, transaction: transaction)
            }
            .sheet(isPresented: $showingFilter) {
                NavigationView {
                    Form {
                        Section("Filter") {
                            // Account Filter - Grouped by Bank/Type
                            Picker("Account", selection: $selectedAccountFilter) {
                                Text("All Accounts").tag(nil as CDAccount?)
                                
                                // Axis Credit Cards (must have "credit" in type or "****" in name for card number)
                                let axisCards = viewModel.accounts.filter { account in
                                    let name = account.accountName?.lowercased() ?? ""
                                    let type = account.accountType?.lowercased() ?? ""
                                    return name.contains("axis") && 
                                           (type.contains("credit") || name.contains("****"))
                                }
                                if !axisCards.isEmpty {
                                    Section(header: Text("Axis Credit Cards")) {
                                        ForEach(axisCards, id: \.id) { account in
                                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                                        }
                                    }
                                }
                                
                                // ICICI Credit Cards (must have "credit" in type or "****" in name for card number)
                                let iciciCards = viewModel.accounts.filter { account in
                                    let name = account.accountName?.lowercased() ?? ""
                                    let type = account.accountType?.lowercased() ?? ""
                                    return name.contains("icici") && 
                                           (type.contains("credit") || name.contains("****"))
                                }
                                if !iciciCards.isEmpty {
                                    Section(header: Text("ICICI Credit Cards")) {
                                        ForEach(iciciCards, id: \.id) { account in
                                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                                        }
                                    }
                                }
                                
                                // Other Credit Cards
                                let otherCards = viewModel.accounts.filter { account in
                                    let name = account.accountName?.lowercased() ?? ""
                                    let type = account.accountType?.lowercased() ?? ""
                                    return (type.contains("credit") || name.contains("axis") || name.contains("icici")) &&
                                           !name.contains("axis") && !name.contains("icici")
                                }
                                if !otherCards.isEmpty {
                                    Section(header: Text("Other Credit Cards")) {
                                        ForEach(otherCards, id: \.id) { account in
                                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                                        }
                                    }
                                }
                                
                                // Bank Accounts (exclude credit cards, mutual funds, investments, loans)
                                let bankAccounts = viewModel.accounts.filter { account in
                                    let name = account.accountName?.lowercased() ?? ""
                                    let type = account.accountType?.lowercased() ?? ""
                                    // Exclude if it's a credit card (has **** or credit type)
                                    let isCreditCard = type.contains("credit") || name.contains("****")
                                    return !isCreditCard &&
                                           !type.contains("mutual") &&
                                           !type.contains("investment") &&
                                           !type.contains("loan")
                                }
                                if !bankAccounts.isEmpty {
                                    Section(header: Text("Bank Accounts")) {
                                        ForEach(bankAccounts, id: \.id) { account in
                                            Text(account.wrappedAccountName).tag(account as CDAccount?)
                                        }
                                    }
                                }
                            }
                            
                            Picker("Category", selection: Binding(
                                get: { selectedCategoryFilter ?? "All" },
                                set: { selectedCategoryFilter = $0 == "All" ? nil : $0; selectedSubcategoryFilter = nil }
                            )) {
                                Text("All").tag("All")
                                ForEach(viewModel.allCategories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            if let parent = selectedCategoryFilter {
                                let subs = viewModel.subcategories(for: parent)
                                if !subs.isEmpty {
                                    Picker("Subcategory", selection: Binding<String?>(
                                        get: { selectedSubcategoryFilter },
                                        set: { selectedSubcategoryFilter = $0 }
                                    )) {
                                        Text("All").tag(nil as String?)
                                        ForEach(subs, id: \.self) { s in
                                            Text(s).tag(s as String?)
                                        }
                                    }
                                }
                            }
                            TextField("Description contains…", text: $searchKeywords)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }
                        if selectedAccountFilter != nil || selectedCategoryFilter != nil || !searchKeywords.trimmingCharacters(in: .whitespaces).isEmpty {
                            Section {
                                Button("Clear Filters") {
                                    selectedAccountFilter = nil
                                    selectedCategoryFilter = nil
                                    selectedSubcategoryFilter = nil
                                    searchKeywords = ""
                                }
                            }
                        }
                    }
                    .navigationTitle("Filters")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showingFilter = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Apply") { showingFilter = false } }
                    }
                }
            }
        }
    }
    
    private var hasActiveFilter: Bool {
        return selectedAccountFilter != nil || 
               selectedCategoryFilter != nil || 
               !searchKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var filteredTransactions: [CDTransaction] {
        var items = viewModel.recentTransactions
        
        // Filter out 0 amount transactions
        items = items.filter { $0.amount > 0 }
        
        // Filter by account
        if let accountFilter = selectedAccountFilter {
            items = items.filter { $0.account == accountFilter }
        }
        
        if let filter = selectedCategoryFilter {
            items = items.filter { txn in
                let raw = txn.wrappedCategory
                if let sub = selectedSubcategoryFilter { return raw == "\(filter)::\(sub)" }
                return raw == filter || raw.hasPrefix(filter + "::")
            }
        }
        let query = searchKeywords.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            let tokens = query.split(separator: " ")
            items = items.filter { txn in
                let hay = [txn.wrappedNotes, txn.account?.wrappedAccountName ?? "", txn.wrappedCategory]
                    .joined(separator: " ")
                    .lowercased()
                return tokens.allSatisfy { hay.contains($0) }
            }
        }
        return items
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