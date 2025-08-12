import SwiftUI

struct BudgetsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var showingAddBudget = false
    @State private var selectedMonth: Date = Date()
    
    var filteredBudgets: [Budget] {
        viewModel.budgets.filter {
            guard let budgetMonth = $0.month else { return false }
            let budgetComponents = Calendar.current.dateComponents([.year, .month], from: budgetMonth)
            let selectedComponents = Calendar.current.dateComponents([.year, .month], from: selectedMonth)
            return budgetComponents.year == selectedComponents.year && budgetComponents.month == selectedComponents.month
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    DatePicker("Select Month", selection: $selectedMonth, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .padding()
                    
                    if filteredBudgets.isEmpty {
                        ContentUnavailableView("No Budgets for this Month", systemImage: "calendar.badge.exclamationmark")
                            .padding()
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredBudgets) { budget in
                                BudgetRow(budget: budget, viewModel: viewModel)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddBudget = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBudget) {
                AddBudgetView(viewModel: viewModel)
            }
        }
    }
}

struct BudgetRow: View {
    let budget: Budget
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var spent: Double {
        viewModel.recentTransactions
            .filter { transaction in
                guard let budgetCategory = budget.category, let transactionCategory = transaction.category else { return false }
                guard let budgetMonth = budget.month, let transactionDate = transaction.date else { return false }
                
                let budgetComponents = Calendar.current.dateComponents([.year, .month], from: budgetMonth)
                let transactionComponents = Calendar.current.dateComponents([.year, .month], from: transactionDate)
                
                return budgetCategory == transactionCategory &&
                       budgetComponents.year == transactionComponents.year &&
                       budgetComponents.month == transactionComponents.month &&
                       !transaction.isCredit
            }
            .reduce(0) { $0 + $1.amount }
    }
    
    var progress: Double {
        budget.amount > 0 ? spent / budget.amount : 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(budget.category ?? "N/A")
                    .font(.headline)
                Spacer()
                Text(progress, format: .percent)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(progress > 1 ? .red : .secondary)
            }
            
            ProgressView(value: progress)
                .tint(progress > 1 ? .red : (progress > 0.75 ? .orange : .green))
            
            HStack {
                Text(spent, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .foregroundColor(.primary)
                Spacer()
                Text("of \(budget.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))")
                    .foregroundColor(.secondary)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
    }
}

struct AddBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var category: String = ""
    @State private var amount: String = ""
    @State private var month: Date = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Budget Details") {
                    Picker("Category", selection: $category) {
                        ForEach(viewModel.allCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    
                    DatePicker("Month", selection: $month, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amountValue = Double(amount) else { return }
                        viewModel.addBudget(category: category, amount: amountValue, month: month)
                        dismiss()
                    }
                }
            }
        }
    }
} 