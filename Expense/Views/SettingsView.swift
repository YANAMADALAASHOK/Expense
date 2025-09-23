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
    @State private var showGmailTokenSheet = false
    @State private var gmailTokenInput = ""
    @State private var gmailClientId: String = GmailOAuthManager.shared.clientId ?? ""
    @State private var gmailRedirectUri: String = GmailOAuthManager.shared.redirectUri ?? ""
    @State private var showingProfile = false
    @State private var isLoadingBills = false
    @State private var billLoadingProgress = ""
    
    // Collapsible section states
    @State private var isCloudSyncExpanded = false
    @State private var isEmailExpanded = false
    @State private var isBillsExpanded = false
    @State private var isGmailExpanded = false
    @State private var isDataManagementExpanded = false
    @State private var isDangerZoneExpanded = false
    @State private var isCategoriesExpanded = false
    @State private var isCurrencyExpanded = false
    
    var body: some View {
        NavigationView {
            Form {
                // Cloud Sync Section
                CollapsibleSection(
                    title: "Cloud Sync",
                    isExpanded: $isCloudSyncExpanded,
                    icon: "icloud.and.arrow.up"
                ) {
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
                
                // Email Management Section
                CollapsibleSection(
                    title: "Email Management",
                    isExpanded: $isEmailExpanded,
                    icon: "envelope"
                ) {
                    NavigationLink(destination: MailLoginsView(viewModel: expenseViewModel)) {
                        Label("Mail Logins (Outlook & Gmail)", systemImage: "envelope")
                    }
                    
                    NavigationLink(destination: EmailInboxView(viewModel: expenseViewModel, initialSender: "alerts@axisbank.com")) {
                        Label("Axis Alerts (Outlook)", systemImage: "envelope.badge")
                    }
                    NavigationLink(destination: GmailInboxView(viewModel: expenseViewModel)) {
                        Label("ICICI Gmail", systemImage: "tray.full")
                    }
                }

                // Bills Section
                CollapsibleSection(
                    title: "Bills",
                    isExpanded: $isBillsExpanded,
                    icon: "doc.text.below.ecg"
                ) {
                    
                    Button(action: {
                        loadCreditCardBills()
                    }) {
                        HStack {
                            Label("Load Credit Card Bills", systemImage: "envelope.arrow.triangle.branch")
                            if isLoadingBills {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isLoadingBills)
                    
                    if isLoadingBills && !billLoadingProgress.isEmpty {
                        Text(billLoadingProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                    }
                    
                    NavigationLink(destination: CreditCardBillsView(viewModel: expenseViewModel)) {
                        Label("View Processed Bills", systemImage: "creditcard")
                    }
                }

                // Gmail Configuration Section
                CollapsibleSection(
                    title: "Gmail Configuration",
                    isExpanded: $isGmailExpanded,
                    icon: "envelope.circle"
                ) {
                    HStack {
                        Text("Status: ")
                        Text(GmailService.shared.isSignedIn ? "Signed In" : "Not Signed In")
                            .foregroundColor(GmailService.shared.isSignedIn ? .green : .secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OAuth Configuration")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Gmail Client ID", text: $gmailClientId)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        TextField("Redirect URI (e.g., com.googleusercontent.apps.<CLIENT_ID>:/oauth2redirect)", text: $gmailRedirectUri)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        HStack {
                            Button("Save OAuth Settings") {
                                GmailOAuthManager.shared.clientId = gmailClientId.trimmingCharacters(in: .whitespacesAndNewlines)
                                GmailOAuthManager.shared.redirectUri = gmailRedirectUri.trimmingCharacters(in: .whitespacesAndNewlines)
                                errorMessage = "Saved Gmail OAuth settings"
                                showingError = true
                            }
                            .disabled(gmailClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gmailRedirectUri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if GmailService.shared.isSignedIn {
                        Button("Fetch ICICI from Gmail (30d)") {
                            let since = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                            GmailService.shared.fetchICICIMessages(since: since) { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .failure(let err):
                                        errorMessage = "Gmail fetch failed: \(err.localizedDescription)"
                                        showingError = true
                                    case .success(let msgs):
                                        var queued = 0
                                        for (subject, body, _) in msgs {
                                            do {
                                                let parsed = try EmailParser.parse(subject: subject, body: body)
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
                                                queued += 1
                                            } catch { }
                                        }
                                        errorMessage = "Queued \(queued) pending from Gmail"
                                        showingError = true
                                    }
                                }
                            }
                        }
                        Button("Sign Out of Gmail") {
                            GmailService.shared.signOut()
                            errorMessage = "Signed out of Gmail"
                            showingError = true
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Client ID and Redirect URI (from Google Cloud)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Sign in to Gmail") {
                                GmailOAuthManager.shared.signIn { success, message in
                                    errorMessage = success ? "Gmail connected." : (message ?? "Gmail sign-in failed")
                                    showingError = true
                                }
                            }
                        }
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
                Button(action: {
                    showingProfile = true
                }) {
                    ProfileButtonView()
                }
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
        expenseViewModel.clearAllData()
    }
    
    @MainActor
    private func loadCreditCardBills() async {
        isLoadingBills = true
        billLoadingProgress = "Starting bill loading..."
        
        defer {
            isLoadingBills = false
            billLoadingProgress = ""
        }
        
        do {
            print("DEBUG: 🔍 Starting comprehensive credit card bill loading from Settings")
            
            var totalProcessed = 0
            
            // Check both banks and both email providers
            let banks: [(String, String)] = [
                ("cc.statements@axisbank.com", "Axis Bank"),
                ("credit_cards@icicibank.com", "ICICI Bank")
            ]
            let providers: [EmailServiceManager.EmailProvider] = [.outlook, .gmail]
            
            for (bankEmail, bankName) in banks {
                for provider in providers {
                    let providerName = provider == .outlook ? "Outlook" : "Gmail"
                    billLoadingProgress = "📧 Checking \(bankName) from \(providerName)..."
                    print("DEBUG: Checking \(bankName) via \(providerName)...")
                    
                    // Temporarily switch to this provider
                    let originalProvider = EmailServiceManager.shared.preferredProvider
                    EmailServiceManager.shared.preferredProvider = provider
                    
                    defer {
                        EmailServiceManager.shared.preferredProvider = originalProvider
                    }
                    
                    let emailService = EmailServiceManager.shared.getEmailService()
                    
                    // Fetch emails with timeout
                    guard let emails = await withTimeout(seconds: 120, operation: {
                        try await emailService.fetchEmails(from: bankEmail)
                    }) else {
                        billLoadingProgress = "⏰ \(bankName) from \(providerName) timed out"
                        print("DEBUG: \(bankName) via \(providerName) timed out")
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // Show message for 1 second
                        continue
                    }
                    
                    print("DEBUG: Found \(emails.count) emails from \(bankName) via \(providerName)")
                    billLoadingProgress = "📨 Found \(emails.count) emails from \(bankName) (\(providerName))"
                    
                    if emails.isEmpty {
                        billLoadingProgress = "📭 No emails found from \(bankName) (\(providerName))"
                        print("DEBUG: No emails found from \(bankName) via \(providerName)")
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // Show message for 1 second
                        continue
                    }
                    
                    billLoadingProgress = "📎 Processing \(emails.count) emails from \(bankName)..."
                    
                    // Sort emails by date (oldest first, newest last) so latest statement sets final balance
                    let sortedEmails = emails.sorted { email1, email2 in
                        guard let date1 = ISO8601DateFormatter().date(from: email1.receivedDateTime),
                              let date2 = ISO8601DateFormatter().date(from: email2.receivedDateTime) else {
                            return false
                        }
                        return date1 < date2 // oldest first
                    }
                    
                    print("DEBUG: Processing \(sortedEmails.count) emails in chronological order (oldest first)")
                    billLoadingProgress = "📅 Sorted \(sortedEmails.count) emails chronologically for \(bankName)..."
                    
                    // Process all emails in chronological order (oldest first, newest last)
                    for (index, email) in sortedEmails.enumerated() {
                        billLoadingProgress = "📎 Processing email \(index + 1)/\(sortedEmails.count) from \(bankName)..."
                        
                        guard let attachments = await withTimeout(seconds: 60, operation: {
                            try await emailService.fetchAttachments(for: email.id)
                        }) else {
                            continue
                        }
                        
                        let pdfAttachments = attachments.filter { attachment in
                            attachment.contentType?.lowercased().contains("pdf") == true ||
                            attachment.name?.lowercased().hasSuffix(".pdf") == true
                        }
                        
                        for attachment in pdfAttachments {
                            billLoadingProgress = "📄 Processing PDF: \(attachment.name ?? "Statement") from \(bankName)..."
                            
                            if let pdfDataOptional = await withTimeout(seconds: 120, operation: {
                                try await emailService.downloadAttachment(messageId: email.id, attachmentId: attachment.id)
                            }), let pdfData = pdfDataOptional {
                                await processPDFStatement(
                                    pdfData: pdfData,
                                    pdfFileName: attachment.name ?? "\(bankName)_Statement.pdf",
                                    email: email
                                )
                                totalProcessed += 1
                                billLoadingProgress = "✅ Processed \(totalProcessed) statements so far..."
                            }
                        }
                    }
                }
            }
            
            if totalProcessed > 0 {
                billLoadingProgress = "✅ Completed! Processed \(totalProcessed) statements"
                print("DEBUG: ✅ Bill loading complete - processed \(totalProcessed) new statements")
                expenseViewModel.fetchAccounts()
                errorMessage = "✅ Successfully loaded \(totalProcessed) credit card statements"
            } else {
                billLoadingProgress = "ℹ️ No new statements found"
                print("DEBUG: ℹ️ Bill loading complete - no new statements found")
                errorMessage = "ℹ️ No new credit card statements found"
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000) // Show final message for 2 seconds
            showingError = true
            
        } catch {
            billLoadingProgress = "❌ Error occurred"
            print("DEBUG: Error loading credit card bills: \(error)")
            errorMessage = "❌ Error loading bills: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func loadCreditCardBills() {
        Task {
            await loadCreditCardBills()
        }
    }
    
    @MainActor
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            // Add the main operation
            group.addTask {
                do {
                    return try await operation()
                } catch {
                    print("DEBUG: Operation failed with error: \(error)")
                    return nil
                }
            }
            
            // Add timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                print("DEBUG: Operation timed out after \(seconds) seconds")
                return nil
            }
            
            // Return the first completed task result
            let result = await group.next()
            group.cancelAll() // Cancel remaining tasks
            return result ?? nil
        }
    }
    
    @MainActor
    private func processPDFStatement(pdfData: Data, pdfFileName: String, email: EmailMessage) async {
        print("DEBUG: Starting PDF processing for: \(pdfFileName)")
        
        // Save PDF temporarily
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(pdfFileName)
        do {
            try pdfData.write(to: tempURL)
            print("DEBUG: Saved PDF to temp location: \(tempURL.path)")
            
            // Parse PDF with timeout
            let parser = PDFTransactionParser.shared
            
            // Add timeout for PDF parsing (60 seconds)
            let timeoutResult = await withTimeout(seconds: 60, operation: {
                return parser.parsePDF(at: tempURL)
            })
            
            // Handle double optional: withTimeout returns T?, and parsePDF returns CreditCardBillInfo?
            guard let optionalBillInfo = timeoutResult, let billInfo = optionalBillInfo else {
                print("DEBUG: Failed to parse PDF or parsing timed out: \(pdfFileName)")
                return
            }
            
            print("DEBUG: Successfully parsed PDF: \(pdfFileName) - Found \(billInfo.transactions.count) transactions")
            
            // Create or find existing credit card account
            let accountName = "\(billInfo.bankName) ****\(billInfo.cardNumber)"
            let existingAccount = expenseViewModel.accounts.first(where: { account in
                account.wrappedAccountName == accountName && account.wrappedAccountType == AccountType.creditCard
            })
            
            let dateFormatter = ISO8601DateFormatter()
            
            let creditCardAccount: CDAccount
            if let existing = existingAccount {
                creditCardAccount = existing
                print("DEBUG: Using existing account: \(accountName)")
            } else {
                // Create new account
                creditCardAccount = CDAccount(context: expenseViewModel.viewContext)
                creditCardAccount.id = UUID()
                creditCardAccount.accountName = accountName
                creditCardAccount.accountType = AccountType.creditCard.rawValue
                creditCardAccount.balance = -billInfo.totalAmount // Use current usage for account balance
                creditCardAccount.creditLimit = billInfo.creditLimit ?? 0
                
                print("DEBUG: ✅ Created new account: \(accountName)")
            }
            
            // Save the account first with batching to reduce Firestore writes
            try expenseViewModel.performBatchedSave()
            expenseViewModel.viewContext.refresh(creditCardAccount, mergeChanges: true)
            
            // Add all transactions from this bill
            for transaction in billInfo.transactions {
                let existingTransaction = creditCardAccount.transactionsArray.first(where: { cdTransaction in
                    abs(cdTransaction.amount - transaction.amount) < 0.01 &&
                    Calendar.current.isDate(cdTransaction.wrappedDate, inSameDayAs: transaction.date) &&
                    cdTransaction.wrappedNotes.contains(transaction.description)
                })
                
                if existingTransaction == nil {
                    // Check if this is a payment transaction (should be filtered out)
                    let isPayment = isPaymentTransaction(transaction.description)
                    
                    if isPayment {
                        print("DEBUG: 🚫 Skipping payment transaction: \(transaction.description) - ₹\(transaction.amount)")
                        continue
                    }
                    
                    // Re-fetch the account in viewContext
                    let accountInViewContext = expenseViewModel.viewContext.object(with: creditCardAccount.objectID) as! CDAccount
                    
                    // Add CC tag to all credit card transactions
                    let ccTaggedNotes = "[CC] \(transaction.description)"
                    
                    expenseViewModel.addTransaction(
                        amount: transaction.amount,
                        category: TransactionCategory(rawValue: transaction.category),
                        isCredit: false,
                        account: accountInViewContext,
                        notes: ccTaggedNotes,
                        date: transaction.date
                    )
                    
                    print("DEBUG: ✅ Added transaction: \(transaction.description) - ₹\(transaction.amount)")
                }
            }
            
            // Update balance
            let finalAccount = expenseViewModel.viewContext.object(with: creditCardAccount.objectID) as! CDAccount
            finalAccount.balance = -billInfo.totalAmount // Use current usage for account balance
            
            // Save bill metadata for UI display
            saveBillMetadata(account: finalAccount, billInfo: billInfo, pdfFileName: pdfFileName)
            
            // Save context with batching to reduce Firestore writes
            try expenseViewModel.performBatchedSave()
            
            // Force sync after processing is complete
            expenseViewModel.forceSyncPendingSaves()
            
            print("DEBUG: Processed \(billInfo.bankName) ****\(billInfo.cardNumber): \(billInfo.transactions.count) transactions")
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
        } catch {
            print("DEBUG: Error processing PDF \(pdfFileName): \(error)")
        }
    }
    
    // Helper function to detect payment transactions
    private func isPaymentTransaction(_ description: String) -> Bool {
        let paymentKeywords = [
            "BBPS PAYMENT", "PAYMENT RECEIVED", "PAYMENT THANK YOU",
            "CREDIT RECEIVED", "AMOUNT RECEIVED", "PAYMENT PROCESSED",
            "ONLINE PAYMENT", "NEFT PAYMENT", "RTGS PAYMENT", "UPI PAYMENT",
            "IMPS PAYMENT", "CHEQUE PAYMENT", "CASH PAYMENT", "AUTOPAY",
            "REFUND", "REVERSAL", "CASHBACK", "REWARD POINTS"
        ]
        
        let upperDescription = description.uppercased()
        return paymentKeywords.contains { upperDescription.contains($0) }
    }
    
    // Helper function to save bill metadata for UI display
    private func saveBillMetadata(account: CDAccount, billInfo: CreditCardBillInfo, pdfFileName: String) {
        var metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        // Create a unique key for this statement
        let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
        
        // Create bill data dictionary
        let billData: [String: String] = [
            "statementDate": dateFormatter.string(from: billInfo.statementDate),
            "dueDate": dateFormatter.string(from: billInfo.dueDate),
            "dueAmount": String(billInfo.dueAmount),
            "currentUsage": String(billInfo.totalAmount),
            "creditLimit": String(billInfo.creditLimit ?? 0.0),
            "bankName": billInfo.bankName,
            "cardNumber": billInfo.cardNumber,
            "pdfFileName": pdfFileName,
            "transactionCount": String(billInfo.transactions.count)
        ]
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: billData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            metadata[statementKey] = jsonString
            
            // Update account metadata
            account.metadataDictionary = metadata
            
            print("DEBUG: 💾 Saved bill metadata for statement: \(billInfo.statementDate)")
            print("DEBUG: - Key: \(statementKey)")
            print("DEBUG: - Due Amount: ₹\(billInfo.dueAmount)")
            print("DEBUG: - PDF: \(pdfFileName)")
            print("DEBUG: - Total metadata keys: \(metadata.keys.count)")
        } else {
            print("DEBUG: ❌ Failed to save bill metadata for statement: \(billInfo.statementDate)")
        }
    }
    
    
}

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
            // Header Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Collapsible Content
            if isExpanded {
                content
            }
        }
    }
}

struct ProfileButtonView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 32, height: 32)
            
            if let user = authManager.currentUser {
                if user.isGuest {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                } else {
                    Text(initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
            } else {
                Image(systemName: "person.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            }
        }
    }
    
    private var initials: String {
        guard let user = authManager.currentUser else { return "" }
        let first = user.firstName?.first?.uppercased() ?? ""
        let last = user.lastName?.first?.uppercased() ?? ""
        return first + last
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