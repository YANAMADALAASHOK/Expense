import SwiftUI

struct CategorizationRulesView: View {
    @State private var pattern: String = ""
    @State private var selectedCategory: TransactionCategory = .salary
    @ObservedObject private var ai = AICategorizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var expenseViewModel: ExpenseViewModel
    @State private var scope: RuleScope = .all
    @State private var excludeFromDashboard: Bool = false
    
    private var allCategories: [TransactionCategory] {
        var defaults = TransactionCategory.allCases
        let customs = expenseViewModel.customCategories.map { TransactionCategory.custom($0) }
        defaults.append(contentsOf: customs)
        return defaults
    }
    
    var body: some View {
        List {
            Section("Create Rule") {
                TextField("Keywords (all must appear, e.g., neft cognizant)", text: $pattern)
                Picker("Category", selection: $selectedCategory) {
                    ForEach(allCategories, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                Picker("Applies To", selection: $scope) {
                    Text("All").tag(RuleScope.all)
                    Text("Credits only").tag(RuleScope.creditOnly)
                    Text("Debits only").tag(RuleScope.debitOnly)
                }
                Toggle("Exclude from Dashboard", isOn: $excludeFromDashboard)
                Button(action: addRule) {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
                .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Section("Your Rules") {
                let rules = ai.getUserRules()
                if rules.isEmpty {
                    Text("No rules added yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.pattern)
                                HStack(spacing: 8) {
                                    Text(rule.scope == .all ? "All" : (rule.scope == .creditOnly ? "Credits only" : "Debits only"))
                                    if rule.excludeFromDashboard { Text("Excluded").foregroundColor(.orange) }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(rule.category)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete { idxSet in
                        for idx in idxSet { ai.removeRule(at: idx) }
                    }
                }
            }
        }
        .navigationTitle("Categorization Rules")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Apply to Transactions") {
                    expenseViewModel.applyUserCategorizationRules()
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
    
    private func addRule() {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        ai.addOrUpdateRule(pattern: key, category: selectedCategory.rawValue, scope: scope, excludeFromDashboard: excludeFromDashboard)
        pattern = ""
        excludeFromDashboard = false
    }
}

#if DEBUG
struct CategorizationRulesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { CategorizationRulesView() }
    }
}
#endif


