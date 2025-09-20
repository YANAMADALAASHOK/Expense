import SwiftUI

struct InsuranceView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingAddInsurance = false
    @State private var editingInsurance: InsurancePolicy?
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Insurance")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAddInsurance = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .onAppear {
                    loadPolicies()
                    processInsurancePremiums()
                }
        }
        .sheet(isPresented: $showingAddInsurance) {
            addInsuranceSheet
        }
        .sheet(item: $editingInsurance) { policy in
            editInsuranceSheet(for: policy)
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        List {
            if viewModel.insurancePolicies.isEmpty {
                emptyStateView
            } else {
                policiesListView
            }
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Insurance Policies",
            systemImage: "shield.checkered",
            description: Text("Add your insurance policies to track monthly premiums automatically.")
        )
    }
    
    @ViewBuilder
    private var policiesListView: some View {
        ForEach(viewModel.insurancePolicies) { policy in
            InsurancePolicyRow(
                policy: policy,
                accounts: viewModel.accounts,
                currencyCode: currencySettings.selectedCurrency.rawValue
            )
            .contentShape(Rectangle())
            .onTapGesture { editingInsurance = policy }
            .swipeActions(edge: .trailing) {
                Button("Edit") { editingInsurance = policy }
                    .tint(.orange)
                Button("Delete", role: .destructive) { deletePolicy(policy) }
            }
        }
    }
    
    private var addInsuranceSheet: some View {
        AddInsurancePolicyView(
            accounts: viewModel.accounts,
            initial: nil,
            onSave: addPolicy,
            onDelete: nil
        )
    }
    
    private func editInsuranceSheet(for policy: InsurancePolicy) -> some View {
        AddInsurancePolicyView(
            accounts: viewModel.accounts,
            initial: policy,
            onSave: updatePolicy,
            onDelete: deletePolicy
        )
    }
    
    // Insurance management using shared manager
    private func processInsurancePremiums() {
        let insuranceManager = InsuranceManager.shared
        insuranceManager.processInsurancePremiums(context: viewModel.viewContext, accounts: viewModel.accounts)
    }
    
    private func addPolicy(_ policy: InsurancePolicy) {
        viewModel.insurancePolicies.append(policy)
        savePolicies()
    }
    
    private func updatePolicy(_ policy: InsurancePolicy) {
        if let index = viewModel.insurancePolicies.firstIndex(where: { $0.id == policy.id }) {
            viewModel.insurancePolicies[index] = policy
            savePolicies()
        }
    }
    
    private func deletePolicy(_ policy: InsurancePolicy) {
        viewModel.insurancePolicies.removeAll { $0.id == policy.id }
        savePolicies()
        
        // Clean up the last processed date
        let lastProcessedKey = "insurance_\(policy.id)_lastProcessed"
        UserDefaults.standard.removeObject(forKey: lastProcessedKey)
    }
    
    private func savePolicies() {
        let insuranceManager = InsuranceManager.shared
        insuranceManager.savePolicies(viewModel.insurancePolicies)
    }
    
    private func loadPolicies() {
        let insuranceManager = InsuranceManager.shared
        viewModel.insurancePolicies = insuranceManager.loadPolicies()
    }
}

// Simple, focused insurance policy row
private struct InsurancePolicyRow: View {
    let policy: InsurancePolicy
    let accounts: [CDAccount]
    let currencyCode: String
    
    private var accountName: String {
        accounts.first(where: { $0.id == policy.accountId })?.wrappedAccountName ?? "Unknown Account"
    }
    
    private var nextDueDate: String {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.day, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        var targetMonth = currentMonth
        var targetYear = currentYear
        
        // If we've passed this month's due date, show next month
        if currentDay > policy.dayOfMonth {
            targetMonth += 1
            if targetMonth > 12 {
                targetMonth = 1
                targetYear += 1
            }
        }
        
        let dateComponents = DateComponents(year: targetYear, month: targetMonth, day: policy.dayOfMonth)
        if let nextDate = calendar.date(from: dateComponents) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: nextDate)
        }
        
        return "Day \(policy.dayOfMonth)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.name)
                        .font(.headline)
                    Text("Next due: \(nextDueDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(policy.premiumAmount, format: .currency(code: currencyCode))
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(accountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !policy.isActive {
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                    Text("Inactive")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct InsuranceView_Previews: PreviewProvider {
    static var previews: some View {
        InsuranceView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif
