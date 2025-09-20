import SwiftUI

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var newCategory = ""
    @State private var showingError = false
    @State private var selectedParentForSub: String = "Food"
    @State private var newSubcategory = ""
    
    var body: some View {
        NavigationView {
            List {
                Section("Add New Category") {
                    HStack {
                        TextField("Category Name", text: $newCategory)
                        Button("Add") {
                            if !newCategory.isEmpty {
                                viewModel.addCustomCategory(newCategory)
                                newCategory = ""
                            }
                        }
                        .disabled(newCategory.isEmpty)
                    }
                }
                
                Section("Custom Categories") {
                    ForEach(viewModel.customCategories, id: \.self) { category in
                        Text(category)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            viewModel.removeCustomCategory(at: index)
                        }
                    }
                }
                
                Section("Default Categories") {
                    ForEach(TransactionCategory.allCases, id: \.self) { category in
                        Text(category.rawValue)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Subcategories") {
                    Picker("Parent Category", selection: $selectedParentForSub) {
                        ForEach(viewModel.allCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    HStack {
                        TextField("New subcategory", text: $newSubcategory)
                        Button("Add") {
                            let trimmed = newSubcategory.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                viewModel.addSubcategory(parent: selectedParentForSub, subcategory: trimmed)
                                newSubcategory = ""
                            }
                        }
                        .disabled(newSubcategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !viewModel.subcategories(for: selectedParentForSub).isEmpty {
                        ForEach(viewModel.subcategories(for: selectedParentForSub), id: \.self) { sub in
                            HStack {
                                Text(sub)
                                Spacer()
                                Button(role: .destructive) {
                                    // remove subcategory
                                    var list = viewModel.subcategoriesByParent[selectedParentForSub] ?? []
                                    list.removeAll { $0.caseInsensitiveCompare(sub) == .orderedSame }
                                    viewModel.subcategoriesByParent[selectedParentForSub] = list
                                    // persist
                                    UserDefaults.standard.set(try? JSONEncoder().encode(viewModel.subcategoriesByParent), forKey: "SubcategoriesByParent")
                                    viewModel.objectWillChange.send()
                                } label: { Image(systemName: "trash") }
                            }
                        }
                    } else {
                        Text("No subcategories for \(selectedParentForSub)")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    NavigationLink(destination: RulesManagementView(viewModel: viewModel)) {
                        Label("Manage Categorization Rules", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Manage Categories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct RulesManagementView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var pattern: String = ""
    @State private var selectedCategory: String = TransactionCategory.other.rawValue
    @State private var selectedSuggestedSubcategory: String? = nil
    @State private var subcategoryInput: String = ""
    @State private var scope: RuleScope = .all
    @State private var excludeFromDashboard: Bool = false
    
    @State private var editingIndex: Int? = nil
    
    private var rules: [UserRule] { AICategorizationManager.shared.getUserRules() }
    private var allCategories: [String] { viewModel.allCategories }
    private var suggestedSubs: [String] { viewModel.subcategories(for: selectedCategory) }
    
    var body: some View {
        List {
            Section(editingIndex == nil ? "Add / Update Rule" : "Edit Rule") {
                TextField("Match text (all words must appear)", text: $pattern)
                Picker("Category", selection: $selectedCategory) {
                    ForEach(allCategories, id: \.self) { c in
                        Text(c).tag(c)
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
                Picker("Scope", selection: $scope) {
                    ForEach(RuleScope.allCases, id: \.self) { s in
                        Text(s.rawValue)
                    }
                }
                Toggle("Exclude from Dashboard totals", isOn: $excludeFromDashboard)
                HStack {
                    if editingIndex != nil {
                        Button("Save Changes") {
                            saveRule()
                        }
                        Button("Cancel") {
                            clearEditor()
                        }
                    } else {
                        Button("Save Rule") { saveRule() }
                            .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            
            Section("Existing Rules") {
                if rules.isEmpty {
                    Text("No rules yet").foregroundColor(.secondary)
                } else {
                    ForEach(Array(rules.enumerated()), id: \.offset) { idx, rule in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.pattern).font(.headline)
                                HStack {
                                    Text("→ \(rule.category)")
                                    Spacer()
                                    Text(rule.scope.rawValue).foregroundColor(.secondary)
                                }.font(.caption)
                                if rule.excludeFromDashboard { Text("Excluded from dashboard").font(.caption2).foregroundColor(.orange) }
                            }
                            Spacer(minLength: 8)
                            Button("Edit") {
                                // Load into editor for editing
                                editingIndex = idx
                                pattern = rule.pattern
                                // Split category into parent/sub if present
                                if let range = rule.category.range(of: "::") {
                                    selectedCategory = String(rule.category[..<range.lowerBound])
                                    let sub = String(rule.category[range.upperBound...])
                                    selectedSuggestedSubcategory = suggestedSubs.contains(sub) ? sub : nil
                                    subcategoryInput = suggestedSubs.contains(sub) ? "" : sub
                                } else {
                                    selectedCategory = rule.category
                                    selectedSuggestedSubcategory = nil
                                    subcategoryInput = ""
                                }
                                scope = rule.scope
                                excludeFromDashboard = rule.excludeFromDashboard
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { AICategorizationManager.shared.removeRule(matching: rule.pattern) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Rules")
    }
    
    private func saveRule() {
        // Combine category + subcategory if provided
        let manualSub = subcategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenSub = manualSub.isEmpty ? (selectedSuggestedSubcategory ?? "") : manualSub
        let finalCategory = chosenSub.isEmpty ? selectedCategory : "\(selectedCategory)::\(chosenSub)"

        if let idx = editingIndex {
            let rule = UserRule(pattern: pattern, category: finalCategory, scope: scope, excludeFromDashboard: excludeFromDashboard)
            AICategorizationManager.shared.updateRule(at: idx, to: rule)
        } else {
            AICategorizationManager.shared.addOrUpdateRule(pattern: pattern, category: finalCategory, scope: scope, excludeFromDashboard: excludeFromDashboard)
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
        selectedCategory = TransactionCategory.other.rawValue
    }
}

#if DEBUG
struct CategoryManagementView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryManagementView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 