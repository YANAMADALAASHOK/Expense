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
            print("ERROR: No email address found in metadata")
            return []
        }
        
        progressCallback?("Fetching emails from \(bankEmail)...")
        
        // Load existing bills to check for duplicates
        let existingBills = CreditCardBillStorage.shared.loadBills(for: account.id!)
        
        // Get the latest bill date to only fetch newer emails
        let latestBillDate = existingBills.map { $0.statementDate }.max()
        if let latestDate = latestBillDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            print("DEBUG: Latest bill date: \(formatter.string(from: latestDate))")
            progressCallback?("Checking for bills after \(formatter.string(from: latestDate))...")
        } else {
            progressCallback?("Fetching all bills...")
        }
        
        var allBills: [CreditCardBill] = []
        let providers: [EmailServiceManager.EmailProvider] = [.outlook, .gmail]
        
        // Try both email providers
        for provider in providers {
            let providerName = provider == .outlook ? "Outlook" : "Gmail"
            progressCallback?("Checking \(providerName)...")
            
            // Switch to provider
            let originalProvider = EmailServiceManager.shared.preferredProvider
            EmailServiceManager.shared.preferredProvider = provider
            defer { EmailServiceManager.shared.preferredProvider = originalProvider }
            
            do {
                let emailService = EmailServiceManager.shared.getEmailService()
                
                // Fetch emails from the bank's email address (from account metadata)
                let emails = try await emailService.fetchEmails(from: bankEmail)
                
                // Filter emails to only process those newer than latest bill
                let emailsToProcess: [EmailMessage]
                if let latestDate = latestBillDate {
                    // Only process emails received after the latest bill date
                    emailsToProcess = emails.filter { email in
                        if let receivedDate = ISO8601DateFormatter().date(from: email.receivedDateTime) {
                            return receivedDate > latestDate
                        }
                        return false
                    }
                    print("DEBUG: Found \(emails.count) total emails, \(emailsToProcess.count) new emails after latest bill")
                } else {
                    // No existing bills, process all emails
                    emailsToProcess = emails
                    print("DEBUG: Found \(emails.count) emails in \(providerName) (fetching all)")
                }
                
                if emailsToProcess.isEmpty {
                    progressCallback?("No new emails found in \(providerName)")
                    continue
                }
                
                // Process each email with PDF attachments
                for email in emailsToProcess {
                    progressCallback?("Processing email from \(email.receivedDateTime)...")
                    
                    // Get attachments
                    let attachments = try await emailService.fetchAttachments(for: email.id)
                    
                    // Find PDF attachments
                    let pdfAttachments = attachments.filter { ($0.name ?? "").lowercased().hasSuffix(".pdf") }
                    
                    for attachment in pdfAttachments {
                        if let bill = await processPDFAttachment(
                            attachment,
                            email: email,
                            account: account,
                            firstName: firstName,
                            dateOfBirth: dateOfBirth,
                            emailService: emailService
                        ) {
                            // Check for duplicates in both new bills and existing bills
                            let isDuplicateInNew = isDuplicate(bill: bill, in: allBills)
                            let isDuplicateInExisting = isDuplicate(bill: bill, in: existingBills)
                            
                            if !isDuplicateInNew && !isDuplicateInExisting {
                                allBills.append(bill)
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
                        }
                    }
                }
            } catch {
                print("ERROR: Failed to fetch from \(providerName): \(error)")
            }
        }
        
        // Merge new bills with existing bills
        var mergedBills = existingBills
        for newBill in allBills {
            if !isDuplicate(bill: newBill, in: mergedBills) {
                mergedBills.append(newBill)
            }
        }
        
        // Sort bills by statement date (oldest first)
        mergedBills.sort { $0.statementDate < $1.statementDate }
        
        // Save merged bills
        CreditCardBillStorage.shared.saveBills(mergedBills, for: account.id!)
        
        // Auto-mark old bills as paid (except the latest one)
        if let latestBill = mergedBills.last {
            CreditCardBillStorage.shared.autoMarkOldBillsAsPaid(
                for: account.id!,
                exceptBillId: latestBill.id
            )
        }
        
        let newBillsCount = allBills.count
        let totalBillsCount = mergedBills.count
        
        if newBillsCount > 0 {
            progressCallback?("Added \(newBillsCount) new bill(s)! Total: \(totalBillsCount)")
        } else {
            progressCallback?("No new bills found. Total: \(totalBillsCount)")
        }
        
        return mergedBills
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
        dateOfBirth: String,
        emailService: any EmailServiceProtocol
    ) async -> CreditCardBill? {
        do {
            // Download PDF data
            let pdfData = try await emailService.downloadAttachment(
                messageId: email.id,
                attachmentId: attachment.id
            )
            
            guard let pdfData = pdfData else {
                print("ERROR: No data downloaded for attachment")
                return nil
            }
            
            // Save to temporary file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).pdf")
            try pdfData.write(to: tempURL)
            
            // Parse PDF with dynamic password and card number validation
            guard let bill = await parsePDFBill(
                at: tempURL,
                firstName: firstName,
                dateOfBirth: dateOfBirth,
                account: account
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
    private func isDuplicate(bill: CreditCardBill, in bills: [CreditCardBill]) -> Bool {
        let calendar = Calendar.current
        let billComponents = calendar.dateComponents([.year, .month], from: bill.statementDate)
        
        return bills.contains { existingBill in
            let existingComponents = calendar.dateComponents([.year, .month], from: existingBill.statementDate)
            return billComponents.year == existingComponents.year && 
                   billComponents.month == existingComponents.month
        }
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
        account: CDAccount
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
        guard let billInfo = PDFTransactionParser.shared.parseCreditCardBill(from: url) else {
            print("ERROR: Failed to parse PDF")
            return nil
        }
        
        // CRITICAL: Validate card number - only process bills for THIS specific card
        if let accountCardNumber = accountMetadata["cardNumber"] ?? accountMetadata["fullCardNumber"] {
            // Get last 4 digits from account
            let last4Digits = String(accountCardNumber.suffix(4))
            
            // Get digits from bill (bill card number format is like "451457******6988" or "XX18")
            let billCardDigits = billInfo.cardNumber.replacingOccurrences(of: "*", with: "")
                                                     .replacingOccurrences(of: "X", with: "")
                                                     .replacingOccurrences(of: "x", with: "")
            
            // Compare: if bill has only 2 digits (SBI Card), compare last 2; otherwise compare last 4
            let digitsToCompare = min(billCardDigits.count, 4)
            let billSuffix = String(billCardDigits.suffix(digitsToCompare))
            let accountSuffix = String(last4Digits.suffix(digitsToCompare))
            
            if billSuffix != accountSuffix {
                print("DEBUG: ❌ Skipping bill for card ****\(billSuffix) - does not match account card ****\(accountSuffix)")
                return nil
            } else {
                print("DEBUG: ✅ Bill card ****\(billSuffix) matches account card ****\(accountSuffix)")
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
        
        return CreditCardBill(
            cardAccountId: account.id!,
            statementDate: billInfo.statementDate,
            dueDate: billInfo.dueDate,
            totalAmount: billInfo.dueAmount,
            minimumDue: billInfo.dueAmount * 0.05, // 5% minimum
            availableLimit: billInfo.availableLimit ?? 0,
            creditLimit: billInfo.creditLimit ?? 0,
            currentUsage: billInfo.currentUsage ?? billInfo.totalAmount,
            isPaid: false,
            pdfFileName: url.lastPathComponent,
            transactions: transactions
        )
    }
    
}
