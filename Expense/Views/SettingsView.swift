import SwiftUI
import UniformTypeIdentifiers
import CoreData

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

enum ImportType {
    case data, axis
}

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @State private var showingCurrencyPicker = false
    @State private var showingCustomCategorySheet = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false {
        didSet {
            print("DEBUG: showingImportPicker changed to: \(showingImportPicker)")
        }
    }
    @State private var currentImportType: ImportType = .data {
        didSet {
            print("DEBUG: currentImportType changed to: \(currentImportType)")
        }
    }
    @State private var showingGrowwImportPicker = false
    @State private var isImportingGroww = false
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
    @State private var showingSuccess = false
    @State private var successMessage = ""
    
    // Computed property for export document
    private var exportDocument: ExpenseExportDocument? {
        do {
            let data = try expenseViewModel.exportData()
            return ExpenseExportDocument(data: data)
        } catch {
            print("Export error: \(error)")
            return nil
        }
    }
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingData = false
    @State private var selectedBank: CreditCardBank = .axis
    @State private var lastFullCheck: Date?
    @State private var isIncrementalCheck = false
    @State private var showGmailTokenSheet = false
    @State private var gmailTokenInput = ""
    @State private var gmailClientId: String = GmailOAuthManager.shared.clientId ?? ""
    @State private var gmailRedirectUri: String = GmailOAuthManager.shared.redirectUri ?? ""
    @State private var showingProfile = false
    
    // Collapsible section states
    @State private var isCloudSyncExpanded = false
    @State private var isEmailExpanded = false
    @State private var isGmailExpanded = false
    @State private var isDataManagementExpanded = false
    @State private var isDangerZoneExpanded = false
    @State private var isCategoriesExpanded = false
    @State private var isCurrencyExpanded = false
    @State private var isUpdatingTimestamps = false
    
    var body: some View {
        NavigationView {
            Form {
                // Cloud Sync Section - Enhanced with visibility
                Section {
                    SyncStatusView(viewModel: expenseViewModel)
                } header: {
                    Label("Cloud Sync", systemImage: "icloud.and.arrow.up")
                }
                
                // Advanced Cloud Operations
                if let user = authManager.currentUser, !user.isGuest {
                    CollapsibleSection(
                        title: "Advanced Cloud Operations",
                        isExpanded: $isCloudSyncExpanded,
                        icon: "gearshape.2"
                    ) {
                        Button(action: {
                            expenseViewModel.loadFromCloud { success in
                                if success {
                                    checkCloudStatus()
                                }
                            }
                        }) {
                            Label("Load from Cloud", systemImage: "arrow.down.circle")
                        }
                    }
                }
                
                // Email Management Section
                CollapsibleSection(
                    title: "Email Management",
                    isExpanded: $isEmailExpanded,
                    icon: "envelope"
                ) {
                    NavigationLink(destination: MailLoginsView(viewModel: expenseViewModel)) {
                        Label("Mail Logins", systemImage: "envelope.circle.fill")
                    }
                }

                // Data Management Section
                CollapsibleSection(
                    title: "Data Management",
                    isExpanded: $isDataManagementExpanded,
                    icon: "folder"
                ) {
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
                        print("DEBUG: Import Data button tapped")
                        currentImportType = .data
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
                        currentImportType = .axis
                        showingImportPicker = true
                    }) {
                        HStack {
                            Label("Import Axis Bank Statement (CSV)", systemImage: "doc.text")
                            if isImportingAxis { Spacer(); ProgressView() }
                        }
                    }
                    
                    Button(action: {
                        isUpdatingTimestamps = true
                        expenseViewModel.updateTransactionTimestampsFromEmails()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            isUpdatingTimestamps = false
                            errorMessage = "Transaction timestamps updated from email data"
                            showingError = true
                        }
                    }) {
                        HStack {
                            Image(systemName: isUpdatingTimestamps ? "clock.arrow.circlepath" : "clock.badge.checkmark")
                            Text(isUpdatingTimestamps ? "Updating Timestamps..." : "Update Timestamps from Emails")
                        }
                    }
                    .disabled(isUpdatingTimestamps || expenseViewModel.pendingTransactions.isEmpty)
                    
                    Link(destination: URL(string: "https://groww.in/p/portfolio")!) {
                        Label("Get Groww Statement", systemImage: "link")
                    }
                }
                
                // Categories Section
                CollapsibleSection(
                    title: "Categories",
                    isExpanded: $isCategoriesExpanded,
                    icon: "tag"
                ) {
                    Button("Manage Custom Categories") {
                        showingCustomCategorySheet = true
                    }
                    NavigationLink(destination: CategorizationRulesView()) {
                        Label("Teach Auto-Categorization Rules", systemImage: "text.badge.plus")
                    }
                }
                
                // Currency Section
                CollapsibleSection(
                    title: "Currency",
                    isExpanded: $isCurrencyExpanded,
                    icon: "dollarsign.circle"
                ) {
                    Button("Change Currency") {
                        showingCurrencyPicker = true
                    }
                }
                
                // Danger Zone Section
                CollapsibleSection(
                    title: "Danger Zone",
                    isExpanded: $isDangerZoneExpanded,
                    icon: "exclamationmark.triangle"
                ) {
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
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: 
                ProfileButtonView(showingProfile: $showingProfile)
            )
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView()
            }
            .sheet(isPresented: $showingProfile) {
                UserProfileView()
            }
            .sheet(isPresented: $showingCustomCategorySheet) {
                CustomCategoryView()
            }
            .fileExporter(
                isPresented: $showingExportSheet,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "ExpenseData_\(DateFormatter.filenameDateFormatter.string(from: Date())).json"
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
                allowedContentTypes: currentImportType == .data ? [.json] : [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                print("DEBUG: fileImporter callback triggered with result: \(result), type: \(currentImportType)")
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
                    
                    switch currentImportType {
                    case .data:
                        do {
                            let data = try Data(contentsOf: url)
                            try expenseViewModel.importData(from: data)
                            print("Data imported successfully")
                            successMessage = "Data imported successfully! Please restart the app to see all changes."
                            showingSuccess = true
                        } catch {
                            errorMessage = "Import failed: \(error.localizedDescription)"
                            showingError = true
                        }
                    case .axis:
                        // Handle Axis CSV import
                        pendingAxisURL = url
                        showingAxisAccountPicker = true
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
            .alert("Success", isPresented: $showingSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(successMessage)
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func generatePasswordPreviewFromProfile(firstName: String, dob: Date) -> String {
        let firstFour = String(firstName.uppercased().prefix(4))
        let calendar = Calendar.current
        let day = calendar.component(.day, from: dob)
        let month = calendar.component(.month, from: dob)
        let dateMonth = String(format: "%02d%02d", day, month)
        return "\(firstFour)\(dateMonth)"
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
        expenseViewModel.clearAllData()
    }
}

// MARK: - Supporting Views

struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let icon: String
    let content: Content
    
    init(title: String, isExpanded: Binding<Bool>, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                content
            } label: {
                Label(title, systemImage: icon)
                    .font(.headline)
            }
        }
    }
}

struct ProfileButtonView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Binding var showingProfile: Bool
    
    var body: some View {
        Button(action: {
            showingProfile = true
        }) {
            if authManager.isAuthenticated, let _ = authManager.currentUser {
                // Show user initials
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 32, height: 32)
                    
                    Text(getUserInitials())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            } else {
                // Show guest icon
                Image(systemName: "person.circle")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func getUserInitials() -> String {
        guard let user = authManager.currentUser else { return "" }
        let first = user.firstName?.first?.uppercased() ?? ""
        let last = user.lastName?.first?.uppercased() ?? ""
        return first + last
    }
}



extension DateFormatter {
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

struct ExpenseExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
} 