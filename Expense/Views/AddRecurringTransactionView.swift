import SwiftUI
import CoreData

// MARK: - Add Recurring Transaction View
struct AddRecurringTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @StateObject private var recurringManager = RecurringTransactionManager()
    
    @State private var title: String = ""
    @State private var amount: String = ""
    @State private var selectedCategory: TransactionCategory = .other
    @State private var selectedAccount: CDAccount?
    @State private var notes: String = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var startDate = Date()
    @State private var endDate: Date?
    @State private var hasEndDate = false
    @State private var selectedType: RecurringTransactionType = .expense
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    headerSection
                    formFieldsSection
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Add Recurring Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveRecurringTransaction() }
                        .disabled(title.isEmpty || amount.isEmpty || selectedAccount == nil)
                }
            }
        }
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.primary)
            
            Text("Add Recurring Transaction")
                .font(DesignSystem.Typography.headlineMedium)
                .foregroundColor(DesignSystem.Colors.onSurface)
            
            Text("Set up automatic transactions that repeat on schedule")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DesignSystem.Spacing.xl)
    }
    
    @ViewBuilder
    private var formFieldsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Title
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Title")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                TextField("Enter transaction title", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Amount
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Amount")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                TextField("0.00", text: $amount)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
            }
            
            // Category
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Category")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Menu {
                    ForEach(TransactionCategory.allCases, id: \.self) { category in
                        Button(category.displayName) {
                            selectedCategory = category
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedCategory.displayName)
                            .foregroundColor(DesignSystem.Colors.onSurface)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                    }
                    .padding()
                    .background(DesignSystem.Colors.surfaceVariant)
                    .cornerRadius(DesignSystem.CornerRadius.sm)
                }
            }
            
            // Account Selection
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Account")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Menu {
                    ForEach(viewModel.accounts, id: \.self) { account in
                        Button(account.wrappedAccountName) {
                            selectedAccount = account
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedAccount?.wrappedAccountName ?? "Select Account")
                            .foregroundColor(DesignSystem.Colors.onSurface)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                    }
                    .padding()
                    .background(DesignSystem.Colors.surfaceVariant)
                    .cornerRadius(DesignSystem.CornerRadius.sm)
                }
            }
            
            // Frequency
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Frequency")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Picker("Frequency", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // Notes
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Notes (Optional)")
                    .font(DesignSystem.Typography.titleSmall)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                TextField("Add notes...", text: $notes)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }
    
    private func saveRecurringTransaction() {
        guard let amountValue = Double(amount),
              let account = selectedAccount else { return }
        
        let recurringTransaction = RecurringTransaction(
            title: title,
            amount: amountValue,
            category: selectedCategory.rawValue,
            accountId: account.id?.uuidString ?? "",
            frequency: frequency,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            notes: notes.isEmpty ? nil : notes,
            type: selectedType
        )
        
        recurringManager.addRecurringTransaction(recurringTransaction)
        dismiss()
    }
}

// MARK: - Recurring Transactions List View
struct RecurringTransactionsView: View {
    @StateObject private var recurringManager = RecurringTransactionManager()
    @State private var showingAddTransaction = false
    
    var body: some View {
        NavigationView {
            List {
                if recurringManager.recurringTransactions.isEmpty {
                    ContentUnavailableView("No Recurring Transactions", systemImage: "repeat.circle")
                } else {
                    ForEach(recurringManager.recurringTransactions) { transaction in
                        RecurringTransactionRow(transaction: transaction)
                    }
                    .onDelete(perform: deleteTransactions)
                }
            }
            .navigationTitle("Recurring Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTransaction = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddRecurringTransactionView()
            }
        }
    }
    
    private func deleteTransactions(offsets: IndexSet) {
        for index in offsets {
            let transaction = recurringManager.recurringTransactions[index]
            recurringManager.deleteRecurringTransaction(transaction)
            NotificationManager.shared.cancelBillReminder(for: transaction)
        }
    }
}

// MARK: - Recurring Transaction Row
struct RecurringTransactionRow: View {
    let transaction: RecurringTransaction
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(transaction.title)
                    .font(DesignSystem.Typography.titleMedium)
                    .foregroundColor(DesignSystem.Colors.onSurface)
                
                Spacer()
                
                Text(transaction.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(DesignSystem.Typography.titleSmall)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.type == RecurringTransactionType.expense ? DesignSystem.Colors.error : DesignSystem.Colors.success)
            }
            
            HStack {
                Text(transaction.frequency.displayName)
                    .font(DesignSystem.Typography.labelSmall)
                    .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                
                Spacer()
                
                Text("Next: \(transaction.nextDueDate, style: .date)")
                    .font(DesignSystem.Typography.labelSmall)
                    .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
