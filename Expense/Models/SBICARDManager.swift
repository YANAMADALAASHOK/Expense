import Foundation
import CoreData

/// Manager for processing SBI Credit Card statements from email attachments
/// Searches both Outlook and Gmail for PDFs with format: "SBI Card Statement_XXXX_DD-MM-YYYY.PDF"
class SBICARDManager {
    static let shared = SBICARDManager()
    private init() {}
    
    // MARK: - Public Methods
    
    /// Process SBI credit card statements from emails
    /// - Parameters:
    ///   - viewModel: ExpenseViewModel for Core Data operations
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Number of statements processed
    @MainActor
    func processStatements(
        viewModel: ExpenseViewModel,
        progressCallback: ((String) -> Void)? = nil
    ) async -> Int {
        print("DEBUG: 🏦 SBICARDManager - Starting SBI Card statement processing")
        
        // CRITICAL: Enable bulk processing mode to disable Firestore sync
        viewModel.isBulkProcessing = true
        print("DEBUG: 🚫 Firestore sync DISABLED for bulk processing")
        
        var totalProcessed = 0
        let providers: [EmailServiceManager.EmailProvider] = [.outlook, .gmail]
        
        // Search both email providers
        for provider in providers {
            let providerName = provider == .outlook ? "Outlook" : "Gmail"
            
            // Skip Gmail if we already found statements in Outlook
            if provider == .gmail && totalProcessed > 0 {
                print("DEBUG: ⏭️ Skipping Gmail - already found \(totalProcessed) statements in Outlook")
                continue
            }
            
            progressCallback?("📧 Searching \(providerName) for SBI statements...")
            print("DEBUG: 🔍 Checking \(providerName) for SBI Card statements")
            
            // Temporarily switch to this provider
            let originalProvider = EmailServiceManager.shared.preferredProvider
            EmailServiceManager.shared.preferredProvider = provider
            
            defer {
                EmailServiceManager.shared.preferredProvider = originalProvider
            }
            
            let emailService = EmailServiceManager.shared.getEmailService()
            
            // Fetch ALL recent emails to find forwarded/shared SBI PDFs
            do {
                progressCallback?("📨 Searching all folders for SBI Card PDFs...")
                print("DEBUG: 📧 Fetching all recent emails from \(providerName) to find SBI Card PDFs")
                
                var allEmails: [EmailMessage] = []
                
                // Strategy 1: Search by common domains (inbox, sent, etc.)
                let possibleSenders = [
                    "sbicard.com",
                    "gmail.com",
                    "outlook.com",
                    "hotmail.com",
                    "yahoo.com",
                    "icloud.com"
                ]
                
                print("DEBUG: 🔍 Strategy 1: Searching by sender domains...")
                for sender in possibleSenders {
                    do {
                        let emails = try await emailService.fetchEmails(from: sender)
                        allEmails.append(contentsOf: emails)
                        print("DEBUG: Found \(emails.count) emails from \(sender)")
                    } catch {
                        // Silently continue if sender fails
                        continue
                    }
                }
                
                // Strategy 2: If using Outlook, also search for emails with "SBI" in subject/body
                if provider == .outlook {
                    print("DEBUG: 🔍 Strategy 2: Searching Outlook for 'SBI' keyword...")
                    do {
                        // Search for emails containing "SBI" - this will search all folders
                        let sbiEmails = try await searchOutlookForKeyword("SBI")
                        print("DEBUG: Found \(sbiEmails.count) emails with 'SBI' keyword")
                        allEmails.append(contentsOf: sbiEmails)
                    } catch {
                        print("DEBUG: ⚠️ Keyword search failed: \(error.localizedDescription)")
                    }
                }
                
                if allEmails.isEmpty {
                    print("DEBUG: ℹ️ No emails found in \(providerName)")
                    continue
                }
                
                print("DEBUG: 📧 Total emails found in \(providerName): \(allEmails.count)")
                progressCallback?("📎 Found \(allEmails.count) emails, scanning for SBI Card PDFs...")
                
                // Collect all SBI PDFs first, then sort by date
                var sbiPDFsToProcess: [(email: EmailMessage, attachment: EmailAttachment, index: Int)] = []
                
                // Process each email for PDF attachments
                var emailsWithAttachments = 0
                var totalPDFsFound = 0
                
                for (index, email) in allEmails.enumerated() {
                    progressCallback?("📄 Scanning email \(index + 1)/\(allEmails.count)...")
                    
                    // Fetch attachments
                    do {
                        let attachments = try await emailService.fetchAttachments(for: email.id)
                        
                        if !attachments.isEmpty {
                            emailsWithAttachments += 1
                            print("DEBUG: 📎 Email \(index + 1) has \(attachments.count) attachment(s)")
                            
                            // Log all attachment names for debugging
                            for attachment in attachments {
                                if let name = attachment.name {
                                    print("DEBUG:   - Attachment: \(name)")
                                }
                            }
                        }
                        
                        // Filter for SBI Card statement PDFs
                        let sbiPDFs = attachments.filter { attachment in
                            guard let name = attachment.name?.lowercased() else { return false }
                            
                            // Match pattern: "SBI Card Statement_XXXX_DD-MM-YYYY.PDF"
                            // Also accept variations like "sbi_card_statement", "sbicard", etc.
                            let hasSBI = name.contains("sbi")
                            let hasCard = name.contains("card")
                            let hasStatement = name.contains("statement") || name.contains("stmt")
                            let isPDF = name.hasSuffix(".pdf")
                            
                            // Must have SBI + Card + (Statement OR just be a PDF with SBI Card in name)
                            return isPDF && hasSBI && hasCard && (hasStatement || name.contains("sbicard"))
                        }
                        
                        if sbiPDFs.isEmpty {
                            continue
                        }
                        
                        totalPDFsFound += sbiPDFs.count
                        print("DEBUG: ✅ Found \(sbiPDFs.count) SBI Card PDF(s) in email \(index + 1)")
                        for pdf in sbiPDFs {
                            let pdfName = pdf.name ?? "Unknown"
                            print("DEBUG:   - SBI PDF: \(pdfName)")
                            // Collect PDF for later processing
                            sbiPDFsToProcess.append((email: email, attachment: pdf, index: index))
                        }
                        
                    } catch {
                        print("DEBUG: ⚠️ Error fetching attachments for email \(index + 1): \(error.localizedDescription)")
                    }
                }
                
                // Summary for this provider
                print("DEBUG: 📊 \(providerName) Summary:")
                print("DEBUG:   - Total emails scanned: \(allEmails.count)")
                print("DEBUG:   - Emails with attachments: \(emailsWithAttachments)")
                print("DEBUG:   - SBI Card PDFs found: \(totalPDFsFound)")
                
                // Sort PDFs by extracting date from filename - oldest first
                sbiPDFsToProcess.sort { pdf1, pdf2 in
                    let name1 = pdf1.attachment.name ?? ""
                    let name2 = pdf2.attachment.name ?? ""
                    
                    // Extract date from filename: "SBI Card Statement_4418_24-09-2025.PDF"
                    // Pattern: DD-MM-YYYY
                    let datePattern = #"(\d{2})-(\d{2})-(\d{4})"#
                    
                    func extractDate(from filename: String) -> Date? {
                        guard let regex = try? NSRegularExpression(pattern: datePattern),
                              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
                              match.numberOfRanges >= 4 else {
                            return nil
                        }
                        
                        let day = (filename as NSString).substring(with: match.range(at: 1))
                        let month = (filename as NSString).substring(with: match.range(at: 2))
                        let year = (filename as NSString).substring(with: match.range(at: 3))
                        
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "dd-MM-yyyy"
                        return dateFormatter.date(from: "\(day)-\(month)-\(year)")
                    }
                    
                    let date1 = extractDate(from: name1) ?? Date.distantPast
                    let date2 = extractDate(from: name2) ?? Date.distantPast
                    
                    return date1 < date2 // Oldest first
                }
                
                print("DEBUG: 📅 Processing \(sbiPDFsToProcess.count) PDFs in chronological order (oldest first)")
                
                // MEMORY OPTIMIZATION: Process in smaller batches to prevent crash
                let batchSize = 3 // Process 3 PDFs at a time
                let totalBatches = (sbiPDFsToProcess.count + batchSize - 1) / batchSize
                
                for batchIndex in 0..<totalBatches {
                    let startIndex = batchIndex * batchSize
                    let endIndex = min(startIndex + batchSize, sbiPDFsToProcess.count)
                    let batch = Array(sbiPDFsToProcess[startIndex..<endIndex])
                    
                    print("DEBUG: 📦 Processing batch \(batchIndex + 1)/\(totalBatches) (\(batch.count) PDFs)")
                    progressCallback?("📦 Batch \(batchIndex + 1)/\(totalBatches) - Processing \(batch.count) statements...")
                    
                    // Process each PDF in this batch
                    for (localIndex, pdfInfo) in batch.enumerated() {
                        let pdfIndex = startIndex + localIndex
                    let pdfName = pdfInfo.attachment.name ?? "Unknown"
                    progressCallback?("📄 Processing \(pdfIndex + 1)/\(sbiPDFsToProcess.count): \(pdfName)")
                    print("DEBUG: 📄 [\(pdfIndex + 1)/\(sbiPDFsToProcess.count)] Processing PDF: \(pdfName)")
                    
                    // Download PDF
                    do {
                        guard let pdfData = try await emailService.downloadAttachment(
                            messageId: pdfInfo.email.id,
                            attachmentId: pdfInfo.attachment.id
                        ) else {
                            print("DEBUG: ❌ Failed to download PDF: \(pdfName)")
                            continue
                        }
                        
                        // Process the PDF
                        let processed = await processPDFStatement(
                            pdfData: pdfData,
                            pdfFileName: pdfName,
                            email: pdfInfo.email,
                            viewModel: viewModel
                        )
                        
                        if processed {
                            totalProcessed += 1
                            progressCallback?("✅ [\(pdfIndex + 1)/\(sbiPDFsToProcess.count)] Processed: \(pdfName)")
                        }
                        
                        // CRITICAL: Clear memory after each PDF to prevent crash
                        autoreleasepool {
                            // Force memory cleanup
                            print("DEBUG: 🧹 Clearing memory after processing \(pdfName)")
                        }
                        
                        // Small delay to allow memory cleanup
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        
                    } catch {
                        print("DEBUG: ❌ Error downloading PDF \(pdfName): \(error.localizedDescription)")
                    }
                    }
                    
                    // CRITICAL: Clear memory after each batch
                    print("DEBUG: 🧹🧹 Clearing memory after batch \(batchIndex + 1)")
                    autoreleasepool {
                        // Force aggressive memory cleanup between batches
                    }
                    
                    // Longer delay between batches to ensure memory is freed
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
                
            } catch {
                print("DEBUG: ❌ Error fetching SBI emails from \(providerName): \(error.localizedDescription)")
            }
        }
        
        print("DEBUG: ✅ SBICARDManager - Completed processing \(totalProcessed) statements")
        
        // CRITICAL: Re-enable Firestore sync after bulk processing
        viewModel.isBulkProcessing = false
        print("DEBUG: ✅ Firestore sync RE-ENABLED")
        
        // Now do a single efficient bulk sync to Firestore
        print("DEBUG: ☁️ Performing single bulk sync to Firestore...")
        await viewModel.performBulkSync()
        
        return totalProcessed
    }
    
    // MARK: - Private Methods
    
    /// Process a single SBI Card PDF statement
    @MainActor
    private func processPDFStatement(
        pdfData: Data,
        pdfFileName: String,
        email: EmailMessage,
        viewModel: ExpenseViewModel
    ) async -> Bool {
        print("DEBUG: 🔍 Processing SBI Card PDF: \(pdfFileName)")
        
        // Save PDF temporarily
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(pdfFileName)
        
        do {
            try pdfData.write(to: tempURL)
            print("DEBUG: 💾 Saved PDF to temp location: \(tempURL.path)")
            
            // Parse PDF
            let parser = PDFTransactionParser.shared
            guard let billInfo = parser.parsePDF(at: tempURL) else {
                print("DEBUG: ❌ Failed to parse SBI Card PDF: \(pdfFileName)")
                try? FileManager.default.removeItem(at: tempURL)
                return false
            }
            
            print("DEBUG: ✅ Successfully parsed PDF: \(pdfFileName)")
            print("DEBUG: - Bank: \(billInfo.bankName)")
            print("DEBUG: - Card: ****\(billInfo.cardNumber)")
            print("DEBUG: - Transactions: \(billInfo.transactions.count)")
            print("DEBUG: - Total Amount: ₹\(billInfo.totalAmount)")
            
            // Check if this bill already exists
            let accountName = "\(billInfo.bankName) ****\(billInfo.cardNumber)"
            let existingAccount = viewModel.accounts.first(where: { account in
                account.wrappedAccountName == accountName && account.wrappedAccountType == AccountType.creditCard
            })
            
            if let existing = existingAccount {
                let dateFormatter = ISO8601DateFormatter()
                let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
                let metadata = existing.metadataDictionary
                
                if metadata.keys.contains(statementKey) {
                    print("DEBUG: ⏭️ Bill already exists for \(accountName) - Statement: \(billInfo.statementDate)")
                    print("DEBUG: ⏭️ Skipping duplicate bill processing")
                    try? FileManager.default.removeItem(at: tempURL)
                    return false
                }
            }
            
            let dateFormatter = ISO8601DateFormatter()
            
            // Create or find existing credit card account
            let creditCardAccount: CDAccount
            if let existing = existingAccount {
                creditCardAccount = existing
                print("DEBUG: ✅ Using existing account: \(accountName)")
            } else {
                // Create new account
                creditCardAccount = CDAccount(context: viewModel.viewContext)
                creditCardAccount.id = UUID()
                creditCardAccount.accountName = accountName
                creditCardAccount.accountType = AccountType.creditCard.rawValue
                creditCardAccount.balance = -billInfo.totalAmount
                creditCardAccount.creditLimit = billInfo.creditLimit ?? 0
                
                print("DEBUG: ✅ Created new account: \(accountName)")
            }
            
            // Save the account first
            try viewModel.performBatchedSave()
            viewModel.viewContext.refresh(creditCardAccount, mergeChanges: true)
            
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
                    let accountInViewContext = viewModel.viewContext.object(with: creditCardAccount.objectID) as! CDAccount
                    
                    // Add SBI Card tag and statement date to all transactions
                    let dateFormatter = ISO8601DateFormatter()
                    let statementDateString = dateFormatter.string(from: billInfo.statementDate)
                    let sbiTaggedNotes = "[SBI Card] [STMT:\(statementDateString)] \(transaction.description)"
                    
                    viewModel.addTransaction(
                        amount: transaction.amount,
                        category: TransactionCategory(rawValue: transaction.category),
                        isCredit: false,
                        account: accountInViewContext,
                        notes: sbiTaggedNotes,
                        date: transaction.date
                    )
                    
                    print("DEBUG: ✅ Added transaction: \(transaction.description) - ₹\(transaction.amount)")
                }
            }
            
            // Update balance ONLY if this statement is newer than the last one
            let finalAccount = viewModel.viewContext.object(with: creditCardAccount.objectID) as! CDAccount
            let metadata = finalAccount.metadataDictionary
            
            var shouldUpdateBalance = true
            if let lastStatementDateString = metadata["lastStatementDate"],
               let lastStatementDate = dateFormatter.date(from: lastStatementDateString) {
                // Only update if this statement is newer or same date
                shouldUpdateBalance = billInfo.statementDate >= lastStatementDate
                print("DEBUG: Last statement: \(lastStatementDate), Current: \(billInfo.statementDate), Will update: \(shouldUpdateBalance)")
            }
            
            if shouldUpdateBalance {
                finalAccount.balance = -billInfo.totalAmount
                print("DEBUG: ✅ Updated account balance to: ₹\(billInfo.totalAmount)")
            } else {
                print("DEBUG: ⏭️ Skipped balance update - older statement")
            }
            
            // Save bill metadata
            saveBillMetadata(account: finalAccount, billInfo: billInfo, pdfFileName: pdfFileName)
            
            // Save context
            try viewModel.performBatchedSave()
            viewModel.forceSyncPendingSaves()
            
            print("DEBUG: ✅ Successfully processed SBI Card statement: \(pdfFileName)")
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            return true
            
        } catch {
            print("DEBUG: ❌ Error processing SBI Card PDF \(pdfFileName): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }
    
    /// Check if a transaction is a payment (credit) transaction
    private func isPaymentTransaction(_ description: String) -> Bool {
        let paymentKeywords = [
            "PAYMENT RECEIVED", "BBPS PAYMENT", "PAYMENT THANK YOU",
            "CREDIT RECEIVED", "AMOUNT RECEIVED", "PAYMENT PROCESSED",
            "ONLINE PAYMENT", "NEFT PAYMENT", "RTGS PAYMENT", "UPI PAYMENT",
            "IMPS PAYMENT", "CHEQUE PAYMENT", "CASH PAYMENT", "AUTOPAY",
            "REFUND", "REVERSAL", "CASHBACK", "REWARD POINTS"
        ]
        
        let upperDescription = description.uppercased()
        return paymentKeywords.contains { upperDescription.contains($0) }
    }
    
    /// Save bill metadata to account
    private func saveBillMetadata(account: CDAccount, billInfo: CreditCardBillInfo, pdfFileName: String) {
        var metadata = account.metadataDictionary
        let dateFormatter = ISO8601DateFormatter()
        
        // Create a unique key for this statement
        let statementKey = "statement_\(dateFormatter.string(from: billInfo.statementDate))"
        
        // Check if bill already exists and preserve paid status
        var existingPaidStatus: String?
        var existingPaidDate: String?
        
        if let existingJsonString = metadata[statementKey],
           let existingJsonData = existingJsonString.data(using: .utf8),
           let existingBillData = try? JSONSerialization.jsonObject(with: existingJsonData) as? [String: String] {
            existingPaidStatus = existingBillData["manuallyPaid"]
            existingPaidDate = existingBillData["paidDate"]
            print("DEBUG: 📋 Found existing bill - Paid status: \(existingPaidStatus ?? "nil")")
        }
        
        // Create bill data dictionary
        var billData: [String: String] = [
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
        
        // Preserve existing paid status if it exists
        if let paidStatus = existingPaidStatus {
            billData["manuallyPaid"] = paidStatus
            print("DEBUG: ✅ Preserved paid status: \(paidStatus)")
        }
        if let paidDate = existingPaidDate {
            billData["paidDate"] = paidDate
            print("DEBUG: ✅ Preserved paid date: \(paidDate)")
        }
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: billData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            metadata[statementKey] = jsonString
            
            // Also save the latest statement date for balance update logic
            let lastStatementDateString = metadata["lastStatementDate"]
            let lastStatementDate = lastStatementDateString.flatMap { dateFormatter.date(from: $0) }
            
            // Only update if this statement is newer
            if let existingLastDate = lastStatementDate, billInfo.statementDate >= existingLastDate {
                metadata["lastStatementDate"] = dateFormatter.string(from: billInfo.statementDate)
            } else if lastStatementDateString == nil {
                // No previous statement date, save this one
                metadata["lastStatementDate"] = dateFormatter.string(from: billInfo.statementDate)
            }
            
            // Save metadata
            account.metadataDictionary = metadata
            
            print("DEBUG: 💾 Saved bill metadata for statement: \(billInfo.statementDate)")
            print("DEBUG: - Key: \(statementKey)")
            print("DEBUG: - Due Amount: ₹\(billInfo.dueAmount)")
            print("DEBUG: - PDF: \(pdfFileName)")
            if let paidStatus = existingPaidStatus {
                print("DEBUG: - Paid Status: \(paidStatus)")
            }
            print("DEBUG: - Total metadata keys: \(metadata.keys.count)")
        } else {
            print("DEBUG: ❌ Failed to save bill metadata for statement: \(billInfo.statementDate)")
        }
    }
    
    
    /// Search Outlook for emails containing a specific keyword (searches all folders)
    private func searchOutlookForKeyword(_ keyword: String) async throws -> [EmailMessage] {
        return try await withCheckedThrowingContinuation { continuation in
            OutlookService.shared.getAccessToken { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(let token):
                    // Use Microsoft Graph search API to search all folders
                    let searchQuery = keyword
                    let encodedSearch = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
                    let urlString = "https://graph.microsoft.com/v1.0/me/messages?$top=100&$select=id,subject,receivedDateTime,bodyPreview,body,from&$search=\"\(encodedSearch)\""
                    
                    guard let url = URL(string: urlString) else {
                        continuation.resume(throwing: NSError(domain: "SBICARDManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
                        return
                    }
                    
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        guard let data = data else {
                            continuation.resume(throwing: NSError(domain: "SBICARDManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                            return
                        }
                        
                        do {
                            let decoder = JSONDecoder()
                            let graphResponse = try decoder.decode(GraphMessagesResponse.self, from: data)
                            
                            // Convert to EmailMessage format
                            let emailMessages = graphResponse.value.map { outlookMsg -> EmailMessage in
                                EmailMessage(
                                    id: outlookMsg.id,
                                    receivedDateTime: outlookMsg.receivedDateTime,
                                    subject: outlookMsg.subject,
                                    bodyPreview: outlookMsg.bodyPreview,
                                    body: nil,
                                    from: outlookMsg.from.map { from in
                                        EmailMessage.EmailFrom(
                                            emailAddress: from.emailAddress.map { addr in
                                                EmailMessage.EmailAddress(
                                                    address: addr.address,
                                                    name: nil
                                                )
                                            }
                                        )
                                    }
                                )
                            }
                            
                            continuation.resume(returning: emailMessages)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }.resume()
                }
            }
        }
    }
}

// Helper struct for Graph API response
private struct GraphMessagesResponse: Decodable {
    let value: [OutlookMessageForSearch]
}

private struct OutlookMessageForSearch: Decodable {
    let id: String
    let receivedDateTime: String
    let subject: String?
    let bodyPreview: String?
    let from: From?
    
    struct From: Decodable {
        let emailAddress: EmailAddress?
    }
    
    struct EmailAddress: Decodable {
        let address: String?
    }
}
