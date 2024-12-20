import SwiftUI

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var newCategory = ""
    @State private var showingError = false
    
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

#if DEBUG
struct CategoryManagementView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryManagementView(viewModel: ExpenseViewModel(context: PreviewHelper.shared.viewContext))
    }
}
#endif 