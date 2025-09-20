import SwiftUI

struct CategorizationRulesView: View {
    @State private var pattern: String = ""
    @State private var selectedCategory: TransactionCategory = .salary
    @ObservedObject private var ai = AICategorizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var expenseViewModel: ExpenseViewModel
    @State private var scope: RuleScope = .all
    @State private var excludeFromDashboard: Bool = false
    @State private var selectedSuggestedSubcategory: String? = nil
    @State private var subcategoryInput: String = ""
    @State private var editingIndex: Int? = nil
    
    private var allCategories: [TransactionCategory] {
        var defaults = TransactionCategory.allCases
        let customs = expenseViewModel.customCategories.map { TransactionCategory.custom($0) }
        defaults.append(contentsOf: customs)
        return defaults
    }
    private var suggestedSubs: [String] {
        expenseViewModel.subcategories(for: selectedCategory.displayName)
    }
    
    var body: some View {
        List {
            Section(editingIndex == nil ? "Create Rule" : "Edit Rule") {
                TextField("Keywords (all must appear, e.g., neft cognizant)", text: $pattern)
                Picker("Category", selection: $selectedCategory) {
                    ForEach(allCategories, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                if !suggestedSubs.isEmpty {
                    Picker("Subcategory (suggested)", selection: Binding<String?>(
                        get: { selectedSuggestedSubcategory },
                        set: { selectedSuggestedSubcategory = $0 }
                    )) {
                        Text("None").tag(nil as String?)
                        ForEach(suggestedSubs, id: \.self) { s in
                            Text(s).tag(s as String?)
                        }
                    }
                }
                TextField("Or enter subcategory", text: $subcategoryInput)
                Picker("Applies To", selection: $scope) {
                    Text("All").tag(RuleScope.all)
                    Text("Credits only").tag(RuleScope.creditOnly)
                    Text("Debits only").tag(RuleScope.debitOnly)
                }
                Toggle("Exclude from Dashboard", isOn: $excludeFromDashboard)
                HStack {
                    if editingIndex != nil {
                        Button(action: saveRule) { Label("Save Changes", systemImage: "checkmark.circle.fill") }
                        Button(action: clearEditor) { Label("Cancel", systemImage: "xmark.circle") }
                    } else {
                        Button(action: saveRule) { Label("Add Rule", systemImage: "plus.circle.fill") }
                            .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            
            Section("Your Rules") {
                let rules = ai.getUserRules()
                if rules.isEmpty {
                    Text("No rules added yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) {
                                Text(rule.pattern)
                                HStack(spacing: 8) {
                                    Text(rule.scope == .all ? "All" : (rule.scope == .creditOnly ? "Credits only" : "Debits only"))
                                    if rule.excludeFromDashboard { Text("Excluded").foregroundColor(.orange) }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                Text(rule.category).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Edit") {
                                loadRuleForEditing(index: index, rule: rule)
                            }
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
    
    private func saveRule() {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let parent = selectedCategory.rawValue
        let manualSub = subcategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenSub = manualSub.isEmpty ? (selectedSuggestedSubcategory ?? "") : manualSub
        let finalCategory = chosenSub.isEmpty ? parent : "\(parent)::\(chosenSub)"
        if let idx = editingIndex {
            let rule = UserRule(pattern: key, category: finalCategory, scope: scope, excludeFromDashboard: excludeFromDashboard)
            AICategorizationManager.shared.updateRule(at: idx, to: rule)
        } else {
            ai.addOrUpdateRule(pattern: key, category: finalCategory, scope: scope, excludeFromDashboard: excludeFromDashboard)
        }
        clearEditor()
    }
    private func clearEditor() {
        editingIndex = nil
        pattern = ""
        selectedSuggestedSubcategory = nil
        subcategoryInput = ""
        excludeFromDashboard = false
        scope = .all
    }
    private func loadRuleForEditing(index: Int, rule: UserRule) {
        editingIndex = index
        pattern = rule.pattern
        scope = rule.scope
        excludeFromDashboard = rule.excludeFromDashboard
        if let range = rule.category.range(of: "::") {
            let parent = String(rule.category[..<range.lowerBound])
            let sub = String(rule.category[range.upperBound...])
            selectedCategory = TransactionCategory(rawValue: parent)
            if suggestedSubs.contains(sub) { selectedSuggestedSubcategory = sub; subcategoryInput = "" }
            else { selectedSuggestedSubcategory = nil; subcategoryInput = sub }
        } else {
            selectedCategory = TransactionCategory(rawValue: rule.category)
            selectedSuggestedSubcategory = nil
            subcategoryInput = ""
        }
    }
}

#if DEBUG
struct CategorizationRulesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { CategorizationRulesView() }
    }
}
#endif


