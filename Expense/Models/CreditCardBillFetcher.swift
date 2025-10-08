import Foundation
import PDFKit
import CoreData

// MARK: - Credit Card Bill Fetcher
class CreditCardBillFetcher {
    static let shared = CreditCardBillFetcher()
    private init() {}
    
    // Fetch and process bills for a specific card
    @MainActor
    func fetchBills(
        for account: CDAccount,
        viewModel: ExpenseViewModel? = nil,
        progressCallback: ((String) -> Void)? = nil
    ) async -> [CreditCardBill] {
        // Get user profile from AuthenticationManager
        guard let currentUser = AuthenticationManager.shared.currentUser,
              let firstName = currentUser.firstName,
              let dob = currentUser.dateOfBirth else {
            print("ERROR: User profile not found or incomplete")
            progressCallback?("Error: Please complete your profile with First Name and Date of Birth")
            return []
        }
        
        // Format DOB as DD/MM/YYYY
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let dateOfBirth = dateFormatter.string(from: dob)
        
        print("DEBUG: Using profile data - Name: \(firstName), DOB: \(dateOfBirth)")
        progressCallback?("Using profile: \(firstName)")
        
        guard let metadata = account.metadataDictionary as [String: String]?,
              let bankEmail = metadata["emailAddress"] else {
            return []
        }
        
        // Determine which email addresses to check based on bank
        let emailsToCheck: [String]
        let isICICIBank = account.metadataDictionary["bankName"]?.contains("ICICI") == true
        let isSBICard = account.metadataDictionary["bankName"]?.contains("SBI") == true
        
        if let bankName = account.metadataDictionary["bankName"], 
           let bank = CreditCardBank(rawValue: bankName) {
            emailsToCheck = [bank.rawValue]
            if isICICIBank {
                progressCallback?("Fetching emails from both Outlook and Gmail for ICICI Bank...")
            } else if isSBICard {
                progressCallback?("Searching for emails with SBI PDF attachments...")
            } else {
                progressCallback?("Fetching emails from \(bank.rawValue)...")
            }
        } else if let bankEmail = account.metadataDictionary["bankEmail"] {
            emailsToCheck = [bankEmail]
            progressCallback?("Fetching emails from \(bankEmail)...")
        } else {
            emailsToCheck = [bankEmail]
            progressCallback?("Fetching emails from \(bankEmail)...")
        }
        
        // Load existing bills to check for duplicates
        let existingBills = CreditCardBillStorage.shared.loadBills(for: account.id!)
        print("DEBUG: 📋 Found \(existingBills.count) existing bills for account \(account.id!)")
        for bill in existingBills {
            print("DEBUG: 📋 Existing: \(formatStatementPeriod(bill.statementDate)) - ₹\(bill.totalAmount)")
        }
        
        // Get the last bill load date from account metadata
        var emailFilterDate: Date? = nil
        if let lastLoadDateString = account.metadataDictionary["lastBillLoadDate"] {
            if let lastLoadDate = ISO8601DateFormatter().date(from: lastLoadDateString) {
                // Add 1 day to get tomorrow's date for email filtering
                emailFilterDate = Calendar.current.date(byAdding: .day, value: 1, to: lastLoadDate)
            }
        }
        
        if let filterDate = emailFilterDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            print("DEBUG: 📅 Last bills loaded: \(formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: filterDate)!)) - will fetch emails from \(formatter.string(from: filterDate)) onwards")
        } else {
            print("DEBUG: 📅 No previous load date found - will fetch all emails")
        }
        
        // Fetch emails from all addresses
        var allEmails: [EmailMessage] = []
        
        for emailAddress in emailsToCheck {
            print("DEBUG: Checking email address: \(emailAddress)")
            progressCallback?("Checking emails for \(emailAddress)...")
            
            // For ICICI Bank, check both Outlook and Gmail
            if isICICIBank {
                print("DEBUG: 🏦 ICICI Bank detected - checking both Outlook and Gmail")
                
                // Check Outlook
                do {
                    let outlookService = OutlookEmailServiceAdapter()
                    let outlookEmails = try await outlookService.fetchEmails(from: emailAddress)
                    let filteredOutlookEmails = outlookEmails.filter { email in
                        guard let filterDate = emailFilterDate,
                              let receivedDate = ISO8601DateFormatter().date(from: email.receivedDateTime) else {
                            return true
                        }
                        return receivedDate >= filterDate
                    }
                    allEmails.append(contentsOf: filteredOutlookEmails)
                    print("DEBUG: 📧 Outlook: Found \(outlookEmails.count) total emails, \(filteredOutlookEmails.count) new emails")
                } catch {
                    print("ERROR: Failed to fetch Outlook emails: \(error)")
                }
                
                // Check Gmail with broader query for ICICI
                do {
                    let gmailService = GmailEmailServiceAdapter()
                    let gmailEmails = try await gmailService.fetchEmails(from: "icicibank") // Broader search
                    let filteredGmailEmails = gmailEmails.filter { email in
                        guard let filterDate = emailFilterDate,
                              let receivedDate = ISO8601DateFormatter().date(from: email.receivedDateTime) else {
                            return true
                        }
                        return receivedDate >= filterDate
                    }
                    allEmails.append(contentsOf: filteredGmailEmails)
                    print("DEBUG: 📧 Gmail: Found \(gmailEmails.count) total emails, \(filteredGmailEmails.count) new emails")
                } catch {
                    print("ERROR: Failed to fetch Gmail emails: \(error)")
                }
            } else if isSBICard {
                print("DEBUG: 💳 SBI Card detected - checking both Outlook and Gmail")
                
                // Check Outlook
                do {
                    let outlookService = OutlookEmailServiceAdapter()
                    let outlookEmails = try await outlookService.fetchEmails(from: emailAddress)
                    let filteredOutlookEmails = outlookEmails.filter { email in
                        guard let filterDate = emailFilterDate,
                              let receivedDate = ISO8601DateFormatter().date(from: email.receivedDateTime) else {
                            return true
                        }
                        return receivedDate >= filterDate
                    }
                    allEmails.append(contentsOf: filteredOutlookEmails)
                    print("DEBUG: 📧 Outlook SBI: Found \(outlookEmails.count) total emails, \(filteredOutlookEmails.count) new emails")
                } catch {
                    print("ERROR: Failed to fetch Outlook SBI emails: \(error)")
                }
                
                // Check Gmail
                do {
                    let gmailService = GmailEmailServiceAdapter()
                    let gmailEmails = try await gmailService.fetchEmails(from: emailAddress)
                    let filteredGmailEmails = gmailEmails.filter { email in
                        guard let filterDate = emailFilterDate,
                              let receivedDate = ISO8601DateFormatter().date(from: email.receivedDateTime) else {
                            return true
                        }
                        return receivedDate >= filterDate
                    }
                    allEmails.append(contentsOf: filteredGmailEmails)
                    print("DEBUG: 📧 Gmail SBI: Found \(gmailEmails.count) total emails, \(filteredGmailEmails.count) new emails")
                } catch {
                    print("ERROR: Failed to fetch Gmail SBI emails: \(error)")
                }
            } else {
                // For other banks, use unified email service
                let emailService = EmailServiceManager.shared.getEmailService()
                
                do {
                    let emails = try await emailService.fetchEmails(from: emailAddress)
                    let filteredEmails = emails.filter { email in
                        guard let filterDate = emailFilterDate,
                              let receivedDate = ISO8601DateFormatter().date(from: email.receivedDateTime) else {
                            return true
                        }
                        return receivedDate >= filterDate
                    }
                    allEmails.append(contentsOf: filteredEmails)
                    print("DEBUG: Found \(emails.count) total emails, \(filteredEmails.count) new emails from \(emailAddress)")
                } catch {
                    print("ERROR: Failed to fetch emails from \(emailAddress): \(error)")
                }
            }
        }
        
        print("DEBUG: Total emails found from all sources: \(allEmails.count)")
        
        if allEmails.isEmpty {
            progressCallback?("No new emails found")
            return []
        }
        
        progressCallback?("Processing \(allEmails.count) emails...")
        
        // Remove duplicates based on subject and date
        let uniqueEmails = Array(Set(allEmails))
        print("DEBUG: After removing duplicates: \(uniqueEmails.count) emails")
        
        // Process all filtered emails
        let emailsToProcess = uniqueEmails
        if let filterDate = emailFilterDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            print("DEBUG: Found \(uniqueEmails.count) emails from \(formatter.string(from: filterDate)) onwards")
        } else {
            print("DEBUG: Found \(uniqueEmails.count) emails (fetching all)")
        }
        
        if emailsToProcess.isEmpty {
            progressCallback?("No new emails found")
            return []
        }
        
        // Process each email with PDF attachments
        var newBills: [CreditCardBill] = []
        
        for email in emailsToProcess {
            progressCallback?("Processing email from \(email.receivedDateTime)...")
            print("DEBUG: 📧 Processing email: \(email.subject)")
            print("DEBUG: 📧 Email date: \(email.receivedDateTime)")
            
            // Determine which email service to use based on email ID format
            print("DEBUG: 🔍 Fetching attachments for email: \(email.id)")
            let allAttachments: [EmailAttachment]
            do {
                // Gmail IDs are short (like "199616f75b544185")
                // Outlook IDs are long (like "AQMkADAwATM0MDAAMS0wNmE4LWVlADc3AC0wMAItMDAKAEYAAAOIsJCWStWBT4Bz6_N3vAJ3BwD70_M6ii7xTag8L6Tadyz1AAACAQwAAAD70_M6ii7xTag8L6Tadyz1AAZytxmxAAAA")
                if email.id.count < 50 {
                    // Gmail email - use Gmail service
                    print("DEBUG: 📧 Using Gmail service for email ID: \(email.id)")
                    let gmailService = GmailEmailServiceAdapter()
                    allAttachments = try await gmailService.fetchAttachments(for: email.id)
                } else {
                    // Outlook email - use Outlook service
                    print("DEBUG: 📧 Using Outlook service for email ID: \(email.id)")
                    let outlookService = OutlookEmailServiceAdapter()
                    allAttachments = try await outlookService.fetchAttachments(for: email.id)
                }
                print("DEBUG: ✅ Successfully fetched \(allAttachments.count) attachments")
            } catch {
                print("DEBUG: ❌ Failed to fetch attachments: \(error)")
                allAttachments = []
            }
            let pdfAttachments = allAttachments.filter { ($0.name ?? "").lowercased().hasSuffix(".pdf") }
            
            print("DEBUG: 📎 Found \(allAttachments.count) total attachments, \(pdfAttachments.count) PDFs")
            for attachment in allAttachments {
                print("DEBUG: 📎 Attachment: '\(attachment.name ?? "unknown")' (\(attachment.contentType ?? "unknown type"))")
            }
            for pdf in pdfAttachments {
                print("DEBUG: 📄 PDF: \(pdf.name ?? "unknown")")
            }
            
            for attachment in pdfAttachments {
                print("DEBUG: 🔄 Processing PDF: \(attachment.name ?? "unknown")")
                if let bill = await processPDFAttachment(
                    attachment,
                    email: email,
                    account: account,
                    firstName: firstName,
                    dateOfBirth: dateOfBirth
                ) {
                    print("DEBUG: ✅ Successfully created bill from PDF: \(formatStatementPeriod(bill.statementDate)) - ₹\(bill.totalAmount)")
                    // Check for duplicates in both new bills and existing bills
                    let isDuplicateInNew = isDuplicate(bill: bill, in: newBills)
                    let isDuplicateInExisting = isDuplicate(bill: bill, in: existingBills)
                    
                    if !isDuplicateInNew && !isDuplicateInExisting {
                        newBills.append(bill)
                        print("DEBUG: Added bill for \(formatStatementPeriod(bill.statementDate))")
                        
                        // Auto-sync transactions to main list if viewModel provided
                        if let viewModel = viewModel {
                            await syncBillTransactionsToMainList(
                                bill: bill,
                                account: account,
                                viewModel: viewModel
                            )
                        }
                    } else {
                        print("DEBUG: Skipping duplicate bill for \(formatStatementPeriod(bill.statementDate))")
                    }
                } else {
                    print("DEBUG: ❌ Failed to create bill from PDF: \(attachment.name ?? "unknown")")
                }
            }
        }
        
        progressCallback?("Added \(newBills.count) new bill(s)! Total: \(existingBills.count + newBills.count)")
        return newBills
    }
    
    // Sync bill transactions to main list (balance-neutral)
    @MainActor
    private func syncBillTransactionsToMainList(
        bill: CreditCardBill,
        account: CDAccount,
        viewModel: ExpenseViewModel
    ) async {
        print("DEBUG: 💳 Auto-syncing transactions from bill: \(formatStatementPeriod(bill.statementDate))")
        var addedCount = 0
        var skippedCount = 0
        
        // Re-fetch account in viewContext to ensure proper context management
        guard let accountInViewContext = viewModel.viewContext.object(with: account.objectID) as? CDAccount else {
            print("DEBUG: ❌ Failed to fetch account in viewContext")
            return
        }
        
        // Save and refresh account to ensure it's properly managed
        do {
            try viewModel.viewContext.save()
            viewModel.viewContext.refresh(accountInViewContext, mergeChanges: true)
        } catch {
            print("DEBUG: ⚠️ Failed to save/refresh account: \(error)")
        }
        
        // Fetch existing transactions for this account
        let fetchRequest = NSFetchRequest<CDTransaction>(entityName: "CDTransaction")
        fetchRequest.predicate = NSPredicate(format: "account == %@", accountInViewContext)
        let existingTransactions = (try? viewModel.viewContext.fetch(fetchRequest)) ?? []
        
        // Process bill transactions
        for transaction in bill.transactions {
            // Skip BBPS payment transactions (these are payments made to the card)
            if transaction.description.contains("BBPS PAYMENT") || 
               transaction.description.contains("MB PAYMENT") ||
               transaction.description.contains("PAYMENT RECEIVED") {
                skippedCount += 1
                print("DEBUG: 💳 Skipping payment transaction: \(transaction.description) - ₹\(transaction.amount)")
                continue
            }
            
            // Check if transaction already exists: same date, amount, and description
            let isDuplicate = existingTransactions.contains { existing in
                let sameDate = existing.date == transaction.date
                let sameAmount = existing.amount == transaction.amount
                let sameDescription = existing.wrappedNotes == transaction.description
                return sameDate && sameAmount && sameDescription
            }
            
            if isDuplicate {
                skippedCount += 1
                print("DEBUG: ⏭️ Skipping duplicate: \(transaction.description) - ₹\(transaction.amount)")
            } else {
                // Re-fetch account for each transaction to ensure context validity
                guard let freshAccount = viewModel.viewContext.object(with: account.objectID) as? CDAccount else {
                    print("DEBUG: ⚠️ Failed to re-fetch account for transaction")
                    continue
                }
                
                // Convert category string to TransactionCategory
                let transactionCategory = TransactionCategory(rawValue: transaction.category)
                
                // Create transaction directly WITHOUT adjusting balance
                // Balance should ONLY come from PDF (Credit Limit - Available Limit)
                let newTransaction = CDTransaction(context: viewModel.viewContext)
                newTransaction.id = UUID()
                newTransaction.amount = transaction.amount
                newTransaction.category = transactionCategory.rawValue
                newTransaction.isCredit = false // Credit card spending is a debit
                newTransaction.account = freshAccount
                newTransaction.notes = transaction.description
                newTransaction.date = transaction.date
                
                // Auto-categorize if category is "Other"
                if transactionCategory == .other {
                    newTransaction.autoCategorize()
                }
                
                // Save transaction WITHOUT adjusting account balance
                do {
                    try viewModel.viewContext.save()
                    addedCount += 1
                    print("DEBUG: ✅ Auto-synced: \(transaction.description) - ₹\(transaction.amount)")
                } catch {
                    print("DEBUG: ❌ Failed to save transaction: \(error)")
                }
            }
        }
        
        print("DEBUG: 💳 Auto-sync complete: Added \(addedCount), skipped \(skippedCount)")
        
        // Trigger UI refresh if transactions were added
        if addedCount > 0 {
            viewModel.objectWillChange.send()
        }
    }
    
    // Process individual PDF attachment
    private func processPDFAttachment(
        _ attachment: EmailAttachment,
        email: EmailMessage,
        account: CDAccount,
        firstName: String,
        dateOfBirth: String
    ) async -> CreditCardBill? {
        do {
            // Download PDF data using correct email service based on email ID
            print("DEBUG: 📥 Downloading PDF attachment: \(attachment.name ?? "unknown")")
            let pdfData: Data?
            if email.id.count < 50 {
                // Gmail email - use Gmail service
                print("DEBUG: 📧 Using Gmail service to download attachment")
                let gmailService = GmailEmailServiceAdapter()
                pdfData = try? await gmailService.downloadAttachment(
                    messageId: email.id,
                    attachmentId: attachment.id
                )
            } else {
                // Outlook email - use Outlook service
                print("DEBUG: 📧 Using Outlook service to download attachment")
                let outlookService = OutlookEmailServiceAdapter()
                pdfData = try? await outlookService.downloadAttachment(
                    messageId: email.id,
                    attachmentId: attachment.id
                )
            }
            
            guard let pdfData = pdfData else {
                print("ERROR: No data downloaded for attachment")
                return nil
            }
            
            print("DEBUG: 📄 Downloaded PDF data: \(pdfData.count) bytes")
            
            // Save to temporary file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).pdf")
            try pdfData.write(to: tempURL)
            print("DEBUG: 💾 Saved PDF to temporary file: \(tempURL.path)")
            
            // Parse PDF with dynamic password and card number validation
            guard let bill = await parsePDFBill(
                at: tempURL,
                firstName: firstName,
                dateOfBirth: dateOfBirth,
                account: account,
                email: email
            ) else {
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            return bill
            
        } catch {
            print("ERROR: Failed to process PDF attachment: \(error)")
            return nil
        }
    }
    
    // Check if bill is duplicate based on statement date (same month/year)
    // Simple logic: if same month/year exists, it's a duplicate (keep first one processed)
    private func isDuplicate(bill: CreditCardBill, in bills: [CreditCardBill]) -> Bool {
        let calendar = Calendar.current
        let billComponents = calendar.dateComponents([.year, .month], from: bill.statementDate)
        
        let duplicateBill = bills.first { existingBill in
            let existingComponents = calendar.dateComponents([.year, .month], from: existingBill.statementDate)
            return billComponents.year == existingComponents.year && 
                   billComponents.month == existingComponents.month
        }
        
        if let duplicate = duplicateBill {
            print("DEBUG: 🔄 Skipping duplicate for same month: \(formatStatementPeriod(bill.statementDate))")
            print("DEBUG: 🔄 Existing bill: \(formatStatementPeriod(duplicate.statementDate)) - ₹\(duplicate.totalAmount) (Account: \(duplicate.cardAccountId))")
            print("DEBUG: 🔄 New bill: \(formatStatementPeriod(bill.statementDate)) - ₹\(bill.totalAmount) (Account: \(bill.cardAccountId))")
            return true
        }
        
        return false
    }
    
    // Format statement period for logging
    private func formatStatementPeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
    
    // Parse PDF bill with password
    private func parsePDFBill(
        at url: URL,
        firstName: String,
        dateOfBirth: String,
        account: CDAccount,
        email: EmailMessage? = nil
    ) async -> CreditCardBill? {
        // Get card number from account metadata for SBI Card password generation
        let accountMetadata = account.metadataDictionary
        let cardNumber = accountMetadata["cardNumber"] ?? accountMetadata["fullCardNumber"]
        
        // Update PDFTransactionParser with user details and card number
        PDFTransactionParser.shared.updateUserDetails(
            firstName: firstName,
            dateOfBirth: dateOfBirth,
            cardNumber: cardNumber
        )
        
        // Use the existing working parser
        guard var billInfo = PDFTransactionParser.shared.parseCreditCardBill(from: url) else {
            print("ERROR: Failed to parse PDF")
            return nil
        }
        
        // If PDF has no financial data (duplicate statement), try to extract from email content
        if billInfo.dueAmount == 0 && billInfo.creditLimit == nil, let email = email {
            print("DEBUG: 💡 PDF has no financial data, checking email content...")
            if let emailFinancialData = extractFinancialDataFromEmail(email: email) {
                print("DEBUG: 💰 Found financial data in email: Due=₹\(emailFinancialData.totalDue), Min=₹\(emailFinancialData.minimumDue)")
                
                // Update billInfo with email data
                billInfo = CreditCardBillInfo(
                    bankName: billInfo.bankName,
                    cardNumber: billInfo.cardNumber,
                    statementDate: billInfo.statementDate,
                    dueDate: emailFinancialData.dueDate ?? billInfo.dueDate,
                    totalAmount: emailFinancialData.totalDue,
                    dueAmount: emailFinancialData.minimumDue,
                    creditLimit: billInfo.creditLimit,
                    currentUsage: emailFinancialData.totalDue, // Use total due as current usage
                    availableLimit: billInfo.availableLimit,
                    transactions: billInfo.transactions
                )
            }
        }
        
        // CRITICAL: Validate card number - only process bills for THIS specific card
        if let accountCardNumber = accountMetadata["cardNumber"] ?? accountMetadata["fullCardNumber"] {
            // Get last 4 digits from account
            let last4Digits = String(accountCardNumber.suffix(4))
            
            // Get digits from bill (bill card number format is like "451457******6988" or "XX18")
            let billCardDigits = billInfo.cardNumber.replacingOccurrences(of: "*", with: "")
                                                     .replacingOccurrences(of: "X", with: "")
                                                     .replacingOccurrences(of: "x", with: "")
            
            // Special handling for HDFC duplicate statements that show ****0000
            let isHDFCDuplicateStatement = billCardDigits == "0000" && accountMetadata["bankName"]?.contains("HDFC") == true
            
            // For HDFC cards, also accept bills that match the account card number OR are duplicate statements
            let isHDFCCard = accountMetadata["bankName"]?.contains("HDFC") == true
            
            if isHDFCDuplicateStatement {
                print("DEBUG: ✅ Processing HDFC duplicate statement (****0000) for account ****\(last4Digits)")
            } else if isHDFCCard && billCardDigits.contains(last4Digits) {
                print("DEBUG: ✅ Processing HDFC statement (****\(billCardDigits)) for account ****\(last4Digits)")
            } else if isHDFCCard {
                // For HDFC, accept ANY bill since they use different formats
                print("DEBUG: ✅ Processing HDFC statement (any format) for HDFC account ****\(last4Digits)")
            } else {
                // Compare: if bill has only 2 digits (SBI Card), compare last 2; otherwise compare last 4
                let digitsToCompare = min(billCardDigits.count, 4)
                let billSuffix = String(billCardDigits.suffix(digitsToCompare))
                let accountSuffix = String(last4Digits.suffix(digitsToCompare))
                
                print("DEBUG: 🔍 Card matching details:")
                print("DEBUG: 🔍 Bill card digits: '\(billCardDigits)' (length: \(billCardDigits.count))")
                print("DEBUG: 🔍 Account last 4: '\(last4Digits)'")
                print("DEBUG: 🔍 Digits to compare: \(digitsToCompare)")
                print("DEBUG: 🔍 Bill suffix: '\(billSuffix)'")
                print("DEBUG: 🔍 Account suffix: '\(accountSuffix)'")
                
                if billSuffix != accountSuffix {
                    print("DEBUG: ❌ Skipping bill for card ****\(billSuffix) - does not match account card ****\(accountSuffix)")
                    return nil
                } else {
                    print("DEBUG: ✅ Bill card ****\(billSuffix) matches account card ****\(accountSuffix)")
                }
            }
        }
        
        // Convert CreditCardBillInfo to CreditCardBill
        let transactions = billInfo.transactions.map { transaction in
            BillTransaction(
                date: transaction.date,
                description: transaction.description,
                amount: transaction.amount,
                category: transaction.category
            )
        }
        
        // Calculate bill amount from transactions if PDF has no financial data
        let calculatedAmount: Double
        if billInfo.dueAmount > 0 {
            calculatedAmount = billInfo.dueAmount
        } else {
            // For HDFC duplicate statements, calculate from transactions
            let debitTransactions = transactions.filter { $0.amount > 0 && !$0.description.contains("CREDIT") }
            calculatedAmount = debitTransactions.reduce(0) { $0 + $1.amount }
            print("DEBUG: 💰 Calculated bill amount from transactions: ₹\(calculatedAmount) (PDF had ₹0)")
        }
        
        let bill = CreditCardBill(
            cardAccountId: account.id!,
            statementDate: billInfo.statementDate,
            dueDate: billInfo.dueDate,
            totalAmount: calculatedAmount,
            minimumDue: calculatedAmount * 0.05, // 5% minimum
            availableLimit: billInfo.availableLimit ?? 0,
            creditLimit: billInfo.creditLimit ?? 0,
            currentUsage: billInfo.currentUsage ?? calculatedAmount,
            isPaid: false,
            pdfFileName: url.lastPathComponent,
            transactions: transactions
        )
        
        print("DEBUG: 🎯 Created bill with Account ID: \(account.id!) for card ****\(billInfo.cardNumber.suffix(4))")
        return bill
    }
    
    // Extract financial data from HDFC email content
    private func extractFinancialDataFromEmail(email: EmailMessage) -> (totalDue: Double, minimumDue: Double, dueDate: Date?)? {
        let bodyText = email.body?.content ?? ""
        let bodyPreview = email.bodyPreview ?? ""
        let emailContent = bodyPreview + " " + bodyText
        
        // Extract total amount due
        var totalDue: Double = 0
        let totalDuePatterns = [
            #"Total amount\s*due[^\d]*([\d,]+\.?\d*)"#,
            #"Total Amount Due[^\d]*([\d,]+\.?\d*)"#,
            #"Amount Due[^\d]*([\d,]+\.?\d*)"#
        ]
        
        for pattern in totalDuePatterns {
            if let match = emailContent.range(of: pattern, options: [String.CompareOptions.regularExpression, String.CompareOptions.caseInsensitive]) {
                let matchText = String(emailContent[match])
                let numbers = matchText.replacingOccurrences(of: ",", with: "")
                if let extracted = Double(numbers.components(separatedBy: CharacterSet.decimalDigits.inverted).joined().prefix(10)) {
                    totalDue = extracted
                    print("DEBUG: 📧 Extracted total due from email: ₹\(totalDue)")
                    break
                }
            }
        }
        
        // Extract minimum amount due
        var minimumDue: Double = 0
        let minimumDuePatterns = [
            #"Minimum amount\s*due[^\d]*([\d,]+\.?\d*)"#,
            #"Minimum Due[^\d]*([\d,]+\.?\d*)"#,
            #"Min\. Due[^\d]*([\d,]+\.?\d*)"#
        ]
        
        for pattern in minimumDuePatterns {
            if let match = emailContent.range(of: pattern, options: [String.CompareOptions.regularExpression, String.CompareOptions.caseInsensitive]) {
                let matchText = String(emailContent[match])
                let numbers = matchText.replacingOccurrences(of: ",", with: "")
                if let extracted = Double(numbers.components(separatedBy: CharacterSet.decimalDigits.inverted).joined().prefix(10)) {
                    minimumDue = extracted
                    print("DEBUG: 📧 Extracted minimum due from email: ₹\(minimumDue)")
                    break
                }
            }
        }
        
        // Extract due date
        var dueDate: Date?
        let dueDatePatterns = [
            #"Payment due date[^\d]*(\d{2}-\d{2}-\d{4})"#,
            #"Due date[^\d]*(\d{2}-\d{2}-\d{4})"#,
            #"(\d{2}-\d{2}-\d{4})"#
        ]
        
        for pattern in dueDatePatterns {
            if let match = emailContent.range(of: pattern, options: [String.CompareOptions.regularExpression, String.CompareOptions.caseInsensitive]) {
                let matchText = String(emailContent[match])
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd-MM-yyyy"
                
                // Extract just the date part
                if let dateMatch = matchText.range(of: #"\d{2}-\d{2}-\d{4}"#, options: [String.CompareOptions.regularExpression]) {
                    let dateString = String(matchText[dateMatch])
                    if let parsedDate = dateFormatter.date(from: dateString) {
                        dueDate = parsedDate
                        print("DEBUG: 📧 Extracted due date from email: \(parsedDate)")
                        break
                    }
                }
            }
        }
        
        // Return data if we found at least the amounts
        if totalDue > 0 || minimumDue > 0 {
            return (totalDue: totalDue, minimumDue: minimumDue, dueDate: dueDate)
        }
        
        return nil
    }
}
