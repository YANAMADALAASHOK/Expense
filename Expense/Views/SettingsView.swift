import SwiftUI
import UniformTypeIdentifiers

struct ManageCategoriesView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    
    var body: some View {
        List {
            ForEach(viewModel.customCategories, id: \.self) { category in
                Text(category)
            }
            .onDelete(perform: deleteCategory)
        }
        .navigationTitle("Categories")
    }
    
    private func deleteCategory(at offsets: IndexSet) {
        viewModel.customCategories.remove(atOffsets: offsets)
        UserDefaults.standard.set(viewModel.customCategories, forKey: "CustomCategories")
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingAddCategory = false
    @State private var newCategory = ""
    
    var body: some View {
        NavigationView {
            List {
                Section("Currency") {
                    Picker("Currency", selection: $currencySettings.selectedCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text("\(currency.symbol) (\(currency.rawValue))").tag(currency)
                        }
                    }
                }
                
                Section("Categories") {
                    NavigationLink(destination: ManageCategoriesView(viewModel: viewModel)) {
                        Label("Manage Categories", systemImage: "list.bullet")
                    }
                    
                    Button(action: {
                        showingAddCategory = true
                    }) {
                        Label("Add Category", systemImage: "plus.circle")
                    }
                }
                
                Section("Data Management") {
                    Button(action: {
                        showingExportSheet = true
                    }) {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: {
                        showingImportPicker = true
                    }) {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .fileExporter(
                isPresented: $showingExportSheet,
                document: ExpenseDataDocument(viewModel: viewModel),
                contentType: .json,
                defaultFilename: "ExpenseData.json"
            ) { result in
                switch result {
                case .success(let url):
                    print("Data exported successfully to \(url)")
                case .failure(let error):
                    errorMessage = "Export failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        errorMessage = "No file selected"
                        showingError = true
                        return
                    }
                    
                    guard url.startAccessingSecurityScopedResource() else {
                        errorMessage = "Permission denied: Cannot access the selected file"
                        showingError = true
                        return
                    }
                    
                    defer {
                        url.stopAccessingSecurityScopedResource()
                    }
                    
                    do {
                        let data = try Data(contentsOf: url)
                        try viewModel.importData(from: data)
                        print("Data imported successfully")
                    } catch {
                        errorMessage = "Import failed: \(error.localizedDescription)"
                        showingError = true
                    }
                    
                case .failure(let error):
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Add Category", isPresented: $showingAddCategory) {
                TextField("Category Name", text: $newCategory)
                Button("Cancel", role: .cancel) {
                    newCategory = ""
                }
                Button("Add") {
                    if !newCategory.isEmpty {
                        viewModel.customCategories.append(newCategory)
                        UserDefaults.standard.set(viewModel.customCategories, forKey: "CustomCategories")
                        newCategory = ""
                    }
                }
            } message: {
                Text("Enter a name for the new category")
            }
        }
    }
}

struct ExpenseDataDocument: FileDocument {
    let viewModel: ExpenseViewModel
    
    static var readableContentTypes: [UTType] { [.json] }
    
    init(viewModel: ExpenseViewModel) {
        self.viewModel = viewModel
    }
    
    init(configuration: ReadConfiguration) throws {
        self.viewModel = ExpenseViewModel(context: PersistenceController.shared.container.viewContext)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try viewModel.exportData()
        return FileWrapper(regularFileWithContents: data)
    }
} 