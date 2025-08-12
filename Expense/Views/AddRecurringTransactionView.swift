import SwiftUI
import CoreData

// MARK: - Add Recurring Transaction View
struct AddRecurringTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ExpenseViewModel
    @StateObject private var recurringManager = RecurringTransactionManager()
    @StateObject private var aiCategorizationManager = AICategorizationManager.shared
    
    @State private var title = ""
    @State private var amount = ""
    @State private var selectedCategory = "Other"
    @State private var selectedAccountId = ""
    @State private var selectedFrequency = RecurrenceFrequency.monthly
    @State private var startDate = Date()
    @State private var endDate: Date?
    @State private var notes = ""
    @State private var selectedType = RecurringTransactionType.expense
    @State private var showingEndDatePicker = false
    @State private var showingCategorySuggestions = false
    @State private var suggestedCategories: [String] = []
    
    init(context: NSManagedObjectContext) {
        let viewModel = ExpenseViewModel(context: context)
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header
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
                    
                    // Form Fields
                    VStack(spacing: DesignSystem.Spacing.md) {
                        // Transaction Type
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Transaction Type")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            Picker("Type", selection: $selectedType) {
                                ForEach(RecurringTransactionType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        // Title
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Title")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            TextField("Enter transaction title", text: $title)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: title) { newTitle in
                                    updateCategorySuggestions()
                                }
                        }
                        
                        // Amount
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Amount")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            TextField("0.00", text: $amount)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                                .onChange(of: amount) { _ in
                                    updateCategorySuggestions()
                                }
                        }
                        
                        // Category with AI suggestions
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Category")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            HStack {
                                Menu {
                                    ForEach(TransactionCategory.allCases, id: \.self) { category in
                                        Button(category.displayName) {
                                            selectedCategory = category.rawValue
                                        }
                                    }
                                    
                                    if !suggestedCategories.isEmpty {
                                        Divider()
                                        ForEach(suggestedCategories, id: \.self) { suggestion in
                                            Button("AI: \(suggestion)") {
                                                selectedCategory = suggestion
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedCategory)
                                            .foregroundColor(DesignSystem.Colors.onSurface)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                                    }
                                    .padding()
                                    .background(DesignSystem.Colors.surfaceVariant)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                                }
                                
                                if !suggestedCategories.isEmpty {
                                    Button(action: { showingCategorySuggestions = true }) {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundColor(DesignSystem.Colors.warning)
                                    }
                                }
                            }
                        }
                        
                        // Account
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Account")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            if viewModel.accounts.isEmpty {
                                Text("No accounts available")
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(DesignSystem.Colors.surfaceVariant)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            } else {
                                Menu {
                                    ForEach(viewModel.accounts) { account in
                                        Button(account.wrappedAccountName) {
                                            selectedAccountId = account.id?.uuidString ?? ""
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedAccountName)
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
                        }
                        
                        // Frequency
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Frequency")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            Menu {
                                ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                                    Button(frequency.displayName) {
                                        selectedFrequency = frequency
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedFrequency.displayName)
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
                        
                        // Start Date
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Start Date")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                                .datePickerStyle(CompactDatePickerStyle())
                                .padding()
                                .background(DesignSystem.Colors.surfaceVariant)
                                .cornerRadius(DesignSystem.CornerRadius.sm)
                        }
                        
                        // End Date (Optional)
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            HStack {
                                Text("End Date (Optional)")
                                    .font(DesignSystem.Typography.titleSmall)
                                    .foregroundColor(DesignSystem.Colors.onSurface)
                                
                                Spacer()
                                
                                Toggle("", isOn: $showingEndDatePicker)
                                    .labelsHidden()
                            }
                            
                            if showingEndDatePicker {
                                DatePicker("End Date", selection: Binding(
                                    get: { endDate ?? Date() },
                                    set: { endDate = $0 }
                                ), displayedComponents: .date)
                                .datePickerStyle(CompactDatePickerStyle())
                                .padding()
                                .background(DesignSystem.Colors.surfaceVariant)
                                .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                        
                        // Notes
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Notes (Optional)")
                                .font(DesignSystem.Typography.titleSmall)
                                .foregroundColor(DesignSystem.Colors.onSurface)
                            
                            TextField("Add notes", text: $notes, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(3...6)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Action Buttons
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Button(action: saveRecurringTransaction) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create Recurring Transaction")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .primaryButtonStyle()
                        }
                        .disabled(!isFormValid)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .secondaryButtonStyle()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Recurring Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCategorySuggestions) {
                CategorySuggestionsView(
                    suggestions: suggestedCategories,
                    selectedCategory: $selectedCategory
                )
            }
            .onAppear {
                if let firstAccount = viewModel.accounts.first {
                    selectedAccountId = firstAccount.id?.uuidString ?? ""
                }
            }
        }
    }
    
    private var selectedAccountName: String {
        if let account = viewModel.accounts.first(where: { $0.id?.uuidString == selectedAccountId }) {
            return account.wrappedAccountName
        }
        return "Select Account"
    }
    
    private var isFormValid: Bool {
        !title.isEmpty && 
        !amount.isEmpty && 
        Double(amount) != nil && 
        !selectedAccountId.isEmpty
    }
    
    private func updateCategorySuggestions() {
        guard !title.isEmpty, let amountValue = Double(amount) else {
            suggestedCategories = []
            return
        }
        
        suggestedCategories = aiCategorizationManager.suggestCategories(
            for: title,
            amount: amountValue
        ).filter { $0 != selectedCategory }
    }
    
    private func saveRecurringTransaction() {
        guard let amountValue = Double(amount) else { return }
        
        let recurringTransaction = RecurringTransaction(
            title: title,
            amount: amountValue,
            category: selectedCategory,
            accountId: selectedAccountId,
            frequency: selectedFrequency,
            startDate: startDate,
            endDate: showingEndDatePicker ? endDate : nil,
            notes: notes.isEmpty ? nil : notes,
            type: selectedType
        )
        
        recurringManager.addRecurringTransaction(recurringTransaction)
        
        // Schedule notification reminder
        NotificationManager.shared.scheduleBillReminder(for: recurringTransaction)
        
        dismiss()
    }
}

// MARK: - Category Suggestions View
struct CategorySuggestionsView: View {
    let suggestions: [String]
    @Binding var selectedCategory: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("AI Suggestions") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(action: {
                            selectedCategory = suggestion
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(DesignSystem.Colors.warning)
                                
                                Text(suggestion)
                                    .foregroundColor(DesignSystem.Colors.onSurface)
                                
                                Spacer()
                                
                                if selectedCategory == suggestion {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(DesignSystem.Colors.primary)
                                }
                            }
                        }
                    }
                }
                
                Section("All Categories") {
                    ForEach(TransactionCategory.allCases, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category.rawValue
                            dismiss()
                        }) {
                            HStack {
                                Text(category.displayName)
                                    .foregroundColor(DesignSystem.Colors.onSurface)
                                
                                Spacer()
                                
                                if selectedCategory == category.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(DesignSystem.Colors.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Recurring Transactions List View
struct RecurringTransactionsListView: View {
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
                AddRecurringTransactionView(context: PersistenceController.shared.container.viewContext)
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
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(transaction.title)
                        .font(DesignSystem.Typography.titleSmall)
                        .foregroundColor(DesignSystem.Colors.onSurface)
                    
                    Text(transaction.category)
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
                    Text(transaction.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        .font(DesignSystem.Typography.titleSmall)
                        .fontWeight(.semibold)
                        .foregroundColor(transaction.type == RecurringTransactionType.expense ? DesignSystem.Colors.error : DesignSystem.Colors.success)
                    
                    Text(transaction.frequency.displayName)
                        .font(DesignSystem.Typography.labelSmall)
                        .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                }
            }
            
            HStack {
                Text("Next: \(transaction.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(DesignSystem.Typography.labelSmall)
                    .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                
                Spacer()
                
                if !transaction.isActive {
                    Text("Inactive")
                        .font(DesignSystem.Typography.labelSmall)
                        .foregroundColor(DesignSystem.Colors.error)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .background(DesignSystem.Colors.error.opacity(0.1))
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
} 