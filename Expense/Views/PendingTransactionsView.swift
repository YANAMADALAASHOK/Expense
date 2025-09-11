import SwiftUI

struct PendingTransactionsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var selectedAccount: CDAccount?
    @State private var showingTransferSheet = false
    @State private var transferFromId: UUID?
    @State private var transferToId: UUID?
    @State private var pendingTransferItem: PendingTransactionItem?

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
                        HStack(spacing: 12) {
                            if TransactionCategory(rawValue: item.suggestedCategory) == .selfTransfer {
                                Button {
                                    pendingTransferItem = item
                                    transferFromId = nil
                                    transferToId = nil
                                    showingTransferSheet = true
                                } label: {
                                    Label("Approve Transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.green)
                                        .cornerRadius(8)
                                }
                            } else {
                                Menu {
                                    ForEach(viewModel.accounts) { acc in
                                        Button(acc.wrappedAccountName) { viewModel.approvePendingTransaction(id: item.id, toAccount: acc) }
                                    }
                                } label: {
                                    Label("Approve", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.green)
                                        .cornerRadius(8)
                                }
                            }
                            Button(role: .destructive) { 
                                viewModel.removePendingTransaction(id: item.id) 
                            } label: { 
                                Label("Decline", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.red)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Pending Transactions")
        .sheet(isPresented: $showingTransferSheet) {
            NavigationView {
                Form {
                    Section("Transfer Accounts") {
                        Picker("From", selection: $transferFromId) {
                            Text("Select Source").tag(nil as UUID?)
                            ForEach(viewModel.accounts) { acc in
                                Text(acc.wrappedAccountName).tag(acc.id as UUID?)
                            }
                        }
                        Picker("To", selection: $transferToId) {
                            Text("Select Destination").tag(nil as UUID?)
                            ForEach(viewModel.accounts) { acc in
                                Text(acc.wrappedAccountName).tag(acc.id as UUID?)
                            }
                        }
                    }
                }
                .navigationTitle("Approve Transfer")
                .onAppear { 
                    print("[PendingTransfers] Sheet appeared for item=\(String(describing: pendingTransferItem?.id)) amount=\(pendingTransferItem?.amount ?? -1)")
                }
                .onChange(of: transferFromId) { _, newVal in
                    print("[PendingTransfers] Selected From id=\(String(describing: newVal))")
                }
                .onChange(of: transferToId) { _, newVal in
                    print("[PendingTransfers] Selected To id=\(String(describing: newVal))")
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingTransferSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            print("[PendingTransfers] Save tapped with fromId=\(String(describing: transferFromId)) toId=\(String(describing: transferToId)) pendingId=\(String(describing: pendingTransferItem?.id))")
                            guard let item = pendingTransferItem else {
                                print("[PendingTransfers] No pending item in state")
                                return
                            }
                            guard let fromId = transferFromId, let toId = transferToId, fromId != toId else {
                                print("[PendingTransfers] Invalid From/To selection")
                                return
                            }
                            guard let from = viewModel.accounts.first(where: { $0.id == fromId }),
                                  let to = viewModel.accounts.first(where: { $0.id == toId }) else {
                                print("[PendingTransfers] Unable to resolve accounts from IDs")
                                return
                            }
                            let notes = item.notes ?? item.subject
                            print("[PendingTransfers] Executing transfer amount=\(item.amount) from=\(from.wrappedAccountName) to=\(to.wrappedAccountName) date=\(item.date)")
                            viewModel.transferBetweenAccounts(amount: item.amount, from: from, to: to, notes: notes, date: item.date)
                            viewModel.removePendingTransaction(id: item.id)
                            showingTransferSheet = false
                        }
                    }
                }
            }
        }
    }
}


