import SwiftUI

struct CreditCardEmailsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var emails: [OutlookMessage] = []
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var processingEmailId: String?
    @State private var showingFilePicker = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading emails...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if emails.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Emails Found",
                            systemImage: "envelope",
                            description: Text("No emails found from cc.statements@axisbank.com. Make sure you have Axis Bank credit card statement emails in your inbox.")
                        )
                        
                        Button("Check Outlook Login Settings") {
                            // This will be handled by navigation
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    List(emails, id: \.id) { email in
                        CreditCardEmailRow(
                            email: email,
                            isProcessing: processingEmailId == email.id,
                            onProcess: {
                                processEmail(email)
                            }
                        )
                    }
                    .refreshable {
                        loadEmails()
                    }
                }
            }
            .navigationTitle("Credit Card Emails")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: HStack {
                    Button("Test PDF") {
                        testBundledPDF()
                    }
                    Button("Upload PDF") {
                        showingFilePicker = true
                    }
                    Button("Refresh") {
                        loadEmails()
                    }
                }
            )
            .onAppear {
                loadEmails()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
        }
    }
    
    private func loadEmails() {
        isLoading = true
        print("DEBUG: Starting to load emails from cc.statements@axisbank.com")
        
        // First check if we can get access token
        OutlookService.shared.getAccessToken { tokenResult in
            print("DEBUG: Access token result: \(tokenResult)")
            
            switch tokenResult {
            case .success(let token):
                print("DEBUG: Successfully got access token, now fetching messages")
                
                // Fetch emails from cc.statements@axisbank.com (no time filter)
                OutlookService.shared.fetchRecentMessages(since: nil, sender: "cc.statements@axisbank.com") { result in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        
                        switch result {
                        case .success(let messages):
                            self.emails = messages
                            print("DEBUG: Successfully loaded \(messages.count) emails from cc.statements@axisbank.com")
                            
                            for email in messages {
                                let sender = email.from?.emailAddress?.address ?? "Unknown"
                                print("DEBUG: Email - Subject: \(email.subject ?? "No Subject"), Sender: \(sender), Date: \(email.receivedDateTime)")
                            }
                            
                        case .failure(let error):
                            print("DEBUG: Failed to fetch messages: \(error)")
                            self.errorMessage = "Failed to load emails: \(error.localizedDescription)"
                            self.showingError = true
                        }
                    }
                }
                
            case .failure(let error):
                print("DEBUG: Failed to get access token: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Authentication failed: \(error.localizedDescription). Please check your Outlook login in Settings."
                    self.showingError = true
                }
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                self.errorMessage = "❌ No file selected"
                self.showingError = true
                return
            }
            
            print("DEBUG: Processing uploaded PDF: \(url.lastPathComponent)")
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                self.errorMessage = "❌ Cannot access selected file"
                self.showingError = true
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Parse the PDF
            if let billInfo = PDFTransactionParser.shared.parseCreditCardBill(from: url) {
                DispatchQueue.main.async {
                    self.errorMessage = "✅ PDF parsed successfully! Bank: \(billInfo.bankName), Card: ****\(billInfo.cardNumber), Transactions: \(billInfo.transactions.count)"
                    self.showingError = true
                    
                    // Create account from the parsed bill
                    self.createOrUpdateCreditCardAccount(from: billInfo, pdfFileName: url.lastPathComponent, email: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "❌ Failed to parse uploaded PDF file"
                    self.showingError = true
                }
            }
            
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = "❌ File import failed: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }
    
    private func testBundledPDF() {
        print("DEBUG: Testing bundled PDF from project...")
        
        if let billInfo = PDFTransactionParser.shared.testBundledPDF() {
            DispatchQueue.main.async {
                self.errorMessage = "✅ Bundled PDF parsed! Bank: \(billInfo.bankName), Card: ****\(billInfo.cardNumber), Transactions: \(billInfo.transactions.count)"
                self.showingError = true
                
                // Create account from the parsed bill
                self.createOrUpdateCreditCardAccount(from: billInfo, pdfFileName: "Credit Card Statement.pdf", email: nil)
            }
        } else {
            DispatchQueue.main.async {
                self.errorMessage = "❌ Failed to parse bundled PDF. Make sure 'Credit Card Statement.pdf' is added to the Xcode project bundle."
                self.showingError = true
            }
        }
    }
    
    private func processEmail(_ email: OutlookMessage) {
        processingEmailId = email.id
        
        // Get access token and fetch attachments for this message
        OutlookService.shared.getAccessToken { result in
            switch result {
            case .success(let token):
                self.fetchAndProcessPDFAttachments(email: email, token: token)
            case .failure(let error):
                DispatchQueue.main.async {
                    self.processingEmailId = nil
                    self.errorMessage = "Failed to get access token: \(error.localizedDescription)"
                    self.showingError = true
                }
            }
        }
    }
    
    private func fetchAndProcessPDFAttachments(email: OutlookMessage, token: String) {
        let attachmentsUrl = "https://graph.microsoft.com/v1.0/me/messages/\(email.id)/attachments"
        
        guard let url = URL(string: attachmentsUrl) else {
            DispatchQueue.main.async {
                self.processingEmailId = nil
                self.errorMessage = "Invalid attachment URL"
                self.showingError = true
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.processingEmailId = nil
                    self.errorMessage = "Failed to fetch attachments: \(error?.localizedDescription ?? "Unknown error")"
                    self.showingError = true
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let attachments = json["value"] as? [[String: Any]] {
                    
                    print("DEBUG: Found \(attachments.count) attachments for email: \(email.subject ?? "No Subject")")
                    
                    var pdfFound = false
                    for attachment in attachments {
                        if let name = attachment["name"] as? String,
                           let contentType = attachment["contentType"] as? String,
                           let attachmentId = attachment["id"] as? String {
                            
                            print("DEBUG: Attachment - Name: \(name), Type: \(contentType), ID: \(attachmentId)")
                            
                            // Check for PDF by name or content type
                            if name.lowercased().contains("pdf") || 
                               contentType.lowercased().contains("pdf") ||
                               contentType.contains("application/octet-stream") {
                                pdfFound = true
                                print("DEBUG: Processing PDF attachment: \(name)")
                                self.downloadAndProcessPDF(
                                    email: email,
                                    attachmentId: attachmentId,
                                    fileName: name,
                                    token: token
                                )
                                break // Process only the first PDF found
                            } else {
                                print("DEBUG: Skipping non-PDF attachment: \(name) (\(contentType))")
                            }
                        } else {
                            print("DEBUG: Attachment missing required fields: \(attachment)")
                        }
                    }
                    
                    if !pdfFound {
                        DispatchQueue.main.async {
                            self.processingEmailId = nil
                            self.errorMessage = "No PDF attachments found in this email"
                            self.showingError = true
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.processingEmailId = nil
                        self.errorMessage = "Failed to parse attachments response"
                        self.showingError = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.processingEmailId = nil
                    self.errorMessage = "Failed to parse attachments: \(error.localizedDescription)"
                    self.showingError = true
                }
            }
        }.resume()
    }
    
    private func downloadAndProcessPDF(email: OutlookMessage, attachmentId: String, fileName: String, token: String) {
        let attachmentUrl = "https://graph.microsoft.com/v1.0/me/messages/\(email.id)/attachments/\(attachmentId)"
        
        print("DEBUG: Downloading PDF from URL: \(attachmentUrl)")
        
        guard let url = URL(string: attachmentUrl) else {
            print("DEBUG: Invalid attachment URL: \(attachmentUrl)")
            DispatchQueue.main.async {
                self.processingEmailId = nil
                self.errorMessage = "Invalid PDF download URL"
                self.showingError = true
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DEBUG: Network error downloading PDF: \(error)")
                DispatchQueue.main.async {
                    self.processingEmailId = nil
                    self.errorMessage = "Failed to download PDF: \(error.localizedDescription)"
                    self.showingError = true
                }
                return
            }
            
            guard let data = data else {
                print("DEBUG: No data received for PDF download")
                DispatchQueue.main.async {
                    self.processingEmailId = nil
                    self.errorMessage = "No data received for PDF download"
                    self.showingError = true
                }
                return
            }
            
            print("DEBUG: Received \(data.count) bytes for PDF download")
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("DEBUG: PDF download response keys: \(json.keys)")
                    
                    if let contentBytes = json["contentBytes"] as? String {
                        print("DEBUG: Found contentBytes, length: \(contentBytes.count)")
                        
                        // Decode base64 content
                        if let pdfData = Data(base64Encoded: contentBytes) {
                            print("DEBUG: Successfully decoded PDF: \(fileName) (\(pdfData.count) bytes)")
                            self.processPDF(pdfData: pdfData, fileName: fileName, email: email)
                        } else {
                            print("DEBUG: Failed to decode base64 content")
                            DispatchQueue.main.async {
                                self.processingEmailId = nil
                                self.errorMessage = "Failed to decode PDF data from base64"
                                self.showingError = true
                            }
                        }
                    } else {
                        print("DEBUG: No contentBytes found in response")
                        DispatchQueue.main.async {
                            self.processingEmailId = nil
                            self.errorMessage = "PDF download response missing content"
                            self.showingError = true
                        }
                    }
                } else {
                    print("DEBUG: Response is not valid JSON")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("DEBUG: Response content: \(responseString)")
                    }
                    DispatchQueue.main.async {
                        self.processingEmailId = nil
                        self.errorMessage = "Invalid PDF download response format"
                        self.showingError = true
                    }
                }
            } catch {
                print("DEBUG: JSON parsing error: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("DEBUG: Response content: \(responseString)")
                }
                DispatchQueue.main.async {
                    self.processingEmailId = nil
                    self.errorMessage = "Failed to parse PDF download response: \(error.localizedDescription)"
                    self.showingError = true
                }
            }
        }.resume()
    }
    
    private func processPDF(pdfData: Data, fileName: String, email: OutlookMessage) {
        // Save PDF to temporary location
        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try pdfData.write(to: pdfURL)
            
            // Parse the PDF using PDFTransactionParser
            DispatchQueue.main.async {
                print("DEBUG: Successfully saved PDF: \(fileName)")
                
                if let billInfo = PDFTransactionParser.shared.parseCreditCardBill(from: pdfURL) {
                    print("DEBUG: Successfully parsed PDF:")
                    print("DEBUG: Bank: \(billInfo.bankName)")
                    print("DEBUG: Card: \(billInfo.cardNumber)")
                    print("DEBUG: Total Amount: ₹\(billInfo.totalAmount)")
                    print("DEBUG: Transactions: \(billInfo.transactions.count)")
                    
                    // Create credit card account if needed
                    self.createOrUpdateCreditCardAccount(from: billInfo, pdfFileName: fileName, email: email)
                    
                    self.processingEmailId = nil
                    self.errorMessage = "✅ Successfully processed \(fileName): Found \(billInfo.transactions.count) transactions. Created account: \(billInfo.bankName) ****\(billInfo.cardNumber)"
                    self.showingError = true
                } else {
                    print("DEBUG: Failed to parse PDF: \(fileName)")
                    self.processingEmailId = nil
                    self.errorMessage = "❌ Failed to parse PDF: \(fileName). Please check if it's password protected with YANA1906."
                    self.showingError = true
                }
            }
        } catch {
            DispatchQueue.main.async {
                print("DEBUG: Failed to save PDF: \(error)")
                self.processingEmailId = nil
                self.errorMessage = "Failed to save PDF: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }
    
    private func createOrUpdateCreditCardAccount(from billInfo: CreditCardBillInfo, pdfFileName: String, email: OutlookMessage?) {
        let context = viewModel.viewContext
        
        // Create or find existing credit card account
        let accountName = "\(billInfo.bankName) ****\(billInfo.cardNumber)"
        
        let existingAccount = viewModel.accounts.first { account in
            account.wrappedAccountName == accountName && account.wrappedAccountType == .creditCard
        }
        
        print("DEBUG: Looking for account: \(accountName)")
        print("DEBUG: Total accounts in viewModel: \(viewModel.accounts.count)")
        print("DEBUG: Existing account found: \(existingAccount != nil)")
        
        let creditCardAccount: CDAccount
        let shouldUpdateAccountBalance: Bool
        
        if let existing = existingAccount {
            creditCardAccount = existing
            print("DEBUG: Using existing account: \(existing.wrappedAccountName)")
            
            // Check if this statement is newer than the last processed one
            let existingMetadata = existing.metadataDictionary
            let lastStatementDateString = existingMetadata["lastStatementDate"]
            let dateFormatter = ISO8601DateFormatter()
            
            if let lastDateString = lastStatementDateString,
               let lastDate = dateFormatter.date(from: lastDateString) {
                // Compare statement dates
                shouldUpdateAccountBalance = billInfo.statementDate > lastDate
                print("DEBUG: Last statement date: \(lastDate), New statement date: \(billInfo.statementDate)")
                print("DEBUG: Should update account balance: \(shouldUpdateAccountBalance)")
            } else {
                // No previous statement date found, update account
                shouldUpdateAccountBalance = true
                print("DEBUG: No previous statement date found, will update account")
            }
            
            // Update metadata with new statement info (always update metadata for history)
            var metadata = existing.metadataDictionary
            
            // Always update these for the latest processed statement
            metadata["lastPDFFileName"] = pdfFileName
            if let email = email {
                metadata["lastEmailSubject"] = email.subject ?? ""
                metadata["lastEmailDate"] = email.receivedDateTime
            } else {
                metadata["lastEmailSubject"] = "Local Test PDF"
                metadata["lastEmailDate"] = ISO8601DateFormatter().string(from: Date())
            }
            
            // Store this statement in bill history
            let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
            var statementData: [String: String] = [:]
            statementData["statementDate"] = dateFormatter.string(from: billInfo.statementDate)
            statementData["dueDate"] = dateFormatter.string(from: billInfo.dueDate)
            statementData["dueAmount"] = String(billInfo.totalAmount)
            statementData["currentUsage"] = String(billInfo.totalAmount) // Current usage at time of statement
            statementData["creditLimit"] = String(billInfo.creditLimit ?? 0)
            statementData["pdfFileName"] = pdfFileName
            statementData["transactionCount"] = String(billInfo.transactions.count)
            if let email = email {
                statementData["emailSubject"] = email.subject ?? ""
                statementData["emailDate"] = email.receivedDateTime
            }
            
            // Store the statement data as JSON string
            if let statementJsonData = try? JSONSerialization.data(withJSONObject: statementData),
               let statementJsonString = String(data: statementJsonData, encoding: .utf8) {
                metadata[statementKey] = statementJsonString
                print("DEBUG: Stored statement history: \(statementKey)")
            }
            
            // Only update account-level info if this statement is newer
            if shouldUpdateAccountBalance {
                metadata["lastStatementDate"] = dateFormatter.string(from: billInfo.statementDate)
                metadata["lastDueDate"] = dateFormatter.string(from: billInfo.dueDate)
                metadata["lastDueAmount"] = String(billInfo.totalAmount)
                metadata["creditLimit"] = String(billInfo.creditLimit ?? 0)
                
                // Update account balance and credit limit
                creditCardAccount.balance = -billInfo.totalAmount // Negative balance for credit cards
                creditCardAccount.creditLimit = billInfo.creditLimit ?? 0
                
                print("DEBUG: Updated account balance to: \(creditCardAccount.balance)")
                print("DEBUG: Updated credit limit to: \(creditCardAccount.creditLimit)")
            } else {
                print("DEBUG: Skipping account balance update - older statement")
            }
            
            creditCardAccount.metadataDictionary = metadata
            
        } else {
            // New account - always update everything
            shouldUpdateAccountBalance = true
            creditCardAccount = CDAccount(context: context)
            creditCardAccount.id = UUID()
            creditCardAccount.accountName = accountName
            creditCardAccount.accountType = AccountType.creditCard.rawValue
            creditCardAccount.balance = -billInfo.totalAmount // Negative balance for credit cards
            creditCardAccount.creditLimit = billInfo.creditLimit ?? 0
            
            // Set metadata
            var metadata: [String: String] = [:]
            let dateFormatter = ISO8601DateFormatter()
            
            metadata["bankName"] = billInfo.bankName
            metadata["cardNumber"] = billInfo.cardNumber
            metadata["lastStatementDate"] = dateFormatter.string(from: billInfo.statementDate)
            metadata["lastDueDate"] = dateFormatter.string(from: billInfo.dueDate)
            metadata["lastDueAmount"] = String(billInfo.totalAmount) // This is actually the due amount from the statement
            metadata["creditLimit"] = String(billInfo.creditLimit ?? 0)
            metadata["lastPDFFileName"] = pdfFileName
            if let email = email {
                metadata["lastEmailSubject"] = email.subject ?? ""
                metadata["lastEmailDate"] = email.receivedDateTime
            } else {
                metadata["lastEmailSubject"] = "Local Test PDF"
                metadata["lastEmailDate"] = ISO8601DateFormatter().string(from: Date())
            }
            
            // Store this statement in bill history for new account
            let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
            var statementData: [String: String] = [:]
            statementData["statementDate"] = dateFormatter.string(from: billInfo.statementDate)
            statementData["dueDate"] = dateFormatter.string(from: billInfo.dueDate)
            statementData["dueAmount"] = String(billInfo.totalAmount)
            statementData["currentUsage"] = String(billInfo.totalAmount) // Current usage at time of statement
            statementData["creditLimit"] = String(billInfo.creditLimit ?? 0)
            statementData["pdfFileName"] = pdfFileName
            statementData["transactionCount"] = String(billInfo.transactions.count)
            if let email = email {
                statementData["emailSubject"] = email.subject ?? ""
                statementData["emailDate"] = email.receivedDateTime
            }
            
            // Store the statement data as JSON string
            if let statementJsonData = try? JSONSerialization.data(withJSONObject: statementData),
               let statementJsonString = String(data: statementJsonData, encoding: .utf8) {
                metadata[statementKey] = statementJsonString
                print("DEBUG: Stored statement history for new account: \(statementKey)")
            }
            
            creditCardAccount.metadataDictionary = metadata
            
            print("DEBUG: Created new account: \(accountName)")
        }
        
        // Add transactions to the account (always add transactions regardless of statement date)
        var newTransactionsCount = 0
        var duplicateTransactionsCount = 0
        
        for transaction in billInfo.transactions {
            // Check if transaction already exists to avoid duplicates
            let existingTransaction = creditCardAccount.transactionsArray.first { cdTransaction in
                abs(cdTransaction.amount - transaction.amount) < 0.01 &&
                Calendar.current.isDate(cdTransaction.wrappedDate, inSameDayAs: transaction.date) &&
                cdTransaction.wrappedNotes.contains(transaction.description)
            }
            
            if existingTransaction == nil {
                let cdTransaction = CDTransaction(context: context)
                cdTransaction.id = UUID()
                cdTransaction.amount = transaction.amount
                cdTransaction.category = transaction.category
                cdTransaction.date = transaction.date
                cdTransaction.isCredit = false // Credit card expenses are debits
                cdTransaction.notes = transaction.description
                cdTransaction.account = creditCardAccount
                
                creditCardAccount.addToTransactions(cdTransaction)
                newTransactionsCount += 1
            } else {
                duplicateTransactionsCount += 1
            }
        }
        
        print("DEBUG: Transaction processing summary:")
        print("DEBUG: - New transactions added: \(newTransactionsCount)")
        print("DEBUG: - Duplicate transactions skipped: \(duplicateTransactionsCount)")
        print("DEBUG: - Total transactions in statement: \(billInfo.transactions.count)")
        
        // Save context
        do {
            try context.save()
            print("DEBUG: Successfully saved credit card account and transactions")
            print("DEBUG: Account name: \(creditCardAccount.wrappedAccountName)")
            print("DEBUG: Account type: \(creditCardAccount.wrappedAccountType)")
            print("DEBUG: Account balance: \(creditCardAccount.balance)")
            print("DEBUG: Transactions added: \(billInfo.transactions.count)")
            
            // Refresh the ExpenseViewModel's accounts
            DispatchQueue.main.async {
                self.viewModel.fetchAccounts()
                print("DEBUG: Refreshed accounts in ExpenseViewModel")
            }
        } catch {
            print("DEBUG: Failed to save credit card data: \(error)")
        }
    }
}

struct CreditCardEmailRow: View {
    let email: OutlookMessage
    let isProcessing: Bool
    let onProcess: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(email.subject ?? "No Subject")
                        .font(.headline)
                        .lineLimit(2)
                    
                    HStack {
                        Text(formatDate(email.receivedDateTime))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(email.from?.emailAddress?.address ?? "Unknown Sender")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let preview = email.bodyPreview, !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Button(action: onProcess) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "doc.text.below.ecg")
                        }
                        Text(isProcessing ? "Processing..." : "Process PDF")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isProcessing ? Color.gray.opacity(0.3) : Color.blue.opacity(0.1))
                    .foregroundColor(isProcessing ? .gray : .blue)
                    .cornerRadius(8)
                }
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

#Preview {
    CreditCardEmailsView(viewModel: ExpenseViewModel(context: PersistenceController.preview.container.viewContext))
}
