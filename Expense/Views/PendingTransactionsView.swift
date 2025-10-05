import SwiftUI

// Lightweight chip for summary metrics (file-scoped to avoid nested generic bloat)
private struct SummaryChip: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

// Compact filter menu (funnel) extracted from toolbar
private struct FilterMenuView: View {
    @Binding var selectedDateRange: DateRangeOption
    @Binding var showingDatePicker: Bool
    @Binding var selectedBank: BankFilter
    let accounts: [CDAccount]
    let setPreferred: (_ bankKey: String, _ account: CDAccount?) -> Void
    
    var body: some View {
        Menu {
            // Date Range
            Picker("Date Range", selection: $selectedDateRange) {
                ForEach(DateRangeOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            if selectedDateRange == .custom {
                Button("Set Custom Range…") { showingDatePicker = true }
            }
            Divider()
            // Bank Filter
            Picker("Bank", selection: $selectedBank) {
                ForEach(BankFilter.allCases, id: \.self) { bank in
                    Text(bank.displayName).tag(bank)
                }
            }
            Divider()
            // Preferred Accounts
            Menu("Preferred Account (Axis)") {
                ForEach(accounts) { acc in
                    Button(acc.wrappedAccountName) { setPreferred("axis", acc) }
                }
                Button("Clear") { setPreferred("axis", nil) }
            }
            Menu("Preferred Account (ICICI)") {
                ForEach(accounts) { acc in
                    Button(acc.wrappedAccountName) { setPreferred("icici", acc) }
                }
                Button("Clear") { setPreferred("icici", nil) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
}

// Bulk approve menu extracted from toolbar
private struct BulkApproveMenuView: View {
    let selectedBank: BankFilter
    let accounts: [CDAccount]
    @Binding var selectedTransactions: Set<UUID>
    let preferredAccount: (BankFilter) -> CDAccount?
    let onApprove: (CDAccount) -> Void
    
    var body: some View {
        Menu {
            if selectedBank != .all, let pref = preferredAccount(selectedBank) {
                Button("Approve Selected → Preferred (\(pref.wrappedAccountName))") {
                    onApprove(pref)
                }
                Divider()
            }
            ForEach(accounts) { acc in
                Button("Approve Selected → \(acc.wrappedAccountName)") {
                    onApprove(acc)
                }
            }
        } label: {
            Image(systemName: "checkmark.circle")
        }
        .disabled(selectedTransactions.isEmpty || accounts.isEmpty)
    }
}
// Compact summary bar to reduce body complexity
private struct SummaryBar: View {
    let total: Int
    let visible: Int
    let duplicates: Int
    var body: some View {
        HStack(spacing: 12) {
            SummaryChip(title: "Total: \(total)", systemImage: "tray.full")
            SummaryChip(title: "Visible: \(visible)", systemImage: "eye")
            SummaryChip(title: "Duplicates: \(duplicates)", systemImage: "exclamationmark.triangle.fill")
        }
    }
}

// Minimal empty state view to simplify main body
private struct PendingEmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "No Transactions Found",
            systemImage: "tray",
            description: Text("Select a date range and bank, then tap 'Load from Emails' to fetch transactions.")
        )
    }
}

// Lightweight list view extracted to improve type-checking performance
private struct PendingListView: View {
    let transactions: [PendingTransactionItem]
    @Binding var selected: Set<UUID>
    let isDuplicate: (PendingTransactionItem) -> Bool
    let viewModel: ExpenseViewModel
    let inferBank: (PendingTransactionItem) -> BankFilter
    let resolvePreferredAccount: (BankFilter) -> CDAccount?
    let groupedAccounts: [(title: String, accounts: [CDAccount])]
    
    var body: some View {
        List {
            ForEach(transactions) { transaction in
                VStack(alignment: .leading, spacing: 8) {
                    PendingTransactionRowView(
                        transaction: transaction,
                        isSelected: selected.contains(transaction.id),
                        isDuplicate: isDuplicate(transaction),
                        onSelectionChanged: { isSelected in
                            if isSelected { selected.insert(transaction.id) } else { selected.remove(transaction.id) }
                        }
                    )
                    HStack(spacing: 12) {
                        let bank = inferBank(transaction)
                        if let pref = resolvePreferredAccount(bank) {
                            Button {
                                viewModel.approvePendingTransaction(id: transaction.id, toAccount: pref)
                            } label: {
                                Label("Quick Approve", systemImage: "checkmark.circle").foregroundColor(.green)
                            }
                        }
                        Menu {
                            ForEach(groupedAccounts, id: \.title) { group in
                                Section(header: Text(group.title)) {
                                    ForEach(group.accounts) { acc in
                                        Button(acc.wrappedAccountName) {
                                            viewModel.approvePendingTransaction(id: transaction.id, toAccount: acc)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                        }
                        Button(role: .destructive) {
                            viewModel.removePendingTransaction(id: transaction.id)
                        } label: {
                            Label("Reject", systemImage: "xmark.circle.fill")
                        }
                    }
                    .font(.callout)
                    .padding(.top, 2)
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Date Range Selection
enum DateRangeOption: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case custom = "Custom Range"
    
    var displayName: String {
        return self.rawValue
    }
}

// MARK: - Bank Selection
enum BankFilter: String, CaseIterable {
    case all = "All Banks"
    case axis = "Axis Bank"
    case icici = "ICICI Bank"
    
    var displayName: String {
        return self.rawValue
    }
}

struct PendingTransactionsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var selectedDateRange: DateRangeOption = .today
    @State private var selectedBank: BankFilter = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var isLoadingTransactions = false
    @State private var selectedTransactions: Set<UUID> = []
    @State private var showingDatePicker = false
    @State private var showingClearAlert = false
    @State private var showingClearAllAlert = false
    
    // Summary counts
    private var totalPendingCount: Int { viewModel.pendingTransactions.count }
    private var visibleCount: Int { filteredTransactions.count }
    private var duplicateVisibleCount: Int { filteredTransactions.filter { isDuplicateTransaction($0) }.count }

    // Infer bank for a pending item based on content
    private func inferBank(for item: PendingTransactionItem) -> BankFilter {
        let text = (item.subject + "\n" + item.body).lowercased()
        if text.contains("axis") { return .axis }
        if text.contains("icici") { return .icici }
        return selectedBank == .all ? .axis : selectedBank // default to current filter or axis
    }
    
    // Pre-formatted labels replaced by SummaryBar view

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Summary chips
                summaryArea
                // Transaction List
                listSection
            }
        }
        .navigationTitle("Pending Transactions")
        .toolbar {
            // Filters (funnel button)
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    // Date Range
                    Picker("Date Range", selection: $selectedDateRange) {
                        ForEach(DateRangeOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    if selectedDateRange == .custom {
                        Button("Set Custom Range…") { showingDatePicker = true }
                    }
                    Divider()
                    // Bank Filter
                    Picker("Bank", selection: $selectedBank) {
                        ForEach(BankFilter.allCases, id: \.self) { bank in
                            Text(bank.displayName).tag(bank)
                        }
                    }
                    Divider()
                    // Preferred Accounts (persist keys locally)
                    Menu("Preferred Account (Axis)") {
                        ForEach(viewModel.accounts) { acc in
                            Button(acc.wrappedAccountName) {
                                if let id = acc.id { UserDefaults.standard.set(id.uuidString, forKey: "PreferredAccount_axis") }
                            }
                        }
                        Button("Clear") { UserDefaults.standard.removeObject(forKey: "PreferredAccount_axis") }
                    }
                    Menu("Preferred Account (ICICI)") {
                        ForEach(viewModel.accounts) { acc in
                            Button(acc.wrappedAccountName) {
                                if let id = acc.id { UserDefaults.standard.set(id.uuidString, forKey: "PreferredAccount_icici") }
                            }
                        }
                        Button("Clear") { UserDefaults.standard.removeObject(forKey: "PreferredAccount_icici") }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.resetEmailIngestionState()
                } label: {
                    Label("Reset Email Ingestion", systemImage: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset Email Ingestion State")
                .help("Clears processed email history so past messages can be reprocessed")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: loadTransactionsFromEmails) {
                    if isLoadingTransactions { ProgressView() } else { Image(systemName: "envelope.arrow.triangle.branch") }
                }
                .accessibilityLabel("Load from Emails")
            }
            // Select All Visible
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    selectedTransactions = Set(filteredTransactions.map { $0.id })
                } label: {
                    Image(systemName: "checkmark.circle.badge.plus")
                }
                .disabled(filteredTransactions.isEmpty)
                .accessibilityLabel("Select All Visible")
            }
            // Bulk Approve Selected (inline menu)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if selectedBank != .all, let pref = preferredAccount(for: selectedBank) {
                        Button("Approve Selected → Preferred (\(pref.wrappedAccountName))") {
                            let ids = selectedTransactions
                            for id in ids { viewModel.approvePendingTransaction(id: id, toAccount: pref) }
                            selectedTransactions.removeAll()
                        }
                        Divider()
                    }
                    ForEach(groupedAccounts, id: \.title) { group in
                        Section(header: Text(group.title)) {
                            ForEach(group.accounts) { acc in
                                Button(acc.wrappedAccountName) {
                                    let ids = selectedTransactions
                                    for id in ids { viewModel.approvePendingTransaction(id: id, toAccount: acc) }
                                    selectedTransactions.removeAll()
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .disabled(selectedTransactions.isEmpty || viewModel.accounts.isEmpty)
            }
            // Approve All Visible (choose account)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if selectedBank != .all, let pref = preferredAccount(for: selectedBank) {
                        Button("Approve All Visible → Preferred (\(pref.wrappedAccountName))") {
                            approveAllVisible(to: pref)
                        }
                        Divider()
                    }
                    ForEach(groupedAccounts, id: \.title) { group in
                        Section(header: Text(group.title)) {
                            ForEach(group.accounts) { acc in
                                Button(acc.wrappedAccountName) {
                                    approveAllVisible(to: acc)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "checkmark.seal")
                }
                .disabled(filteredTransactions.isEmpty || viewModel.accounts.isEmpty)
                .accessibilityLabel("Approve All Visible")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { showingClearAlert = true } label: { Image(systemName: "trash") }
                .disabled(selectedTransactions.isEmpty)
                .accessibilityLabel("Reject Selected")
                .help("Reject and remove selected pending transactions")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { showingClearAllAlert = true } label: { Image(systemName: "trash.slash") }
                .disabled(viewModel.pendingTransactions.isEmpty)
                .accessibilityLabel("Delete All Pending")
            }
            // Select All / Deselect All (bottom bar)
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Select All") {
                    selectedTransactions = Set(filteredTransactions.map { $0.id })
                }
                .disabled(filteredTransactions.isEmpty)
                Spacer()
                Button("Deselect All") {
                    selectedTransactions.removeAll()
                }
                .disabled(selectedTransactions.isEmpty)
            }
        }
        .alert("Reject Selected", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reject", role: .destructive) {
                clearCurrentSelection()
            }
        } message: {
            Text("This will reject and remove all selected pending transactions. This action cannot be undone.")
        }
        .alert("Delete All Pending", isPresented: $showingClearAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                clearAllPending()
            }
        } message: {
            Text("This will delete all currently loaded pending transactions (") + Text("\(viewModel.pendingTransactions.count)") + Text("). This cannot be undone.")
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                Form {
                    Section("Custom Date Range") {
                        DatePicker("From", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("To", selection: $customEndDate, displayedComponents: .date)
                    }
                }
                .navigationTitle("Filters")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingDatePicker = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { showingDatePicker = false } }
                }
            }
        }
        // Keep the view builder properties inside the view struct
    }
    
    // MARK: - Sections
    @ViewBuilder
    private var listSection: some View {
        let items = filteredTransactions
        if items.isEmpty && !isLoadingTransactions {
            PendingEmptyStateView()
        } else {
            PendingListView(
                transactions: items,
                selected: $selectedTransactions,
                isDuplicate: isDuplicateTransaction,
                viewModel: viewModel,
                inferBank: { item in inferBank(for: item) },
                resolvePreferredAccount: { bank in preferredAccount(for: bank) },
                groupedAccounts: groupedAccounts
            )
        }
    }
    
    // Summary extracted to reduce type-check load
    @ViewBuilder
    private var summaryArea: some View {
        if totalPendingCount > 0 {
            SummaryBar(total: totalPendingCount, visible: visibleCount, duplicates: duplicateVisibleCount)
                .padding(.horizontal)
                .padding(.vertical, 8)
        } else {
            EmptyView()
        }
    }
    
    // Helper to group accounts by type
    private var groupedAccounts: [(title: String, accounts: [CDAccount])] {
        let creditCards = viewModel.accounts.filter { account in
            let name = account.accountName?.lowercased() ?? ""
            let type = account.accountType?.lowercased() ?? ""
            return type.contains("credit") || name.contains("axis") || name.contains("icici")
        }
        
        let axisCards = creditCards.filter { $0.accountName?.lowercased().contains("axis") ?? false }
        let iciciCards = creditCards.filter { $0.accountName?.lowercased().contains("icici") ?? false }
        let otherCards = creditCards.filter { 
            let name = $0.accountName?.lowercased() ?? ""
            return !name.contains("axis") && !name.contains("icici")
        }
        
        let banks = viewModel.accounts.filter { account in
            let name = account.accountName?.lowercased() ?? ""
            let type = account.accountType?.lowercased() ?? ""
            return !type.contains("credit") && !name.contains("axis") && !name.contains("icici")
        }
        
        var groups: [(String, [CDAccount])] = []
        if !axisCards.isEmpty { groups.append(("Axis Credit Cards", axisCards)) }
        if !iciciCards.isEmpty { groups.append(("ICICI Credit Cards", iciciCards)) }
        if !otherCards.isEmpty { groups.append(("Other Credit Cards", otherCards)) }
        if !banks.isEmpty { groups.append(("Bank Accounts", banks)) }
        
        return groups
    }
    
    // Resolve preferred account for a bank using stored UUIDs
    private func preferredAccount(for bank: BankFilter) -> CDAccount? {
        let key = (bank == .axis) ? "PreferredAccount_axis" : "PreferredAccount_icici"
        guard let idStr = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: idStr) else { return nil }
        return viewModel.accounts.first { acct in
            if let aid = acct.id { return aid == uuid }
            return false
        }
    }
    
    // Approve all currently visible (filtered) items to a chosen account
    private func approveAllVisible(to account: CDAccount) {
        let items = filteredTransactions
        for item in items {
            viewModel.approvePendingTransaction(id: item.id, toAccount: account)
        }
        selectedTransactions.removeAll()
    }
    
    // MARK: - Computed Properties
    
    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedDateRange {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, now)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let startOfYesterday = calendar.startOfDay(for: yesterday)
            let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: startOfYesterday) ?? now
            return (startOfYesterday, endOfYesterday)
        case .last7Days:
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            let startOfSevenDaysAgo = calendar.startOfDay(for: sevenDaysAgo)
            return (startOfSevenDaysAgo, now)
        case .last30Days:
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            let startOfThirtyDaysAgo = calendar.startOfDay(for: thirtyDaysAgo)
            return (startOfThirtyDaysAgo, now)
        case .custom:
            return (calendar.startOfDay(for: customStartDate), 
                   calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate)) ?? customEndDate)
        }
    }
    
    private var filteredTransactions: [PendingTransactionItem] {
        return viewModel.pendingTransactions.filter { transaction in
            // Date filter
            let dateInRange = transaction.date >= dateRange.start && transaction.date <= dateRange.end
            
            // Bank filter
            let bankMatches: Bool
            switch selectedBank {
            case .all:
                bankMatches = true
            case .axis:
                bankMatches = transaction.subject.lowercased().contains("axis") || 
                             transaction.body.lowercased().contains("axis")
            case .icici:
                bankMatches = transaction.subject.lowercased().contains("icici") || 
                             transaction.body.lowercased().contains("icici")
            }
            
            return dateInRange && bankMatches
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadTransactionsFromEmails() {
        guard !isLoadingTransactions else { return }
        
        isLoadingTransactions = true
        
        // Start fresh for this session per your request
        viewModel.pendingTransactions.removeAll()
        selectedTransactions.removeAll()
        
        let since = dateRange.start
        var totalQueued = 0
        let group = DispatchGroup()
        
        // Axis (Outlook)
        if selectedBank == .all || selectedBank == .axis {
            group.enter()
            viewModel.fetchOutlookEmails(since: since, sender: "alerts@axisbank.com") { result in
                defer { group.leave() }
                switch result {
                case .failure(let err):
                    print("[PendingTransactions] Outlook fetch error: \(err.localizedDescription)")
                case .success:
                    let messages = viewModel.fetchedEmails
                    var queued = 0
                    for msg in messages {
                        let bodyText: String = (msg.body?.content ?? msg.bodyPreview) ?? ""
                        if let parsed = try? EmailParser.parse(subject: msg.subject, body: bodyText) {
                            let item = PendingTransactionItem(
                                subject: parsed.subject,
                                body: parsed.body,
                                amount: parsed.amount,
                                date: parsed.date,
                                isCredit: parsed.isCredit,
                                suggestedCategory: parsed.suggestedCategory,
                                notes: parsed.description
                            )
                            viewModel.addPendingTransaction(item)
                            queued += 1
                        }
                    }
                    totalQueued += queued
                    print("[PendingTransactions] Axis (Outlook) queued \(queued)")
                }
            }
        }
        
        // ICICI (Gmail)
        if selectedBank == .all || selectedBank == .icici {
            if GmailService.shared.isSignedIn {
                group.enter()
                GmailService.shared.fetchICICIMessages(since: since) { result in
                    defer { group.leave() }
                    switch result {
                    case .failure(let err):
                        print("[PendingTransactions] Gmail fetch error: \(err.localizedDescription)")
                    case .success(let msgs):
                        var queued = 0
                        for (subject, body, _) in msgs {
                            if let parsed = try? EmailParser.parse(subject: subject, body: body) {
                                let item = PendingTransactionItem(
                                    subject: parsed.subject,
                                    body: parsed.body,
                                    amount: parsed.amount,
                                    date: parsed.date,
                                    isCredit: parsed.isCredit,
                                    suggestedCategory: parsed.suggestedCategory,
                                    notes: parsed.description
                                )
                                viewModel.addPendingTransaction(item)
                                queued += 1
                            }
                        }
                        totalQueued += queued
                        print("[PendingTransactions] ICICI (Gmail) queued \(queued)")
                    }
                }
            } else {
                print("[PendingTransactions] Gmail not signed in; skipping ICICI fetch")
            }
        }
        
        group.notify(queue: .main) {
            self.isLoadingTransactions = false
            print("[PendingTransactions] Loaded \(totalQueued) transactions from emails")
            let visible = self.filteredTransactions.count
            print("[PendingTransactions] After filters (date/bank) showing \(visible) transactions")
        }
    }
    
    private func isDuplicateTransaction(_ item: PendingTransactionItem) -> Bool {
        let existingTransactions = viewModel.recentTransactions
        return existingTransactions.contains { transaction in
            let amountMatches = abs(transaction.amount - item.amount) < 0.01
            let dateMatches = Calendar.current.isDate(transaction.wrappedDate, inSameDayAs: item.date)
            let creditMatches = transaction.isCredit == item.isCredit
            return amountMatches && dateMatches && creditMatches
        }
    }
    
    private func clearCurrentSelection() {
        // Remove selected transactions from the pending list
        let transactionsToRemove = selectedTransactions
        viewModel.pendingTransactions.removeAll { transaction in
            transactionsToRemove.contains(transaction.id)
        }
        
        // Clear the selection
        selectedTransactions.removeAll()
        
        // Save the updated pending transactions
        viewModel.savePendingTransactions()
        
        print("[PendingTransactions] Cleared \(transactionsToRemove.count) selected transactions")
    }
    
    private func clearAllPending() {
        viewModel.pendingTransactions.removeAll()
        viewModel.savePendingTransactions()
        selectedTransactions.removeAll()
        print("[PendingTransactions] Deleted all pending transactions")
    }
}

// MARK: - Transaction Row View
struct PendingTransactionRowView: View {
    let transaction: PendingTransactionItem
    let isSelected: Bool
    let isDuplicate: Bool
    let onSelectionChanged: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection Checkbox
            Button(action: {
                onSelectionChanged(!isSelected)
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title2)
            }
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.subject)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Duplicate Indicator
                    if isDuplicate {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Duplicate")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Predicted category (rules/AI preview)
                HStack(spacing: 6) {
                    let predictedRaw = AICategorizationManager.shared.categorizeTransaction(
                        title: transaction.subject,
                        amount: transaction.amount,
                        isCredit: transaction.isCredit,
                        notes: transaction.notes ?? String(transaction.body.prefix(120))
                    )
                    let predictedDisplay = TransactionCategory(rawValue: predictedRaw).displayName
                    Label("\(predictedDisplay)", systemImage: "tag")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(transaction.amount, format: .currency(code: CurrencySettings.shared.selectedCurrency.rawValue))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(transaction.isCredit ? .green : .red)
                    
                    Spacer()
                    
                    Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(transaction.body.prefix(100) + (transaction.body.count > 100 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}


