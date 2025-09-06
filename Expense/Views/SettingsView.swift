import SwiftUI
import UniformTypeIdentifiers

struct CurrencyPickerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Button(action: {
                        currencySettings.selectedCurrency = currency
                        dismiss()
                    }) {
                        HStack {
                            Text("\(currency.symbol) (\(currency.rawValue))")
                            Spacer()
                            if currency == currencySettings.selectedCurrency {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Currency")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct CustomCategoryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @State private var newCategory = ""
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Add New Category")) {
                    HStack {
                        TextField("Category Name", text: $newCategory)
                        Button(action: addCategory) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newCategory.isEmpty)
                    }
                }
                
                Section(header: Text("Custom Categories")) {
                    ForEach(expenseViewModel.customCategories, id: \.self) { category in
                        Text(category)
                    }
                    .onDelete(perform: deleteCategory)
                }
            }
            .navigationTitle("Custom Categories")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
    
    private func addCategory() {
        guard !newCategory.isEmpty else { return }
        expenseViewModel.addCustomCategory(newCategory)
        newCategory = ""
    }
    
    private func deleteCategory(at offsets: IndexSet) {
        offsets.forEach { index in
            expenseViewModel.removeCustomCategory(at: index)
        }
    }
}

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
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @State private var showingCurrencyPicker = false
    @State private var showingCustomCategorySheet = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingGrowwImportPicker = false
    @State private var isImportingGroww = false
    @State private var showingAxisImportPicker = false
    @State private var isImportingAxis = false
    @State private var showingAxisAccountPicker = false
    @State private var pendingAxisURL: URL?
    @State private var isUpdatingNAVs = false
    @State private var newCategory = ""
    @State private var cloudSyncStatus = "Checking..."
    @State private var lastSyncTime: Date?
    @State private var isCheckingStatus = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingData = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account")) {
                    if let user = authManager.currentUser {
                        if user.isGuest {
                            Text("Signed in as Guest")
                        } else {
                            Text("Email: \(user.email)")
                        }
                        Button("Sign Out") {
                            authManager.signOut()
                        }
                    }
                }
                
                Section(header: Text("Cloud Sync")) {
                    VStack(alignment: .leading) {
                        Text("Status: \(cloudSyncStatus)")
                        if let lastSync = lastSyncTime {
                            Text("Last synced: \(lastSync.formatted())")
                        }
                    }
                    
                    if let user = authManager.currentUser, !user.isGuest {
                        Button(action: {
                            expenseViewModel.syncToCloud()
                            checkCloudStatus()
                        }) {
                            Text("Sync Now")
                        }
                        
                        Button(action: {
                            expenseViewModel.loadFromCloud { success in
                                if success {
                                    checkCloudStatus()
                                }
                            }
                        }) {
                            Text("Load from Cloud")
                        }
                    }
                }
                
                Section(header: Text("Outlook Email")) {
                    Button("Connect Outlook (Mail.Read)") {
                        MicrosoftOAuthManager.shared.signIn { result in
                            switch result {
                            case .success:
                                errorMessage = "Outlook connected."
                                showingError = true
                            case .failure(let error):
                                errorMessage = "Outlook sign-in failed: \(error.localizedDescription)"
                                showingError = true
                            }
                        }
                    }
                    NavigationLink(destination: EmailInboxView(viewModel: expenseViewModel, initialSender: "alerts@axisbank.com")) {
                        Label("Fetch Axis Alerts", systemImage: "envelope.badge")
                    }
                    Button("Fetch All (Newer Only)") {
                        OutlookService.shared.fetchRecentMessages(since: expenseViewModel.lastEmailReceivedAt, sender: nil) { result in
                            switch result {
                            case .success(let messages):
                                var created = 0
                                for m in messages {
                                    let msgId = m.id
                                    guard !expenseViewModel.processedEmailMessageIds.contains(msgId) else { continue }
                                    let received = ISO8601DateFormatter().date(from: m.receivedDateTime) ?? Date()
                                    do {
                                        let parsed = try EmailParser.parse(subject: m.subject, body: m.body?.content ?? m.bodyPreview)
                                        let pending = PendingTransactionItem(
                                            subject: parsed.subject,
                                            body: parsed.body,
                                            amount: parsed.amount,
                                            date: parsed.date,
                                            isCredit: parsed.isCredit,
                                            suggestedCategory: parsed.suggestedCategory,
                                            notes: parsed.description
                                        )
                                        expenseViewModel.addPendingTransaction(pending)
                                        expenseViewModel.markEmailProcessed(messageId: msgId, receivedAt: received)
                                        created += 1
                                    } catch { }
                                }
                                errorMessage = "Fetched \(messages.count); queued \(created) pending."
                                showingError = true
                            case .failure(let error):
                                errorMessage = "Outlook fetch failed: \(error.localizedDescription)"
                                showingError = true
                            }
                        }
                    }
                    NavigationLink(destination: PendingTransactionsView(viewModel: expenseViewModel)) {
                        Label("Review Pending Transactions", systemImage: "doc.plaintext")
                    }
                    NavigationLink(destination: EmailInboxView(viewModel: expenseViewModel)) {
                        Label("Browse Inbox (manual)", systemImage: "envelope")
                    }
                }

                Section(header: Text("Data Management")) {
                    Button(action: {
                        isUpdatingNAVs = true
                        expenseViewModel.updateMutualFundNAVs { _ in
                            isUpdatingNAVs = false
                        }
                    }) {
                        HStack {
                            Image(systemName: isUpdatingNAVs ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                            Text(isUpdatingNAVs ? "Updating NAVs..." : "Refresh Mutual Fund NAVs")
                        }
                    }
                    .disabled(isUpdatingNAVs)

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
                    
                    Button(action: {
                        showingGrowwImportPicker = true
                    }) {
                        HStack {
                            Label("Import from Groww CSV", systemImage: "doc.text")
                            if isImportingGroww { Spacer(); ProgressView() }
                        }
                    }
                    Button(action: {
                        showingAxisImportPicker = true
                    }) {
                        HStack {
                            Label("Import Axis Bank Statement (CSV)", systemImage: "doc.text")
                            if isImportingAxis { Spacer(); ProgressView() }
                        }
                    }
                    
                    Link(destination: URL(string: "https://groww.in/p/portfolio")!) {
                        Label("Get Groww Statement", systemImage: "link")
                    }
                }
                
                Section(header: Text("Danger Zone")) {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: isDeletingData ? "trash.circle.fill" : "trash")
                            Text(isDeletingData ? "Deleting..." : "Delete All Data")
                        }
                        .foregroundColor(.red)
                    }
                    .disabled(isDeletingData)
                }
                
                Section(header: Text("Categories")) {
                    Button("Manage Custom Categories") {
                        showingCustomCategorySheet = true
                    }
                    NavigationLink(destination: CategorizationRulesView()) {
                        Label("Teach Auto-Categorization Rules", systemImage: "text.badge.plus")
                    }
                }
                
                Section(header: Text("Currency")) {
                    Button("Change Currency") {
                        showingCurrencyPicker = true
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView()
            }
            .sheet(isPresented: $showingCustomCategorySheet) {
                CustomCategoryView()
            }
            .fileExporter(
                isPresented: $showingExportSheet,
                document: ExpenseDataDocument(viewModel: expenseViewModel),
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
                        try expenseViewModel.importData(from: data)
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
            .sheet(isPresented: $showingGrowwImportPicker) {
                GrowwDocumentPicker(onPick: { url in
                    // Dismiss picker sheet immediately
                    showingGrowwImportPicker = false
                    isImportingGroww = true
                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("groww_\(UUID().uuidString).csv")
                    do {
                        // Request security access to the picked URL before copying
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        if FileManager.default.fileExists(atPath: tmpURL.path) { try? FileManager.default.removeItem(at: tmpURL) }
                        try FileManager.default.copyItem(at: url, to: tmpURL)
                        expenseViewModel.importGrowwCSV(from: tmpURL) { result in
                            DispatchQueue.main.async { isImportingGroww = false }
                            switch result {
                            case .success(let count):
                                errorMessage = "Successfully imported \(count) mutual funds."
                                showingError = true
                            case .failure(let error):
                                errorMessage = "Groww Import failed: \(error.localizedDescription)"
                                showingError = true
                            }
                        }
                    } catch {
                        isImportingGroww = false
                        errorMessage = "Groww Import failed: \(error.localizedDescription)"
                        showingError = true
                    }
                }, onCancel: {
                    showingGrowwImportPicker = false
                })
            }
            .fileImporter(
                isPresented: $showingAxisImportPicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        errorMessage = "No file selected for Axis import"
                        showingError = true
                        return
                    }
                    pendingAxisURL = url
                    showingAxisAccountPicker = true
                case .failure(let error):
                    errorMessage = "Axis Import failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
            .sheet(isPresented: $showingAxisAccountPicker) {
                if let url = pendingAxisURL {
                    NavigationView {
                        AxisAccountPickerView(viewModel: expenseViewModel) { account in
                            isImportingAxis = true
                            expenseViewModel.importAxisBankCSV(from: url, into: account) { result in
                                DispatchQueue.main.async {
                                    isImportingAxis = false
                                    showingAxisAccountPicker = false
                                    pendingAxisURL = nil
                                }
                                switch result {
                                case .success(let count):
                                    errorMessage = "Successfully imported \(count) Axis transactions."
                                    showingError = true
                                case .failure(let error):
                                    errorMessage = "Axis Import failed: \(error.localizedDescription)"
                                    showingError = true
                                }
                            }
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Delete All Data",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Data", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all your data from both the device and Firebase. This action cannot be undone. Are you sure you want to continue?")
            }
            .onAppear {
                checkCloudStatus()
            }
        }
    }
    
    private func checkCloudStatus() {
        guard !isCheckingStatus else { return }
        isCheckingStatus = true
        
        guard let user = authManager.currentUser, !user.isGuest else {
            cloudSyncStatus = "Not available (Guest Mode)"
            isCheckingStatus = false
            return
        }
        
        expenseViewModel.checkCloudDataStatus { exists, lastSync in
            DispatchQueue.main.async {
                cloudSyncStatus = exists ? "Synced" : "Not synced"
                lastSyncTime = lastSync
                isCheckingStatus = false
            }
        }
    }
    
    private func deleteAllData() {
        isDeletingData = true
        
        // Delete from Firebase first
        if let user = authManager.currentUser, !user.isGuest {
            expenseViewModel.deleteAllDataFromFirebase { success in
                DispatchQueue.main.async {
                    if success {
                        // Then clear local data
                        expenseViewModel.clearAllData()
                        errorMessage = "All data has been successfully deleted from both Firebase and device."
                    } else {
                        errorMessage = "Failed to delete data from Firebase. Please try again."
                    }
                    showingError = true
                    isDeletingData = false
                }
            }
        } else {
            // Just clear local data for guest users
            expenseViewModel.clearAllData()
            errorMessage = "All local data has been successfully deleted."
            showingError = true
            isDeletingData = false
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