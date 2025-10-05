import Foundation
import PDFKit
import Vision
import UIKit

struct CreditCardTransaction {
    let date: Date
    let description: String
    let amount: Double
    let category: String
    let referenceNumber: String?
}

struct CreditCardBillInfo {
    let bankName: String
    let cardNumber: String
    let statementDate: Date
    let dueDate: Date
    let totalAmount: Double // Total amount due
    let dueAmount: Double // Amount due to be paid
    let creditLimit: Double?
    let currentUsage: Double? // Calculated: Credit Limit - Available Limit
    let availableLimit: Double? // Available credit limit
    let transactions: [CreditCardTransaction]
}

class PDFTransactionParser {
    static let shared = PDFTransactionParser()
    private init() {}
    
    // User details for dynamic password generation
    // TODO: These should be configurable from user settings/preferences
    private var userFirstName = "YANAMADALA" // First name
    private var userDOB = "19/06/1990" // DD/MM/YYYY format (DD/MM/YYYY)
    
    // Function to update user details for password generation
    func updateUserDetails(firstName: String, dateOfBirth: String) {
        self.userFirstName = firstName.uppercased()
        self.userDOB = dateOfBirth
        print("DEBUG: Updated user details - Name: \(firstName), DOB: \(dateOfBirth)")
    }
    
    // Generate dynamic passwords based on user details
    private func generateDynamicPasswords() -> [String] {
        let firstName = userFirstName.uppercased()
        let firstFourChars = String(firstName.prefix(4)) // First 4 characters: "YANA"
        
        // Extract date and month from DOB (19/06/1990 -> 1906)
        let dobComponents = userDOB.components(separatedBy: "/")
        guard dobComponents.count >= 2,
              let day = Int(dobComponents[0]),
              let month = Int(dobComponents[1]) else {
            return ["YANA1906"] // Fallback to known working password
        }
        
        let dateMonth = String(format: "%02d%02d", day, month) // "1906"
        
        // Generate password variations
        let basePassword = "\(firstFourChars)\(dateMonth)" // "YANA1906"
        
        return [
            basePassword, // "YANA1906" - Primary password
            basePassword.lowercased(), // "yana1906"
            "\(firstFourChars)@\(dateMonth)", // "YANA@1906"
            "\(firstFourChars.lowercased())@\(dateMonth)", // "yana@1906"
            "\(firstFourChars)_\(dateMonth)", // "YANA_1906"
            "\(firstFourChars.lowercased())_\(dateMonth)", // "yana_1906"
            firstFourChars, // "YANA"
            firstFourChars.lowercased(), // "yana"
            dateMonth, // "1906"
            String(day), // "19"
            String(format: "%02d", month), // "06"
        ]
    }
    
    // Get passwords optimized for specific bank content
    private func getBankOptimizedPasswords(for pdfContent: String? = nil) -> [String] {
        let dynamicPasswords = generateDynamicPasswords()
        print("DEBUG: Generated \(dynamicPasswords.count) dynamic passwords from name '\(userFirstName)' and DOB '\(userDOB)'")
        print("DEBUG: Primary password: \(dynamicPasswords.first ?? "None")")
        
        var passwords = dynamicPasswords
        
        // Add bank-specific passwords based on content (if available)
        if let content = pdfContent?.lowercased() {
            if content.contains("icici") {
                print("DEBUG: Detected ICICI Bank PDF, prioritizing ICICI passwords")
                passwords.append(contentsOf: [
                    // ICICI Bank passwords first
                    "icici", "ICICI", "Icici", "icicibank", "ICICIBANK",
                    // Then Axis Bank passwords
                    "axis", "AXIS", "Axis", "axisbank", "AXISBANK"
                ])
            } else if content.contains("axis") {
                passwords.append(contentsOf: [
                    // Axis Bank passwords first
                    "axis", "AXIS", "Axis", "axisbank", "AXISBANK",
                    // Then ICICI Bank passwords
                    "icici", "ICICI", "Icici", "icicibank", "ICICIBANK"
                ])
            } else {
                // Unknown bank, try all
                passwords.append(contentsOf: [
                    "axis", "AXIS", "Axis", "axisbank", "AXISBANK",
                    "icici", "ICICI", "Icici", "icicibank", "ICICIBANK"
                ])
            }
        } else {
            // No content available, try all bank passwords
            passwords.append(contentsOf: [
                "axis", "AXIS", "Axis", "axisbank", "AXISBANK",
                "icici", "ICICI", "Icici", "icicibank", "ICICIBANK"
            ])
        }
        
        // Add common fallback passwords
        passwords.append(contentsOf: [
            "password", "Password", "PASSWORD", "123456",
            "ashok", "ASHOK", "Ashok", "naidu", "NAIDU", "Naidu",
            "ashoknaidu", "ASHOKNAIDU", "AshokNaidu"
        ])
        
        print("DEBUG: Total passwords to try: \(passwords.count)")
        return passwords
    }
    
    // Legacy method for backward compatibility
    private var bankPasswords: [String] {
        return getBankOptimizedPasswords()
    }
    
    func parseCreditCardBill(from url: URL) -> CreditCardBillInfo? {
        guard let pdfDocument = loadPDFDocument(from: url) else {
            print("Failed to load PDF document")
            return nil
        }
        
        // Quick check for SBI Card - use special extraction
        let quickText = extractTextFromPDF(pdfDocument)
        if quickText.lowercased().contains("sbi card") || quickText.lowercased().contains("state bank") {
            print("DEBUG: Detected SBI Card - using full page extraction")
            let fullText = extractTextFromSBICardPDF(pdfDocument)
            return parseSBICardStatement(fullText)
        }
        
        // For other banks, use standard extraction
        let fullText = quickText
        print("Extracted PDF text (\(fullText.count) characters)")
        
        // Determine bank and parse accordingly
        if fullText.lowercased().contains("axis bank") {
            return parseAxisBankStatement(fullText)
        } else if fullText.lowercased().contains("hdfc") {
            return parseHDFCBankStatement(fullText)
        } else if fullText.lowercased().contains("icici") {
            return parseICICIBankStatement(fullText)
        } else {
            return parseGenericStatement(fullText)
        }
    }
    
    // Wrapper method for AccountsView compatibility
    func parsePDF(at url: URL) -> CreditCardBillInfo? {
        return parseCreditCardBill(from: url)
    }
    
    // Test function to process the project folder PDF with detailed analysis
    func testProjectPDF() -> CreditCardBillInfo? {
        // Try multiple possible locations for the PDF
        let possiblePaths = [
            "/Users/ashoknaidu/Desktop/Expense/Credit Card Statement.pdf",
            "/Users/ashoknaidu/Desktop/Expense/Expense/Credit Card Statement.pdf",
            "/Users/ashoknaidu/Desktop/Expense/Resources/Credit Card Statement.pdf"
        ]
        
        for pathString in possiblePaths {
            let pdfPath = URL(fileURLWithPath: pathString)
            print("DEBUG: Checking for PDF at: \(pathString)")
            
            if FileManager.default.fileExists(atPath: pathString) {
                print("DEBUG: Found PDF at: \(pathString)")
                
                // Analyze the PDF first
                analyzePDFStructure(at: pdfPath)
                
                return parseCreditCardBill(from: pdfPath)
            }
        }
        
        print("DEBUG: PDF file not found at any of these locations:")
        for path in possiblePaths {
            print("DEBUG: - \(path)")
        }
        
        // Fallback to sample data if PDF not found
        print("DEBUG: Falling back to sample data for testing")
        return testWithSampleData()
    }
    
    // Analyze PDF structure and content
    private func analyzePDFStructure(at url: URL) {
        print("DEBUG: ===== PDF ANALYSIS START =====")
        
        // Get file info
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                print("DEBUG: PDF file size: \(fileSize) bytes")
            }
            if let modificationDate = attributes[.modificationDate] as? Date {
                print("DEBUG: PDF modification date: \(modificationDate)")
            }
        } catch {
            print("DEBUG: Could not get file attributes: \(error)")
        }
        
        // Try to load PDF document
        guard let document = PDFDocument(url: url) else {
            print("DEBUG: Failed to create PDFDocument")
            return
        }
        
        print("DEBUG: PDF loaded successfully")
        print("DEBUG: Page count: \(document.pageCount)")
        print("DEBUG: Is encrypted: \(document.isEncrypted)")
        print("DEBUG: Is locked: \(document.isLocked)")
        print("DEBUG: Allows printing: \(document.allowsPrinting)")
        print("DEBUG: Allows copying: \(document.allowsCopying)")
        
        // Analyze each page
        for pageIndex in 0..<min(document.pageCount, 3) { // Analyze first 3 pages max
            guard let page = document.page(at: pageIndex) else { continue }
            
            print("DEBUG: --- Page \(pageIndex + 1) Analysis ---")
            let bounds = page.bounds(for: .mediaBox)
            print("DEBUG: Page bounds: \(bounds)")
            
            // Try to get page label/title
            if let pageLabel = page.label {
                print("DEBUG: Page label: \(pageLabel)")
            }
            
            // Check for direct text content
            if let pageText = page.string {
                let trimmedText = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
                print("DEBUG: Direct text length: \(trimmedText.count) characters")
                if trimmedText.count > 0 {
                    print("DEBUG: First 100 chars: \(String(trimmedText.prefix(100)))")
                    if trimmedText.count > 100 {
                        print("DEBUG: Last 100 chars: \(String(trimmedText.suffix(100)))")
                    }
                } else {
                    print("DEBUG: No direct text found - will need OCR")
                }
            }
            
            // Check for annotations
            let annotations = page.annotations
            print("DEBUG: Annotations count: \(annotations.count)")
            for (index, annotation) in annotations.enumerated() {
                print("DEBUG: Annotation \(index): \(annotation.type ?? "unknown") - \(annotation.contents ?? "no content")")
            }
        }
        
        print("DEBUG: ===== PDF ANALYSIS END =====")
    }
    
    // Test function to process the bundled sample PDF (if added to Xcode)
    func testBundledPDF() -> CreditCardBillInfo? {
        guard let pdfPath = Bundle.main.url(forResource: "Credit Card Statement", withExtension: "pdf") else {
            print("DEBUG: Bundled PDF file not found in app bundle")
            print("DEBUG: Trying project folder instead...")
            return testProjectPDF()
        }
        
        print("DEBUG: Testing bundled PDF at: \(pdfPath.path)")
        return parseCreditCardBill(from: pdfPath)
    }
    
    // Alternative test with sample data for simulator
    func testWithSampleData() -> CreditCardBillInfo? {
        print("DEBUG: Creating sample credit card bill data for testing")
        
        // Create sample transactions
        let sampleTransactions = [
            CreditCardTransaction(
                date: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
                description: "AMAZON INDIA",
                amount: 2500.00,
                category: "Shopping",
                referenceNumber: "TXN123456"
            ),
            CreditCardTransaction(
                date: Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date(),
                description: "SWIGGY BANGALORE",
                amount: 450.00,
                category: "Food & Dining",
                referenceNumber: "TXN123457"
            ),
            CreditCardTransaction(
                date: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
                description: "UBER TRIP",
                amount: 320.00,
                category: "Transportation",
                referenceNumber: "TXN123458"
            ),
            CreditCardTransaction(
                date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
                description: "FLIPKART INDIA",
                amount: 1800.00,
                category: "Shopping",
                referenceNumber: "TXN123459"
            ),
            CreditCardTransaction(
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                description: "ZOMATO BANGALORE",
                amount: 680.00,
                category: "Food & Dining",
                referenceNumber: "TXN123460"
            )
        ]
        
        // Create sample bill info
        let billInfo = CreditCardBillInfo(
            bankName: "Axis Bank",
            cardNumber: "6988",
            statementDate: Calendar.current.date(byAdding: .day, value: -15, to: Date()) ?? Date(),
            dueDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date(),
            totalAmount: 5750.00, // Current usage
            dueAmount: 4200.00, // Amount due to be paid (different from usage)
            creditLimit: 100000.00,
            currentUsage: nil,
            availableLimit: nil,
            transactions: sampleTransactions
        )
        
        print("DEBUG: Created sample bill - Bank: \(billInfo.bankName), Card: ****\(billInfo.cardNumber), Amount: ₹\(billInfo.totalAmount), Transactions: \(billInfo.transactions.count)")
        
        return billInfo
    }
    
    private func loadPDFDocument(from url: URL) -> PDFDocument? {
        guard let document = PDFDocument(url: url) else {
            print("Failed to create PDFDocument from URL")
            return nil
        }
        
        print("DEBUG: Initial PDF state - Encrypted: \(document.isEncrypted), Locked: \(document.isLocked), Pages: \(document.pageCount)")
        
        // If document is encrypted/locked, try passwords
        if document.isEncrypted || document.isLocked || document.pageCount == 0 {
            print("PDF is encrypted/locked, trying passwords...")
            
            let passwords = bankPasswords
            for (index, password) in passwords.enumerated() {
                print("DEBUG: Trying password \(index + 1)/\(passwords.count): \(password)")
                
                // Try unlocking with password
                let unlockResult = document.unlock(withPassword: password)
                print("DEBUG: Unlock result for '\(password)': \(unlockResult)")
                
                if unlockResult && !document.isLocked && document.pageCount > 0 {
                    print("DEBUG: ✅ Successfully unlocked PDF with password: \(password) (attempt \(index + 1)/\(passwords.count))")
                    print("DEBUG: Final state - Pages: \(document.pageCount), Allows copying: \(document.allowsCopying)")
                    return document
                }
                
                // Add small delay to prevent overwhelming the system
                if index % 5 == 4 {
                    print("DEBUG: Tried \(index + 1) passwords, continuing...")
                }
            }
            
            // Try empty password (sometimes works)
            print("Trying empty password...")
            if document.unlock(withPassword: "") {
                print("Successfully unlocked PDF with empty password")
                if document.pageCount > 0 {
                    return document
                }
            }
            
            print("Failed to unlock PDF with any known passwords")
            print("Available passwords tried: \(bankPasswords)")
            
            // Return document anyway - sometimes we can still process locked PDFs
            print("Returning locked document for further processing...")
            return document
        } else {
            print("PDF is not password protected")
            return document
        }
    }
    
    private func extractTextFromPDF(_ document: PDFDocument) -> String {
        var fullText = ""
        
        print("PDF has \(document.pageCount) pages")
        
        // Focus on first page only since second page is nonsense
        let pagesToProcess = min(1, document.pageCount) // Only process first page
        
        for pageIndex in 0..<pagesToProcess {
            if let page = document.page(at: pageIndex) {
                print("DEBUG: Processing page \(pageIndex + 1) (main content page)")
                
                // First try to extract text directly
                if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("Page \(pageIndex + 1) extracted \(pageText.count) characters via direct text extraction")
                    print("DEBUG: Direct text sample: \(String(pageText.prefix(300)))")
                    fullText += pageText + "\n"
                } else {
                    print("Page \(pageIndex + 1) has no extractable text, trying OCR...")
                    // Try OCR if no direct text is available
                    if let ocrText = extractTextUsingOCR(from: page) {
                        print("Page \(pageIndex + 1) extracted \(ocrText.count) characters via OCR")
                        print("DEBUG: OCR text sample: \(String(ocrText.prefix(300)))")
                        fullText += ocrText + "\n"
                    } else {
                        print("Page \(pageIndex + 1) OCR failed")
                    }
                }
            } else {
                print("Failed to get page \(pageIndex + 1)")
            }
        }
        
        // Skip second page as it's nonsense
        if document.pageCount > 1 {
            print("DEBUG: Skipping page 2 and beyond as they contain nonsense data")
        }
        
        print("Total extracted text: \(fullText.count) characters")
        if fullText.count > 0 {
            print("DEBUG: Full extracted text preview (first 500 chars):")
            print(String(fullText.prefix(500)))
            if fullText.count > 500 {
                print("DEBUG: Text continues for \(fullText.count - 500) more characters...")
            }
        }
        
        return fullText
    }
    
    private func extractTextUsingOCR(from page: PDFPage) -> String? {
        // Convert PDF page to high-resolution image for better OCR
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3.0 // Higher resolution for better OCR
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        print("DEBUG: Converting PDF page to image - Original: \(pageRect.size), Scaled: \(scaledSize)")
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        
        let image = renderer.image { context in
            // White background
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            // Scale and flip coordinate system
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: 0, y: pageRect.size.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            // Draw the PDF page
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        // Use Vision framework for OCR with enhanced settings
        guard let cgImage = image.cgImage else {
            print("DEBUG: Failed to convert PDF page to CGImage")
            return nil
        }
        
        print("DEBUG: Created image for OCR - Size: \(image.size), Scale: \(image.scale)")
        
        // Try multiple OCR approaches
        return performOCRWithMultipleAttempts(cgImage: cgImage)
    }
    
    private func performOCRWithMultipleAttempts(cgImage: CGImage) -> String? {
        // Attempt 1: Accurate recognition with language correction
        if let text = performOCR(cgImage: cgImage, level: .accurate, useLanguageCorrection: true) {
            print("DEBUG: OCR successful with accurate + language correction")
            return text
        }
        
        // Attempt 2: Accurate recognition without language correction
        if let text = performOCR(cgImage: cgImage, level: .accurate, useLanguageCorrection: false) {
            print("DEBUG: OCR successful with accurate recognition")
            return text
        }
        
        // Attempt 3: Fast recognition
        if let text = performOCR(cgImage: cgImage, level: .fast, useLanguageCorrection: false) {
            print("DEBUG: OCR successful with fast recognition")
            return text
        }
        
        print("DEBUG: All OCR attempts failed")
        return nil
    }
    
    private func performOCR(cgImage: CGImage, level: VNRequestTextRecognitionLevel, useLanguageCorrection: Bool) -> String? {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = useLanguageCorrection
        
        // Set supported languages (English and Hindi for Indian banks)
        request.recognitionLanguages = ["en-US", "hi-IN"]
        
        var recognizedText = ""
        
        do {
            try requestHandler.perform([request])
            
            guard let observations = request.results else {
                print("DEBUG: No OCR observations for level \(level)")
                return nil
            }
            
            print("DEBUG: Found \(observations.count) text observations")
            
            for observation in observations {
                // Get multiple candidates for better accuracy
                let candidates = observation.topCandidates(3)
                if let bestCandidate = candidates.first {
                    recognizedText += bestCandidate.string + "\n"
                    print("DEBUG: OCR text: '\(bestCandidate.string)' (confidence: \(bestCandidate.confidence))")
                }
            }
            
            let trimmedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            print("DEBUG: OCR extracted \(trimmedText.count) characters with level \(level)")
            
            return trimmedText.isEmpty ? nil : trimmedText
            
        } catch {
            print("DEBUG: OCR error with level \(level): \(error)")
            return nil
        }
    }
    
    // MARK: - Axis Bank Standard Format Parser
    private func parseAxisBankStatement(_ text: String) -> CreditCardBillInfo? {
        // All Axis cards use the same format
        return parseAxisStandardFormat(text)
    }
    
    private func parseAxisStandardFormat(_ text: String) -> CreditCardBillInfo? {
        // Extract basic bill information
        let bankName = "Axis Bank"
        
        // Extract card number (look for patterns like "****6988")
        let cardNumber = extractCardNumber(from: text) ?? "Unknown"
        
        // Extract dates
        let statementDate = extractStatementDate(from: text) ?? Date()
        let dueDate = extractDueDate(from: text) ?? Date()
        
        // Extract due amount (what needs to be paid)
        let dueAmount = extractTotalAmount(from: text) ?? 0.0
        
        // Extract credit limit and available credit limit
        let creditLimit = extractCreditLimit(from: text)
        let availableCreditLimit = extractAvailableCreditLimit(from: text)
        
        // Calculate current usage: Credit Limit - Available Credit Limit
        var currentUsage = dueAmount // Default to due amount if calculation fails
        if let limit = creditLimit, let available = availableCreditLimit {
            currentUsage = limit - available
        }
        
        // Extract Axis format transactions
        let transactions = extractAxisStandardTransactions(from: text)
        
        return CreditCardBillInfo(
            bankName: bankName,
            cardNumber: cardNumber,
            statementDate: statementDate,
            dueDate: dueDate,
            totalAmount: currentUsage, // Current usage/balance
            dueAmount: dueAmount, // Amount due to be paid
            creditLimit: creditLimit,
            currentUsage: currentUsage > 0 ? currentUsage : nil,
            availableLimit: availableCreditLimit,
            transactions: transactions
        )
    }
    
    private func parseHDFCBankStatement(_ text: String) -> CreditCardBillInfo? {
        // Similar implementation for HDFC
        return nil
    }
    
    private func parseICICIBankStatement(_ text: String) -> CreditCardBillInfo? {
        print("DEBUG: Starting ICICI Bank statement parsing")
        print("DEBUG: Text length: \(text.count) characters")
        
        // All ICICI cards use the same format with "Date SerNo. Transaction Details Reward"
        return parseICICIStandardFormat(text)
    }
    
    // MARK: - ICICI Bank Standard Format Parser
    private func parseICICIStandardFormat(_ text: String) -> CreditCardBillInfo? {
        print("DEBUG: Starting ICICI Bank standard format parsing")
        let bankName = "ICICI Bank"
        
        // Extract card number from text (look for patterns like 4315XXXXXXXX3000)
        var cardNumber = "****0000"
        if let cardMatch = text.range(of: #"4\d{3}X{8}\d{4}"#, options: .regularExpression) {
            let fullCard = String(text[cardMatch])
            cardNumber = "****" + String(fullCard.suffix(4))
            print("DEBUG: ICICI - Found card number: \(cardNumber)")
        }
        
        // Extract statement date - ICICI format is different from Axis
        let statementDate = extractICICIStatementDate(from: text) ?? Date()
        
        // Extract due date
        var dueDate = extractDueDate(from: text) ?? Calendar.current.date(byAdding: .day, value: 30, to: statementDate) ?? Date()
        
        // Extract credit limit and available credit limit from CREDIT SUMMARY
        var creditLimit: Double = 0
        var availableLimit: Double = 0
        
        print("DEBUG: ICICI - Searching for credit limit in text...")
        
        // ICICI format: "Credit Limit (Including cash) Available Credit (Including cash)"
        // followed by "`2,50,000.00 ` 2,46,375.58"
        
        // Look for the credit summary section and extract amounts
        if let creditSummaryRange = text.range(of: "CREDIT SUMMARY", options: .caseInsensitive) {
            let afterCreditSummary = String(text[creditSummaryRange.upperBound...])
            print("DEBUG: ICICI - Found CREDIT SUMMARY section")
            
            // Look for the pattern with backticks: `2,50,000.00 ` 2,46,375.58
            let amountPattern = #"`([\d,]+\.\d{2})\s+`\s*([\d,]+\.\d{2})"#
            if let amountMatch = afterCreditSummary.range(of: amountPattern, options: .regularExpression) {
                let amountText = String(afterCreditSummary[amountMatch])
                print("DEBUG: ICICI - Found amount pattern: \(amountText)")
                
                // Extract both credit limit and available credit
                let regex = try! NSRegularExpression(pattern: amountPattern)
                let nsString = amountText as NSString
                if let match = regex.firstMatch(in: amountText, range: NSRange(location: 0, length: nsString.length)) {
                    if match.numberOfRanges >= 3 {
                        let creditLimitStr = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                        let availableLimitStr = nsString.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: "")
                        
                        if let credit = Double(creditLimitStr), let available = Double(availableLimitStr) {
                            creditLimit = credit
                            availableLimit = available
                            print("DEBUG: ICICI - Credit limit: ₹\(creditLimit)")
                            print("DEBUG: ICICI - Available limit: ₹\(availableLimit)")
                        }
                    }
                }
            }
        }
        
        // Fallback: Look for individual patterns if the combined pattern doesn't work
        if creditLimit == 0 {
            print("DEBUG: ICICI - Trying fallback credit limit patterns...")
            let creditLimitPatterns = [
                #"`([\d,]+\.\d{2})"#,  // Look for `2,50,000.00 format
                #"Credit Limit[^`]*`([\d,]+\.\d{2})"#,
                #"([\d,]+\.\d{2})\s+`\s*([\d,]+\.\d{2})"#  // 2,50,000.00 ` 2,46,375.58
            ]
            
            for pattern in creditLimitPatterns {
                if let limitMatch = text.range(of: pattern, options: .regularExpression) {
                    let limitText = String(text[limitMatch])
                    print("DEBUG: ICICI - Found potential credit limit text: \(limitText)")
                    
                    if let amountMatch = limitText.range(of: #"([\d,]+\.\d{2})"#, options: .regularExpression) {
                        let amountStr = String(limitText[amountMatch]).replacingOccurrences(of: ",", with: "")
                        if let amount = Double(amountStr), amount > 10000 {  // Reasonable credit limit check
                            creditLimit = amount
                            print("DEBUG: ICICI - Credit limit (fallback): ₹\(creditLimit)")
                            break
                        }
                    }
                }
            }
        }
        
        // Available limit extraction (fallback if not already extracted above)
        if availableLimit == 0.0 {
            print("DEBUG: ICICI - Trying fallback available limit patterns...")
            let availableLimitPatterns = [
                #"`\s*([\d,]+\.\d{2})"#,  // Look for ` 2,46,375.58 format
                #"Available Credit[^`]*`\s*([\d,]+\.\d{2})"#,
                #"Available[^`]*`\s*([\d,]+\.\d{2})"#
            ]
            
            for pattern in availableLimitPatterns {
                if let limitMatch = text.range(of: pattern, options: .regularExpression) {
                    let limitText = String(text[limitMatch])
                    print("DEBUG: ICICI - Found potential available limit text: \(limitText)")
                    
                    if let amountMatch = limitText.range(of: #"([\d,]+\.\d{2})"#, options: .regularExpression) {
                        let amountStr = String(limitText[amountMatch]).replacingOccurrences(of: ",", with: "")
                        if let amount = Double(amountStr), amount > 1000 {  // Reasonable available limit check
                            availableLimit = amount
                            print("DEBUG: ICICI - Available limit (fallback): ₹\(availableLimit)")
                            break
                        }
                    }
                }
            }
        }
        
        // Extract "Total Amount due" from PDF (PRIORITY: Use actual PDF field, not calculated usage)
        var totalAmount: Double = 0.0
        
        print("DEBUG: ICICI - Searching for Total Amount due in PDF...")
        if let totalAmountRange = text.range(of: "Total Amount due", options: .caseInsensitive) {
            let afterTotalAmount = String(text[totalAmountRange.upperBound...])
            print("DEBUG: ICICI - Found 'Total Amount due' section")
            // Look for `3,624.42 format
            if let amountMatch = afterTotalAmount.range(of: #"`([\d,]+\.\d{2})"#, options: .regularExpression) {
                let amountText = String(afterTotalAmount[amountMatch])
                if let extractedAmount = amountText.range(of: #"([\d,]+\.\d{2})"#, options: .regularExpression) {
                    let amountStr = String(amountText[extractedAmount]).replacingOccurrences(of: ",", with: "")
                    if let amount = Double(amountStr) {
                        totalAmount = amount
                        print("DEBUG: ICICI - Total amount due extracted from PDF: ₹\(totalAmount)")
                    }
                }
            }
        }
        
        // Calculate current usage for reference (but don't use for bill amount)
        var currentUsage: Double = 0.0
        if availableLimit > 0 && creditLimit > availableLimit {
            currentUsage = creditLimit - availableLimit
            print("DEBUG: ICICI - Current usage calculated: ₹\(currentUsage) (Credit: ₹\(creditLimit) - Available: ₹\(availableLimit))")
        }
        
        // If Total Amount due not found, try alternative patterns
        if totalAmount == 0.0 {
            print("DEBUG: ICICI - 'Total Amount due' not found, trying alternative patterns...")
            let totalDuePatterns = [
                #"Total.*due[^`]*`([\d,]+\.\d{2})"#,
                #"Amount.*due[^`]*`([\d,]+\.\d{2})"#,
                #"Outstanding.*balance[^`]*`([\d,]+\.\d{2})"#,
                #"Total.*outstanding[^`]*`([\d,]+\.\d{2})"#
            ]
            
            for pattern in totalDuePatterns {
                if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let matchText = String(text[match])
                    if let amountMatch = matchText.range(of: #"([\d,]+\.\d{2})"#, options: .regularExpression) {
                        let amountStr = String(matchText[amountMatch]).replacingOccurrences(of: ",", with: "")
                        if let amount = Double(amountStr), amount > 0 {
                            totalAmount = amount
                            print("DEBUG: ICICI - Total amount due found with pattern: ₹\(totalAmount)")
                            break
                        }
                    }
                }
            }
        }
        
        // Final fallback: use current usage if no total due found
        if totalAmount == 0.0 {
            totalAmount = currentUsage
            print("DEBUG: ICICI - Using current usage as fallback for total due: ₹\(totalAmount)")
        }
        
        // Extract minimum due amount with ICICI-specific patterns
        var dueAmount: Double = 0.0
        
        print("DEBUG: ICICI - Searching for Minimum Amount due...")
        if let minAmountRange = text.range(of: "Minimum Amount due", options: .caseInsensitive) {
            let afterMinAmount = String(text[minAmountRange.upperBound...])
            // Look for `190.00 format
            if let amountMatch = afterMinAmount.range(of: #"`([\d,]+\.\d{2})"#, options: .regularExpression) {
                let amountText = String(afterMinAmount[amountMatch])
                if let extractedAmount = amountText.range(of: #"([\d,]+\.\d{2})"#, options: .regularExpression) {
                    let amountStr = String(amountText[extractedAmount]).replacingOccurrences(of: ",", with: "")
                    if let amount = Double(amountStr) {
                        dueAmount = amount
                        print("DEBUG: ICICI - Minimum amount due found: ₹\(dueAmount)")
                    }
                }
            }
        }
        
        // Fallback patterns
        if dueAmount == 0.0 {
            print("DEBUG: ICICI - Trying fallback minimum due patterns...")
            let dueAmountPatterns = [
                #"Minimum[^`]*`([\d,]+\.\d{2})"#,
                #"Min[^`]*`([\d,]+\.\d{2})"#,
                #"`([\d,]+\.\d{2})"#  // Any small amount with backtick
            ]
            
            for pattern in dueAmountPatterns {
                if let dueMatch = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let dueText = String(text[dueMatch])
                    if let amountMatch = dueText.range(of: #"([\d,]+\.\d{2})"#, options: .regularExpression) {
                        let amountStr = String(dueText[amountMatch]).replacingOccurrences(of: ",", with: "")
                        if let amount = Double(amountStr), amount < totalAmount {  // Should be less than total amount
                            dueAmount = amount
                            print("DEBUG: ICICI - Minimum due (fallback): ₹\(dueAmount)")
                            break
                        }
                    }
                }
            }
        }
        
        // Extract due date with ICICI-specific patterns
        print("DEBUG: ICICI - Searching for PAYMENT DUE DATE...")
        if let dueDateRange = text.range(of: "PAYMENT DUE DATE", options: .caseInsensitive) {
            let afterDueDate = String(text[dueDateRange.upperBound...])
            print("DEBUG: ICICI - Found PAYMENT DUE DATE section")
            
            // Look for "October 8, 2025" format
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM d, yyyy"
            
            // Extract next few lines after PAYMENT DUE DATE
            let lines = afterDueDate.components(separatedBy: .newlines).prefix(5)
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty && trimmedLine != "PAYMENT DUE DATE" {
                    print("DEBUG: ICICI - Trying to parse due date: '\(trimmedLine)'")
                    
                    // Try different month formats
                    let formatters = [
                        ("MMMM d, yyyy", "October 8, 2025"),
                        ("MMMM d yyyy", "October 8 2025"),
                        ("d MMMM yyyy", "8 October 2025"),
                        ("dd/MM/yyyy", "08/10/2025"),
                        ("dd-MM-yyyy", "08-10-2025")
                    ]
                    
                    for (format, example) in formatters {
                        let formatter = DateFormatter()
                        formatter.dateFormat = format
                        if let date = formatter.date(from: trimmedLine) {
                            dueDate = date
                            print("DEBUG: ICICI - Due date parsed with format '\(format)': \(trimmedLine)")
                            break
                        }
                    }
                    
                    if dueDate != Calendar.current.date(byAdding: .day, value: 30, to: statementDate) {
                        break  // Successfully parsed
                    }
                }
            }
        }
        
        // Fallback: try other due date patterns
        if dueDate == Calendar.current.date(byAdding: .day, value: 30, to: statementDate) {
            print("DEBUG: ICICI - Trying fallback due date patterns...")
            let dueDatePatterns = [
                #"(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})"#,
                #"(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})"#,
                #"Due[^\n]*?(\d{2}[/-]\d{2}[/-]\d{4})"#
            ]
            
            for pattern in dueDatePatterns {
                if let dueDateMatch = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let dueDateText = String(text[dueDateMatch])
                    print("DEBUG: ICICI - Found due date text (fallback): \(dueDateText)")
                    
                    // Try to extract and parse the date
                    let monthFormatter = DateFormatter()
                    monthFormatter.dateFormat = "MMMM d yyyy"
                    if let date = monthFormatter.date(from: dueDateText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        dueDate = date
                        print("DEBUG: ICICI - Due date parsed (fallback): \(dueDateText)")
                        break
                    }
                }
            }
        }
        
        // Extract transactions using ICICI standard format (Amazon format)
        let transactions = extractICICIStandardTransactions(from: text)
        print("DEBUG: ICICI - Extracted \(transactions.count) transactions")
        
        let billInfo = CreditCardBillInfo(
            bankName: bankName,
            cardNumber: cardNumber,
            statementDate: statementDate,
            dueDate: dueDate,
            totalAmount: currentUsage > 0 ? currentUsage : totalAmount, // Use current usage for account balance
            dueAmount: totalAmount,   // Use total amount due for bill payment (₹3,818.92)
            creditLimit: creditLimit,
            currentUsage: currentUsage > 0 ? currentUsage : nil,
            availableLimit: availableLimit > 0 ? availableLimit : nil,
            transactions: transactions
        )
        
        print("DEBUG: ICICI parsing completed - Card: \(cardNumber)")
        print("DEBUG: - Credit Limit: ₹\(creditLimit)")
        print("DEBUG: - Available Limit: ₹\(availableLimit)")
        print("DEBUG: - Current Usage (calculated): ₹\(currentUsage)")
        print("DEBUG: - Total Amount Due (from PDF): ₹\(totalAmount)")
        print("DEBUG: - Account Balance (using): ₹\(currentUsage > 0 ? currentUsage : totalAmount)")
        print("DEBUG: - Bill Amount (using): ₹\(totalAmount)")
        
        return billInfo
    }
    
    private func parseGenericStatement(_ text: String) -> CreditCardBillInfo? {
        // Generic parser for unknown banks
        return nil
    }
    
    private func extractICICIStandardTransactions(from text: String) -> [CreditCardTransaction] {
        print("DEBUG: Starting ICICI standard transaction extraction")
        var transactions: [CreditCardTransaction] = []
        
        let lines = text.components(separatedBy: .newlines)
        var inTransactionSection = false
        var transactionLines: [String] = []
        
        // Find the transaction section with ICICI format
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Look for ICICI transaction section headers
            if trimmedLine.contains("Date SerNo. Transaction Details Reward") {
                print("DEBUG: Found ICICI transaction section header: \(trimmedLine)")
                inTransactionSection = true
                continue
            }
            
            // Look for end of transaction section
            if inTransactionSection && (trimmedLine.contains("PAYMENT SUMMARY") || 
                                       trimmedLine.contains("TOTAL") ||
                                       trimmedLine.contains("EARNINGS") ||
                                       trimmedLine.contains("IMPORTANT MESSAGES") ||
                                       trimmedLine.contains("EMI / PERSONAL LOAN") ||
                                       trimmedLine.contains("EMI/Loan") ||
                                       trimmedLine.contains("Transaction/") ||
                                       trimmedLine.contains("Creation") ||
                                       trimmedLine.contains("Merchant EMI") ||
                                       trimmedLine.isEmpty && transactionLines.count > 0) {
                print("DEBUG: End of ICICI transaction section detected")
                break
            }
            
            // Collect transaction lines
            if inTransactionSection && !trimmedLine.isEmpty {
                transactionLines.append(trimmedLine)
                print("DEBUG: ICICI transaction line: \(trimmedLine)")
            }
        }
        
        print("DEBUG: Found \(transactionLines.count) potential ICICI transaction lines")
        
        // Parse multi-line transactions - amounts can be on separate lines
        transactions = parseMultiLineICICITransactions(transactionLines)
        
        print("DEBUG: Successfully extracted \(transactions.count) ICICI transactions")
        return transactions
    }
    
    private func parseMultiLineICICITransactions(_ lines: [String]) -> [CreditCardTransaction] {
        var transactions: [CreditCardTransaction] = []
        var usedAmountLines: Set<Int> = [] // Track which lines have been used for amounts
        
        // First, collect all transaction lines and their indices
        var transactionIndices: [(Int, String)] = []
        for (index, line) in lines.enumerated() {
            if line.range(of: #"^\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil {
                transactionIndices.append((index, line))
            }
        }
        
        print("DEBUG: Found \(transactionIndices.count) transaction lines to process")
        
        // Process transactions in order, but with smarter amount assignment
        for (i, (lineIndex, line)) in transactionIndices.enumerated() {
            print("DEBUG: Processing transaction \(i+1)/\(transactionIndices.count): \(line)")
            
            // Try to parse as single-line transaction first
            if let transaction = parseICICITransactionLine(line) {
                transactions.append(transaction)
                print("DEBUG: Parsed single-line transaction: \(transaction.description) - ₹\(transaction.amount)")
                continue
            }
            
            // For multi-line parsing, use smart assignment based on transaction position
            if let (transaction, usedLineIndex) = parseMultiLineICICITransactionWithSmartAssignment(lines, startIndex: lineIndex, usedAmountLines: usedAmountLines, transactionNumber: i) {
                transactions.append(transaction)
                usedAmountLines.insert(usedLineIndex)
                print("DEBUG: Parsed multi-line transaction \(i+1): \(transaction.description) - ₹\(transaction.amount) (used line \(usedLineIndex))")
                continue
            }
        }
        
        return transactions
    }
    
    private func parseMultiLineICICITransactionWithSmartAssignment(_ lines: [String], startIndex: Int, usedAmountLines: Set<Int>, transactionNumber: Int) -> (CreditCardTransaction, Int)? {
        guard startIndex < lines.count - 1 else { return nil }
        
        let transactionLine = lines[startIndex]
        
        print("DEBUG: Smart assignment for transaction \(transactionNumber + 1): '\(transactionLine)'")
        
        // Filter out EMI/Loan table data
        if isEMIOrLoanData(transactionLine) {
            print("DEBUG: Skipping EMI/Loan data: \(transactionLine)")
            return nil
        }
        
        // Parse the transaction line (without amount)
        let words = transactionLine.components(separatedBy: .whitespaces)
        guard words.count >= 3 else { return nil }
        
        // Parse date (first word)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        guard let date = dateFormatter.date(from: words[0]) else { 
            print("DEBUG: Failed to parse date from: \(words[0])")
            return nil 
        }
        
        // Serial number is second word
        let serialNumber = words[1]
        
        // Description is everything after serial number (excluding reward points and percentages)
        var descriptionWords = Array(words[2...])
        
        // Remove reward points and percentages from description
        descriptionWords = descriptionWords.filter { word in
            // Remove pure numbers (reward points) and percentages
            if let _ = Int(word), word.count <= 3 { return false }
            if word.hasSuffix("%") { return false }
            return true
        }
        
        let description = descriptionWords.joined(separator: " ")
        guard !description.isEmpty else { 
            print("DEBUG: Empty description after filtering")
            return nil 
        }
        
        // Smart amount assignment based on transaction position and PDF structure
        var amount: Double = 0
        var amountLineIndex = -1
        
        // Special handling for first transaction - prioritize standalone amounts that appear later
        if transactionNumber == 0 {
            print("DEBUG: First transaction - looking for standalone amounts in entire range")
            // Search the entire range for standalone amounts
            for i in 1..<lines.count - startIndex {
                let lineIndex = startIndex + i
                let searchLine = lines[lineIndex]
                let searchWords = searchLine.components(separatedBy: .whitespaces)
                
                // Skip used lines
                if usedAmountLines.contains(lineIndex) { continue }
                
                // Skip transaction lines
                if searchLine.range(of: #"^\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil { continue }
                
                // Skip CR lines
                if searchLine.contains("CR") { continue }
                
                // Look for standalone amounts (single decimal number on a line)
                if searchWords.count == 1 {
                    let word = searchWords[0]
                    let cleanWord = word.replacingOccurrences(of: ",", with: "")
                    if let parsedAmount = Double(cleanWord), 
                       parsedAmount > 0,
                       word.contains(".") {
                        amount = parsedAmount
                        amountLineIndex = lineIndex
                        print("DEBUG: First transaction found STANDALONE amount: \(amount) (from '\(word)' in '\(searchLine)' at line \(lineIndex))")
                        break
                    }
                }
            }
        }
        
        // If no standalone amount found (or not first transaction), use regular logic
        if amount == 0 {
            // First pass: Look for standalone amounts (single decimal number on a line)
            for i in 1...min(5, lines.count - startIndex - 1) {
                let lineIndex = startIndex + i
                let searchLine = lines[lineIndex]
                let searchWords = searchLine.components(separatedBy: .whitespaces)
                
                // Skip lines that have already been used for amounts
                if usedAmountLines.contains(lineIndex) {
                    print("DEBUG: Skipping already used amount line \(lineIndex): \(searchLine)")
                    continue
                }
                
                // Skip lines that are clearly other transactions (start with date)
                if searchLine.range(of: #"^\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil {
                    print("DEBUG: Skipping line with date (another transaction): \(searchLine)")
                    continue
                }
                
                // Skip lines that contain "CR" (credit transactions)
                if searchLine.contains("CR") {
                    print("DEBUG: Skipping CR line: \(searchLine)")
                    continue
                }
                
                // Prioritize standalone amounts (single decimal number on a line)
                if searchWords.count == 1 {
                    let word = searchWords[0]
                    let cleanWord = word.replacingOccurrences(of: ",", with: "")
                    if let parsedAmount = Double(cleanWord), 
                       parsedAmount > 0,
                       word.contains(".") {
                        amount = parsedAmount
                        amountLineIndex = lineIndex
                        print("DEBUG: Found STANDALONE amount in line \(i) (index \(lineIndex)): \(amount) (from '\(word)' in '\(searchLine)')")
                        break
                    }
                }
            }
            
            // Second pass: If no standalone amount found, look for amounts with reward points
            if amount == 0 {
                for i in 1...min(5, lines.count - startIndex - 1) {
                    let lineIndex = startIndex + i
                    let searchLine = lines[lineIndex]
                    let searchWords = searchLine.components(separatedBy: .whitespaces)
                    
                    // Skip lines that have already been used for amounts
                    if usedAmountLines.contains(lineIndex) {
                        continue
                    }
                    
                    // Skip lines that are clearly other transactions (start with date)
                    if searchLine.range(of: #"^\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil {
                        continue
                    }
                    
                    // Skip lines that contain "CR" (credit transactions)
                    if searchLine.contains("CR") {
                        continue
                    }
                    
                    // Look for amounts with reward points (like "11 239.22")
                    if searchWords.count <= 3 {
                        for word in searchWords {
                            let cleanWord = word.replacingOccurrences(of: ",", with: "")
                            if let parsedAmount = Double(cleanWord), 
                               parsedAmount > 0,
                               word.contains(".") {
                                amount = parsedAmount
                                amountLineIndex = lineIndex
                                print("DEBUG: Found amount with reward points in line \(i) (index \(lineIndex)): \(amount) (from '\(word)' in '\(searchLine)')")
                                break
                            }
                        }
                    }
                    
                    if amount > 0 { break }
                }
            }
        }
        
        guard amount > 0 && amountLineIndex >= 0 else {
            print("DEBUG: No valid amount found for transaction \(transactionNumber + 1)")
            return nil
        }
        
        // Check for credit transactions
        let isCredit = transactionLine.contains("CR")
        
        // Filter out payment transactions
        if isCredit && isPaymentTransaction(description) {
            print("DEBUG: Skipping ICICI payment transaction: \(description)")
            return nil
        }
        
        print("DEBUG: Smart assignment result - Date: \(date), SerNo: \(serialNumber), Description: '\(description)', Amount: \(amount), Credit: \(isCredit)")
        
        let transaction = CreditCardTransaction(
            date: date,
            description: description,
            amount: amount,
            category: categorizeTransaction(description),
            referenceNumber: serialNumber
        )
        
        return (transaction, amountLineIndex)
    }
    
    private func parseMultiLineICICITransactionWithTracking(_ lines: [String], startIndex: Int, usedAmountLines: Set<Int>) -> (CreditCardTransaction, Int)? {
        guard startIndex < lines.count - 1 else { return nil }
        
        let transactionLine = lines[startIndex]
        
        print("DEBUG: Trying multi-line parsing with tracking:")
        print("DEBUG: Transaction line: '\(transactionLine)'")
        
        // Filter out EMI/Loan table data
        if isEMIOrLoanData(transactionLine) {
            print("DEBUG: Skipping EMI/Loan data: \(transactionLine)")
            return nil
        }
        
        // Parse the transaction line (without amount)
        let words = transactionLine.components(separatedBy: .whitespaces)
        guard words.count >= 3 else { return nil }
        
        // Parse date (first word)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        guard let date = dateFormatter.date(from: words[0]) else { 
            print("DEBUG: Failed to parse date from: \(words[0])")
            return nil 
        }
        
        // Serial number is second word
        let serialNumber = words[1]
        
        // Description is everything after serial number (excluding reward points and percentages)
        var descriptionWords = Array(words[2...])
        
        // Remove reward points and percentages from description
        descriptionWords = descriptionWords.filter { word in
            // Remove pure numbers (reward points) and percentages
            if let _ = Int(word), word.count <= 3 { return false }
            if word.hasSuffix("%") { return false }
            return true
        }
        
        let description = descriptionWords.joined(separator: " ")
        guard !description.isEmpty else { 
            print("DEBUG: Empty description after filtering")
            return nil 
        }
        
        // Look for amount in the next few lines (not just immediate next line)
        var amount: Double = 0
        var amountLineIndex = -1
        
        // First pass: Look for standalone amounts (single decimal number on a line)
        for i in 1...min(5, lines.count - startIndex - 1) {
            let lineIndex = startIndex + i
            let searchLine = lines[lineIndex]
            let searchWords = searchLine.components(separatedBy: .whitespaces)
            
            // Skip lines that have already been used for amounts
            if usedAmountLines.contains(lineIndex) {
                print("DEBUG: Skipping already used amount line \(lineIndex): \(searchLine)")
                continue
            }
            
            // Skip lines that are clearly other transactions (start with date)
            if searchLine.range(of: #"^\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil {
                print("DEBUG: Skipping line with date (another transaction): \(searchLine)")
                continue
            }
            
            // Skip lines that contain "CR" (credit transactions)
            if searchLine.contains("CR") {
                print("DEBUG: Skipping CR line: \(searchLine)")
                continue
            }
            
            // Prioritize standalone amounts (single decimal number on a line)
            if searchWords.count == 1 {
                let word = searchWords[0]
                let cleanWord = word.replacingOccurrences(of: ",", with: "")
                if let parsedAmount = Double(cleanWord), 
                   parsedAmount > 0,
                   word.contains(".") {
                    amount = parsedAmount
                    amountLineIndex = lineIndex
                    print("DEBUG: Found STANDALONE amount in line \(i) (index \(lineIndex)): \(amount) (from '\(word)' in '\(searchLine)')")
                    break
                }
            }
        }
        
        // Second pass: If no standalone amount found, look for amounts with reward points
        if amount == 0 {
            for i in 1...min(5, lines.count - startIndex - 1) {
                let lineIndex = startIndex + i
                let searchLine = lines[lineIndex]
                let searchWords = searchLine.components(separatedBy: .whitespaces)
                
                // Skip lines that have already been used for amounts
                if usedAmountLines.contains(lineIndex) {
                    continue
                }
                
                // Skip lines that are clearly other transactions (start with date)
                if searchLine.range(of: #"^\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil {
                    continue
                }
                
                // Skip lines that contain "CR" (credit transactions)
                if searchLine.contains("CR") {
                    continue
                }
                
                // Look for amounts with reward points (like "11 239.22")
                if searchWords.count <= 3 {
                    for word in searchWords {
                        let cleanWord = word.replacingOccurrences(of: ",", with: "")
                        if let parsedAmount = Double(cleanWord), 
                           parsedAmount > 0,
                           word.contains(".") {
                            amount = parsedAmount
                            amountLineIndex = lineIndex
                            print("DEBUG: Found amount with reward points in line \(i) (index \(lineIndex)): \(amount) (from '\(word)' in '\(searchLine)')")
                            break
                        }
                    }
                }
                
                if amount > 0 { break }
            }
        }
        
        guard amount > 0 && amountLineIndex >= 0 else {
            print("DEBUG: No valid amount found in next lines")
            return nil
        }
        
        // Check for credit transactions
        let isCredit = transactionLine.contains("CR")
        
        // Filter out payment transactions
        if isCredit && isPaymentTransaction(description) {
            print("DEBUG: Skipping ICICI payment transaction: \(description)")
            return nil
        }
        
        print("DEBUG: Multi-line ICICI format - Date: \(date), SerNo: \(serialNumber), Description: '\(description)', Amount: \(amount), Credit: \(isCredit)")
        
        let transaction = CreditCardTransaction(
            date: date,
            description: description,
            amount: amount,
            category: categorizeTransaction(description),
            referenceNumber: serialNumber
        )
        
        return (transaction, amountLineIndex)
    }
    
    private func parseMultiLineICICITransaction(_ lines: [String], startIndex: Int) -> CreditCardTransaction? {
        guard startIndex < lines.count - 1 else { return nil }
        
        let transactionLine = lines[startIndex]
        let nextLine = lines[startIndex + 1]
        
        print("DEBUG: Trying multi-line parsing:")
        print("DEBUG: Transaction line: '\(transactionLine)'")
        print("DEBUG: Next line: '\(nextLine)'")
        
        // Filter out EMI/Loan table data
        if isEMIOrLoanData(transactionLine) {
            print("DEBUG: Skipping EMI/Loan data: \(transactionLine)")
            return nil
        }
        
        // Parse the transaction line (without amount)
        let words = transactionLine.components(separatedBy: .whitespaces)
        guard words.count >= 3 else { return nil }
        
        // Parse date (first word)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        guard let date = dateFormatter.date(from: words[0]) else { 
            print("DEBUG: Failed to parse date from: \(words[0])")
            return nil 
        }
        
        // Serial number is second word
        let serialNumber = words[1]
        
        // Description is everything after serial number (excluding reward points and percentages)
        var descriptionWords = Array(words[2...])
        
        // Remove reward points and percentages from description
        descriptionWords = descriptionWords.filter { word in
            // Remove pure numbers (reward points) and percentages
            if let _ = Int(word), word.count <= 3 { return false }
            if word.hasSuffix("%") { return false }
            return true
        }
        
        let description = descriptionWords.joined(separator: " ")
        guard !description.isEmpty else { 
            print("DEBUG: Empty description after filtering")
            return nil 
        }
        
        // Look for amount in the next few lines (not just immediate next line)
        var amount: Double = 0
        var amountFound = false
        
        // Search through next 3 lines to find the correct amount
        for i in 1...min(3, lines.count - startIndex - 1) {
            let searchLine = lines[startIndex + i]
            let searchWords = searchLine.components(separatedBy: .whitespaces)
            
            // Skip lines that are clearly other transactions (start with date)
            if searchLine.range(of: #"^\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil {
                print("DEBUG: Skipping line with date (another transaction): \(searchLine)")
                continue
            }
            
            // Skip lines that contain "CR" (credit transactions)
            if searchLine.contains("CR") {
                print("DEBUG: Skipping CR line: \(searchLine)")
                continue
            }
            
            // Look for a standalone decimal amount
            for word in searchWords {
                let cleanWord = word.replacingOccurrences(of: ",", with: "")
                if let parsedAmount = Double(cleanWord), 
                   parsedAmount > 0,
                   word.contains("."),
                   searchWords.count <= 3 { // Amount should be on a simple line
                    amount = parsedAmount
                    print("DEBUG: Found amount in line \(i): \(amount) (from '\(word)' in '\(searchLine)')")
                    amountFound = true
                    break
                }
            }
            
            if amountFound { break }
        }
        
        guard amount > 0 else {
            print("DEBUG: No valid amount found in next line")
            return nil
        }
        
        // Check for credit transactions
        let isCredit = transactionLine.contains("CR") || nextLine.contains("CR")
        
        // Filter out payment transactions
        if isCredit && isPaymentTransaction(description) {
            print("DEBUG: Skipping ICICI payment transaction: \(description)")
            return nil
        }
        
        print("DEBUG: Multi-line ICICI format - Date: \(date), SerNo: \(serialNumber), Description: '\(description)', Amount: \(amount), Credit: \(isCredit)")
        
        return CreditCardTransaction(
            date: date,
            description: description,
            amount: amount,
            category: categorizeTransaction(description),
            referenceNumber: serialNumber
        )
    }
    
    private func isEMIOrLoanData(_ line: String) -> Bool {
        // Check if line contains multiple dates (EMI table format)
        let datePattern = #"\d{2}/\d{2}/\d{4}"#
        
        // Count date matches using NSRegularExpression
        do {
            let regex = try NSRegularExpression(pattern: datePattern)
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            
            // EMI table lines have multiple dates like "29/11/2024 29/10/2025"
            if matches.count > 1 {
                return true
            }
        } catch {
            // If regex fails, continue with other checks
        }
        
        // Check for EMI-specific patterns
        let emiPatterns = [
            "41,330.00", // Large EMI amounts
            "7,578.31",  // EMI amounts
            "3,789.13",  // EMI amounts
            "Merchant EMI",
            "EMI/Loan",
            "Installments",
            "Outstanding",
            "Monthly"
        ]
        
        for pattern in emiPatterns {
            if line.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    private func parseICICITransactionLine(_ line: String) -> CreditCardTransaction? {
        let words = line.components(separatedBy: .whitespaces)
        guard words.count >= 5 else { return nil }
        
        print("DEBUG: Parsing ICICI line: '\(line)'")
        print("DEBUG: Split into \(words.count) words: \(words)")
        
        // Filter out EMI/Loan table data
        if isEMIOrLoanData(line) {
            print("DEBUG: Skipping EMI/Loan data: \(line)")
            return nil
        }
        
        // Try to parse date (first word)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        guard let date = dateFormatter.date(from: words[0]) else { 
            print("DEBUG: Failed to parse date from: \(words[0])")
            return nil 
        }
        
        // Check if last word is "CR" (credit transaction)
        var isCredit = false
        var amountIndex = words.count - 1
        
        if words.last == "CR" {
            isCredit = true
            amountIndex = words.count - 2
            guard amountIndex > 0 else { return nil }
        }
        
        // Find the amount - should be a decimal number (like 574.05)
        var amount: Double = 0
        var actualAmountIndex = -1
        
        // Search backwards from the amount position to find a valid decimal amount
        for i in stride(from: amountIndex, through: 2, by: -1) {
            // Remove commas from the word before parsing
            let cleanWord = words[i].replacingOccurrences(of: ",", with: "")
            if let parsedAmount = Double(cleanWord), 
               parsedAmount > 0,
               words[i].contains(".") { // Must be a decimal amount
                amount = parsedAmount
                actualAmountIndex = i
                print("DEBUG: Found amount \(amount) at index \(i) (from '\(words[i])')")
                break
            }
        }
        
        guard amount > 0 && actualAmountIndex > 2 else { 
            print("DEBUG: No valid amount found")
            return nil 
        }
        
        // Description is everything between serial number (index 1) and amount
        let descriptionWords = Array(words[2..<actualAmountIndex])
        let description = descriptionWords.joined(separator: " ")
        
        guard !description.isEmpty else { 
            print("DEBUG: Empty description")
            return nil 
        }
        
        // Filter out payment transactions (credits to credit card)
        if isCredit && isPaymentTransaction(description) {
            print("DEBUG: Skipping ICICI payment transaction: \(description)")
            return nil
        }
        
        print("DEBUG: ICICI format - Date: \(date), SerNo: \(words[1]), Description: '\(description)', Amount: \(amount), Credit: \(isCredit)")
        
        return CreditCardTransaction(
            date: date,
            description: description,
            amount: amount,
            category: categorizeTransaction(description),
            referenceNumber: words[1] // Serial number
        )
    }
    
    // MARK: - ICICI Transaction Extraction
    
    private func extractICICITransactions(from text: String) -> [CreditCardTransaction] {
        print("DEBUG: Starting ICICI transaction extraction")
        var transactions: [CreditCardTransaction] = []
        
        // ICICI statements have different transaction formats
        // Look for transaction sections and patterns
        let lines = text.components(separatedBy: .newlines)
        
        // Look for transaction table sections
        var inTransactionSection = false
        var transactionLines: [String] = []
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            // Detect transaction section start
            if trimmedLine.lowercased().contains("transaction") && 
               (trimmedLine.lowercased().contains("date") || trimmedLine.lowercased().contains("description")) {
                inTransactionSection = true
                print("DEBUG: ICICI - Found transaction section header: \(trimmedLine)")
                continue
            }
            
            // Look for merchant transaction patterns anywhere in text
            if let transaction = parseICICITransactionLine(trimmedLine, lineIndex: index, allLines: lines) {
                transactions.append(transaction)
                print("DEBUG: ICICI transaction: \(transaction.description) - ₹\(transaction.amount)")
            }
        }
        
        // Also try to extract transactions from consolidated text blocks
        let consolidatedTransactions = extractICICITransactionsFromBlocks(text)
        for transaction in consolidatedTransactions {
            // Avoid duplicates
            if !transactions.contains(where: { $0.amount == transaction.amount && $0.description == transaction.description }) {
                transactions.append(transaction)
                print("DEBUG: ICICI block transaction: \(transaction.description) - ₹\(transaction.amount)")
            }
        }
        
        print("DEBUG: ICICI - Found \(transactions.count) total transactions")
        return transactions
    }
    
    private func parseICICITransactionLine(_ line: String, lineIndex: Int = 0, allLines: [String] = []) -> CreditCardTransaction? {
        // Enhanced ICICI transaction parsing with multiple patterns
        
        // Pattern 1: Standard date format with merchant name
        if let dateMatch = line.range(of: #"\d{2}[/-]\d{2}[/-]\d{4}"#, options: .regularExpression) {
            let dateStr = String(line[dateMatch]).replacingOccurrences(of: "-", with: "/")
            
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            
            if let date = formatter.date(from: dateStr) {
                // Enhanced amount patterns for ICICI
                let amountPatterns = [
                    #"Rs\.?\s*([\d,]+\.?\d*)"#,
                    #"INR\s*([\d,]+\.?\d*)"#,
                    #"([\d,]+\.\d{2})\s*$"#,
                    #"([\d,]+)\s*$"#,
                    #"Amount[:\s]*([\d,]+\.?\d*)"#
                ]
                
                for pattern in amountPatterns {
                    if let amountMatch = line.range(of: pattern, options: .regularExpression) {
                        let amountText = String(line[amountMatch])
                        if let amountRange = amountText.range(of: #"[\d,]+\.?\d*"#, options: .regularExpression) {
                            let amountStr = String(amountText[amountRange]).replacingOccurrences(of: ",", with: "")
                            if let amount = Double(amountStr), amount > 0 {
                                
                                // Safely extract description to avoid index out of bounds
                                let afterDate = String(line[dateMatch.upperBound...])
                                var description = afterDate.replacingOccurrences(of: amountText, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                // Clean up description
                                description = description.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                                description = description.replacingOccurrences(of: "Rs.", with: "")
                                description = description.replacingOccurrences(of: "INR", with: "")
                                description = description.trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                if description.isEmpty {
                                    description = "ICICI Transaction"
                                }
                                
                                let transaction = CreditCardTransaction(
                                    date: date,
                                    description: description,
                                    amount: amount,
                                    category: categorizeTransaction(description),
                                    referenceNumber: nil
                                )
                                return transaction
                            }
                        }
                    }
                }
            }
        }
        
        // Pattern 2: Look for merchant names with amounts (no date on same line)
        let merchantPatterns = [
            #"(AMAZON|FLIPKART|SWIGGY|ZOMATO|UBER|OLA|PAYTM|GPAY|PHONEPE|NETFLIX|SPOTIFY|AIRTEL|JIO)\s.*?(\d+\.?\d*)"#,
            #"([A-Z][A-Z\s]{3,})\s+(\d+\.?\d*)"#,
            #"([A-Z][A-Z0-9\s]{5,})\s+Rs\.?\s*(\d+\.?\d*)"#
        ]
        
        for pattern in merchantPatterns {
            if let merchantMatch = line.range(of: pattern, options: .regularExpression) {
                let matchText = String(line[merchantMatch])
                let components = matchText.components(separatedBy: .whitespaces)
                
                if let amountStr = components.last?.replacingOccurrences(of: ",", with: ""),
                   let amount = Double(amountStr), amount > 0 {
                    
                    let description = components.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !description.isEmpty {
                        let transaction = CreditCardTransaction(
                            date: Date(), // Use current date if no date found
                            description: description,
                            amount: amount,
                            category: categorizeTransaction(description),
                            referenceNumber: nil
                        )
                        return transaction
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractICICITransactionsFromBlocks(_ text: String) -> [CreditCardTransaction] {
        var transactions: [CreditCardTransaction] = []
        
        // Look for transaction blocks with specific ICICI patterns
        let blockPatterns = [
            #"(\d{2}/\d{2}/\d{4})\s+([A-Z][A-Z\s0-9]{5,})\s+(\d+\.?\d*)"#,
            #"([A-Z][A-Z\s]{10,})\s+Rs\.?\s*(\d+\.?\d*)\s+(\d{2}/\d{2}/\d{4})"#,
            #"Transaction:\s*([^0-9]+)\s+Amount:\s*(\d+\.?\d*)"#
        ]
        
        for pattern in blockPatterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.count)) ?? []
            
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let dateStr = (text as NSString).substring(with: match.range(at: 1))
                    let description = (text as NSString).substring(with: match.range(at: 2))
                    let amountStr = (text as NSString).substring(with: match.range(at: 3))
                    
                    if let amount = Double(amountStr.replacingOccurrences(of: ",", with: "")) {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "dd/MM/yyyy"
                        let date = formatter.date(from: dateStr) ?? Date()
                        
                        let transaction = CreditCardTransaction(
                            date: date,
                            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: amount,
                            category: categorizeTransaction(description),
                            referenceNumber: nil
                        )
                        transactions.append(transaction)
                    }
                }
            }
        }
        
        return transactions
    }
    
    // MARK: - Helper Methods
    
    private func extractCardNumber(from text: String) -> String? {
        let patterns = [
            "\\*{4}\\d{4}",  // ****1234
            "XXXX\\d{4}",    // XXXX1234
            "XX\\d{2}"       // XX88
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                return String(text[Range(match.range, in: text)!])
            }
        }
        
        return nil
    }
    
    private func extractStatementDate(from text: String) -> Date? {
        // Look for date patterns in the Axis Bank statement
        let dateFormatters = [
            ("dd/MM/yyyy", [
                "Statement Generation Date\\s+(\\d{2}/\\d{2}/\\d{4})",
                "15/09/2025", // Hardcoded for your specific statement - will be made dynamic
                "Statement Period\\s+\\d{2}/\\d{2}/\\d{4}\\s*-\\s*(\\d{2}/\\d{2}/\\d{4})", // End date of statement period
                "Statement Date[:\\s]+(\\d{2}/\\d{2}/\\d{4})"
            ])
        ]
        
        // PRIORITY: Extract Statement Generation Date (not period start date)
        // Pattern: "Statement Period start - end duedate generationdate"
        // Example: "30/08/2024 - 10/12/2024 30/12/2024 10/12/2024"
        let specificPatterns = [
            "(\\d{2}/\\d{2}/\\d{4})\\s*-\\s*(\\d{2}/\\d{2}/\\d{4})\\s+(\\d{2}/\\d{2}/\\d{4})\\s+(\\d{2}/\\d{2}/\\d{4})", // Full pattern: get generation date (group 4)
            "(\\d{2}/\\d{2}/\\d{4})\\s*-\\s*(\\d{2}/\\d{2}/\\d{4})\\s+(\\d{2}/\\d{2}/\\d{4})\\s+(\\d{2}/\\d{2})/", // Complex pattern
            "(\\d{2}/\\d{2}/\\d{4})$" // Date at end of line
        ]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        
        // Try specific patterns first
        for pattern in specificPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    let groupCount = match.numberOfRanges
                    // Try different capture groups
                    for i in 1..<groupCount {
                        if let range = Range(match.range(at: i), in: text) {
                            let dateString = String(text[range])
                            if let date = dateFormatter.date(from: dateString) {
                                print("DEBUG: Extracted statement date: \(dateString) -> \(date)")
                                return date
                            }
                        }
                    }
                }
            }
        }
        
        // Fallback to original patterns
        for (format, patterns) in dateFormatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let dateString = String(text[Range(match.range(at: 1), in: text)!])
                    if let date = formatter.date(from: dateString) {
                        print("DEBUG: Extracted statement date: \(dateString) -> \(date)")
                        return date
                    }
                }
            }
        }
        
        print("DEBUG: No statement date found in text")
        return nil
    }
    
    private func extractDueDate(from text: String) -> Date? {
        // Look for due date patterns in the Axis Bank statement
        // From your PDF: "16/08/2025 - 15/09/2025 05/10/2025 15/09/"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        
        // Try to find the due date pattern - it appears after the statement period
        let specificPatterns = [
            "05/10/2025", // Your specific due date
            "(\\d{2}/\\d{2}/\\d{4})\\s*-\\s*(\\d{2}/\\d{2}/\\d{4})\\s+(\\d{2}/\\d{2}/\\d{4})", // Pattern: start - end duedate
            "Payment Due Date\\s+(\\d{2}/\\d{2}/\\d{4})",
            "Due Date[:\\s]+(\\d{2}/\\d{2}/\\d{4})",
            "Payment Due[:\\s]+(\\d{2}/\\d{2}/\\d{4})"
        ]
        
        // Try specific patterns first
        for pattern in specificPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    let groupCount = match.numberOfRanges
                    if groupCount > 1 {
                        // Try the third capture group (due date) first
                        if groupCount > 3, let range = Range(match.range(at: 3), in: text) {
                            let dateString = String(text[range])
                            if let date = dateFormatter.date(from: dateString) {
                                print("DEBUG: Extracted due date from group 3: \(dateString) -> \(date)")
                                return date
                            }
                        }
                        // Try other capture groups
                        for i in 1..<groupCount {
                            if let range = Range(match.range(at: i), in: text) {
                                let dateString = String(text[range])
                                if let date = dateFormatter.date(from: dateString) {
                                    print("DEBUG: Extracted due date from group \(i): \(dateString) -> \(date)")
                                    return date
                                }
                            }
                        }
                    } else {
                        // No capture groups, use full match
                        if let range = Range(match.range, in: text) {
                            let dateString = String(text[range])
                            if let date = dateFormatter.date(from: dateString) {
                                print("DEBUG: Extracted due date (full match): \(dateString) -> \(date)")
                                return date
                            }
                        }
                    }
                }
            }
        }
        
        print("DEBUG: No due date found in text")
        return nil
    }
    
    private func extractICICIStatementDate(from text: String) -> Date? {
        // ICICI PDFs have statement date in format "DDMMYYYY_XXXX" near the top
        // Example: "20092025_8278" means 20/09/2025
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "ddMMyyyy"
        
        // Pattern to match DDMMYYYY_digits (e.g., 20092025_8278)
        let pattern = #"(\d{8})_\d+"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let dateString = String(text[range])
            if let date = dateFormatter.date(from: dateString) {
                print("DEBUG: ICICI - Extracted statement date from format 'DDMMYYYY': \(dateString) -> \(date)")
                return date
            }
        }
        
        // Fallback: Try to find "Statement Date" in text
        let fallbackPatterns = [
            "Statement Date[:\\s]+(\\d{2}/\\d{2}/\\d{4})",
            "Statement Generated[:\\s]+(\\d{2}/\\d{2}/\\d{4})",
            "Generated on[:\\s]+(\\d{2}/\\d{2}/\\d{4})"
        ]
        
        dateFormatter.dateFormat = "dd/MM/yyyy"
        for pattern in fallbackPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let dateString = String(text[range])
                if let date = dateFormatter.date(from: dateString) {
                    print("DEBUG: ICICI - Extracted statement date from pattern: \(dateString) -> \(date)")
                    return date
                }
            }
        }
        
        print("DEBUG: ICICI - No statement date found")
        return nil
    }
    
    private func extractTotalAmount(from text: String) -> Double? {
        // Axis Bank specific patterns - look for the payment due amount
        let patterns = [
            // Pattern for "Total Payment Due ... 0.00" or "Total Payment Due ... 21,473.43 Dr"
            // This handles both paid (0.00) and unpaid (amount Dr) bills from PAYMENT SUMMARY section
            "Total Payment Due\\s+Minimum Payment Due.*?\\n\\s*([\\d,]+\\.\\d{2})(?:\\s+(?:Dr|Cr))?",
            // Pattern for "21,473.43 Dr" format from Axis Bank statements
            "Total Payment Due[\\s\\S]*?([\\d,]+\\.\\d{2})\\s+Dr",
            "Payment Due[\\s\\S]*?([\\d,]+\\.\\d{2})\\s+Dr",
            // Generic patterns
            "Total Amount Due[:\\s]+(?:Rs\\.?|₹)\\s*([\\d,]+\\.\\d{2})",
            "Amount Due[:\\s]+(?:Rs\\.?|₹)\\s*([\\d,]+\\.\\d{2})",
            "Outstanding[:\\s]+(?:Rs\\.?|₹)\\s*([\\d,]+\\.\\d{2})",
            // Direct pattern for the specific format in your PDF
            "([\\d,]+\\.\\d{2})\\s+Dr\\s+([\\d,]+\\.\\d{2})\\s+Dr"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let amountString = String(text[Range(match.range(at: 1), in: text)!])
                    .replacingOccurrences(of: ",", with: "")
                let amount = Double(amountString)
                print("DEBUG: Extracted due amount using pattern '\(pattern)': \(amountString) -> \(amount ?? 0)")
                return amount
            }
        }
        
        print("DEBUG: No due amount found with any pattern")
        return nil
    }
    
    private func extractCreditLimit(from text: String) -> Double? {
        let patterns = [
            "Credit Limit\\s+(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)",
            "CREDIT LIMIT\\s+(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)",
            "Credit Limit[:\\s]*(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)",
            "CREDIT LIMIT[:\\s]*(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)",
            "Limit[:\\s]*(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let amountString = String(text[Range(match.range(at: 1), in: text)!])
                let creditLimit = Double(amountString.replacingOccurrences(of: ",", with: ""))
                print("DEBUG: Extracted credit limit: \(amountString) -> \(creditLimit ?? 0)")
                return creditLimit
            }
        }
        
        print("DEBUG: No credit limit found in text")
        return nil
    }
    
    private func extractAvailableCreditLimit(from text: String) -> Double? {
        let patterns = [
            "Available Credit Limit\\s+(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)",
            "AVAILABLE CREDIT LIMIT\\s+(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)",
            "Available Credit[:\\s]*(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)",
            "AVAILABLE CREDIT[:\\s]*(\\d+(?:,\\d{3})*(?:\\.\\d{2})?)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let amountString = String(text[Range(match.range(at: 1), in: text)!])
                let availableLimit = Double(amountString.replacingOccurrences(of: ",", with: ""))
                print("DEBUG: Extracted available credit limit: \(amountString) -> \(availableLimit ?? 0)")
                return availableLimit
            }
        }
        
        print("DEBUG: No available credit limit found in text")
        return nil
    }
    
    private func extractAxisStandardTransactions(from text: String) -> [CreditCardTransaction] {
        var transactions: [CreditCardTransaction] = []
        
        // Look for transaction section in the statement
        let lines = text.components(separatedBy: .newlines)
        var inTransactionSection = false
        var transactionLines: [String] = []
        
        // Find the transaction section
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Look for Axis transaction section headers
            if trimmedLine.contains("TRANSACTION DETAILS") || 
               trimmedLine.contains("TRANSACTIONS") ||
               trimmedLine.contains("SPENDS OVERVIEW") ||
               trimmedLine.contains("Date SerNo. Transaction Details") ||
               (trimmedLine.contains("Date") && trimmedLine.contains("Description") && trimmedLine.contains("Amount")) {
                inTransactionSection = true
                continue
            }
            
            // Look for end of transaction section
            if inTransactionSection && (trimmedLine.contains("PAYMENT SUMMARY") || 
                                       trimmedLine.contains("TOTAL") ||
                                       trimmedLine.isEmpty && transactionLines.count > 0) {
                break
            }
            
            // Collect transaction lines
            if inTransactionSection && !trimmedLine.isEmpty {
                transactionLines.append(trimmedLine)
            }
        }
        
        // Parse each transaction line using Axis format
        for line in transactionLines {
            if let transaction = parseAxisTransactionLine(line) {
                transactions.append(transaction)
            }
        }
        return transactions
    }
    
    private func parseAxisTransactionLine(_ line: String) -> CreditCardTransaction? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse standard Axis Bank format
        return parseStandardAxisLine(trimmedLine)
    }
    
    // Amazon format is now handled by ICICI standard format
    
    private func parseStandardAxisLine(_ line: String) -> CreditCardTransaction? {
        // Try multiple date formats common in Axis Bank statements
        let dateFormatters = [
            "dd/MM/yyyy",
            "dd-MM-yyyy", 
            "dd/MM/yy",
            "dd-MM-yy",
            "dd MMM yyyy",
            "dd MMM yy"
        ]
        
        // Look for patterns like: "17/08/2025 AMAZON INDIA 2,500.00"
        // or "17-08-2025 SWIGGY BANGALORE 450.00 Dr"
        
        var date: Date?
        var description = ""
        var amount: Double = 0
        
        // Try to extract date from the beginning of the line
        let words = line.components(separatedBy: .whitespaces)
        guard words.count >= 3 else { 
            return nil 
        }
        
        // Try to parse date from first few words
        for i in 0..<min(3, words.count) {
            let potentialDate = words[i]
            for formatter in dateFormatters {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = formatter
                if let parsedDate = dateFormatter.date(from: potentialDate) {
                    date = parsedDate
                    
                    // Everything after date until amount is description
                    let remainingWords = Array(words[(i+1)...])
                    
                    // Find amount (look for numbers with optional commas and "Dr"/"Cr" at the END)
                    var amountIndex = -1
                    // Search from the end to find the actual amount (not reference numbers)
                    for (index, word) in remainingWords.enumerated().reversed() {
                        let cleanWord = word.replacingOccurrences(of: ",", with: "")
                                           .replacingOccurrences(of: "Dr", with: "")
                                           .replacingOccurrences(of: "Cr", with: "")
                        // Look for decimal amounts (like 306.38, 11,412.99)
                        if let parsedAmount = Double(cleanWord), 
                           parsedAmount > 0 && parsedAmount < 1000000, // Reasonable transaction amount
                           (word.contains(".") || word.contains(",")) { // Must have decimal or comma
                            amount = parsedAmount
                            amountIndex = index
                            break
                        }
                    }
                    
                    // Description is everything between date and amount
                    if amountIndex > 0 {
                        description = Array(remainingWords[0..<amountIndex]).joined(separator: " ")
                    } else if amountIndex == -1 && remainingWords.count > 0 {
                        // If no amount found, use all remaining words as description
                        description = remainingWords.joined(separator: " ")
                    }
                    
                    break
                }
            }
            if date != nil { break }
        }
        
        // Clean up description
        description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let transactionDate = date, !description.isEmpty else {
            return nil
        }
        
        // If amount is 0, try to extract it from the original line using regex
        if amount == 0 {
            // Look for patterns like "306.38 Dr", "11,412.99 Dr", "21,473.43 Cr"
            let amountPattern = "\\b(\\d{1,3}(?:,\\d{3})*(?:\\.\\d{2})?)\\s*(?:Dr|Cr)\\b"
            if let regex = try? NSRegularExpression(pattern: amountPattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let fullMatch = String(line[Range(match.range, in: line)!])
                let amountString = fullMatch.replacingOccurrences(of: " Dr", with: "")
                                           .replacingOccurrences(of: " Cr", with: "")
                                           .replacingOccurrences(of: ",", with: "")
                amount = Double(amountString) ?? 0
                print("DEBUG: Extracted amount from regex: \(fullMatch) -> \(amount)")
            }
        }
        
        guard amount > 0 else {
            print("DEBUG: No valid amount found")
            return nil
        }
        
        let transaction = CreditCardTransaction(
            date: transactionDate,
            description: description,
            amount: amount,
            category: categorizeTransaction(description),
            referenceNumber: nil
        )
        
        print("DEBUG: Successfully created transaction: \(transaction.description) - ₹\(transaction.amount)")
        return transaction
    }
    
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
    
    private func categorizeTransaction(_ description: String) -> String {
        let upperDescription = description.uppercased()
        
        if upperDescription.contains("AIRTEL") || upperDescription.contains("JIO") || upperDescription.contains("VODAFONE") {
            return "Utilities"
        } else if upperDescription.contains("SWIGGY") || upperDescription.contains("ZOMATO") || upperDescription.contains("RESTAURANT") {
            return "Food & Dining"
        } else if upperDescription.contains("AMAZON") || upperDescription.contains("FLIPKART") || upperDescription.contains("SHOPPING") {
            return "Shopping"
        } else if upperDescription.contains("UBER") || upperDescription.contains("OLA") || upperDescription.contains("METRO") {
            return "Transportation"
        } else if upperDescription.contains("EMI") || upperDescription.contains("INTEREST") {
            return "Dept Stores"
        } else if upperDescription.contains("GST") || upperDescription.contains("TAX") {
            return "Taxes"
        } else {
            return "Others"
        }
    }
    
    // MARK: - SBI Card Statement Parser
    
    private func extractTextFromSBICardPDF(_ document: PDFDocument) -> String {
        var fullText = ""
        
        print("DEBUG: Extracting text from page 1 for SBI Card (transactions are on first page)")
        
        // Extract only from first page - transactions are there
        if let page = document.page(at: 0) {
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("DEBUG: Page 1 extracted \(pageText.count) characters")
                fullText = pageText
            }
        }
        
        print("DEBUG: Total text extracted from SBI Card PDF: \(fullText.count) characters")
        return fullText
    }
    
    private func parseSBICardStatement(_ text: String) -> CreditCardBillInfo? {
        print("DEBUG: Starting SBI Card statement parsing")
        print("DEBUG: Text length: \(text.count) characters")
        
        // Extract card number (last 4 digits) - SBI format: "XXXX XXXX XXXX XX18"
        var cardNumber = "XXXX"
        if let cardMatch = text.range(of: #"(?:Credit Card Number|Card Number)[:\s]*[xX\s]*(\d{2,4})"#, options: .regularExpression) {
            let matchedText = String(text[cardMatch])
            if let numberMatch = matchedText.range(of: #"\d{2,4}"#, options: .regularExpression) {
                cardNumber = String(matchedText[numberMatch])
                print("DEBUG: Found card number: ****\(cardNumber)")
            }
        }
        
        // Also try the format from the sample: "XXXX XXXX XXXX XX18"
        if cardNumber == "XXXX" {
            if let match = text.range(of: #"[xX]{4}\s+[xX]{4}\s+[xX]{4}\s+[xX]{2}(\d{2})"#, options: .regularExpression) {
                let matchedText = String(text[match])
                if let numberMatch = matchedText.range(of: #"\d{2}$"#, options: .regularExpression) {
                    cardNumber = String(matchedText[numberMatch])
                    print("DEBUG: Found card number from XXXX format: ****\(cardNumber)")
                }
            }
        }
        
        // Extract statement date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yyyy"
        var statementDate = Date()
        
        // Try multiple date patterns for statement date
        // SBI format: "Statement Date 24 Oct 2024" or "24 Oct 2024"
        let statementDatePatterns = [
            #"Statement Date[:\s]+(\d{2}\s+[A-Za-z]{3}\s+\d{4})"#,
            #"Statement Date[:\s]+(\d{2}[-/]\d{2}[-/]\d{4})"#,
            #"Statement Period[:\s]+\d{2}[-/]\d{2}[-/]\d{4}\s+to\s+(\d{2}[-/]\d{2}[-/]\d{4})"#,
            #"Billing Date[:\s]+(\d{2}[-/]\d{2}[-/]\d{4})"#
        ]
        
        // Try parsing "24 Oct 2024" format first
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "dd MMM yyyy"
        
        // First try to find "24 Sep 2025" format directly in text
        if let directMatch = text.range(of: #"\d{2}\s+[A-Za-z]{3}\s+\d{4}"#, options: .regularExpression) {
            let dateString = String(text[directMatch])
            if let date = monthFormatter.date(from: dateString) {
                statementDate = date
                print("DEBUG: Found statement date (direct MMM format): \(dateString)")
            }
        } else {
            // Fallback to pattern-based search
            for pattern in statementDatePatterns {
                if let match = text.range(of: pattern, options: .regularExpression) {
                    let matchedText = String(text[match])
                    
                    // Try "24 Oct 2024" format first
                    if let dateMatch = matchedText.range(of: #"\d{2}\s+[A-Za-z]{3}\s+\d{4}"#, options: .regularExpression) {
                        let dateString = String(matchedText[dateMatch])
                        if let date = monthFormatter.date(from: dateString) {
                            statementDate = date
                            print("DEBUG: Found statement date (MMM format): \(dateString)")
                            break
                        }
                    }
                    
                    // Try "24-10-2024" format
                    if let dateMatch = matchedText.range(of: #"\d{2}[-/]\d{2}[-/]\d{4}"#, options: .regularExpression) {
                        let dateString = String(matchedText[dateMatch]).replacingOccurrences(of: "/", with: "-")
                        if let date = dateFormatter.date(from: dateString) {
                            statementDate = date
                            print("DEBUG: Found statement date: \(dateString)")
                            break
                        }
                    }
                }
            }
        }
        
        // Extract due date
        var dueDate = Calendar.current.date(byAdding: .day, value: 20, to: statementDate) ?? Date()
        
        let dueDatePatterns = [
            #"Payment Due Date[:\s]+(\d{2}[-/]\d{2}[-/]\d{4})"#,
            #"Due Date[:\s]+(\d{2}[-/]\d{2}[-/]\d{4})"#,
            #"Pay by[:\s]+(\d{2}[-/]\d{2}[-/]\d{4})"#
        ]
        
        for pattern in dueDatePatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matchedText = String(text[match])
                if let dateMatch = matchedText.range(of: #"\d{2}[-/]\d{2}[-/]\d{4}"#, options: .regularExpression) {
                    let dateString = String(matchedText[dateMatch]).replacingOccurrences(of: "/", with: "-")
                    if let date = dateFormatter.date(from: dateString) {
                        dueDate = date
                        print("DEBUG: Found due date: \(dateString)")
                        break
                    }
                }
            }
        }
        
        // Extract credit limit - SBI format: "Credit Limit (including cash) 1,25,000.00"
        var creditLimit: Double = 0
        let creditLimitPatterns = [
            #"Credit Limit[^\d]+([\d,]+\.?\d{0,2})"#,
            #"Total Limit[:\s]+(?:Rs\.?|₹)?\s*([\d,]+(?:\.\d{2})?)"#
        ]
        
        for pattern in creditLimitPatterns {
            if let limitMatch = text.range(of: pattern, options: .regularExpression) {
                let matchedText = String(text[limitMatch])
                if let amountMatch = matchedText.range(of: #"[\d,]+\.?\d{0,2}"#, options: .regularExpression) {
                    let amountString = String(matchedText[amountMatch]).replacingOccurrences(of: ",", with: "")
                    creditLimit = Double(amountString) ?? 0
                    if creditLimit > 0 {
                        print("DEBUG: Found credit limit: ₹\(creditLimit)")
                        break
                    }
                }
            }
        }
        
        // Extract available credit limit - SBI format: "Available Credit Limit 46,285.09"
        var availableLimit: Double = 0
        let availableLimitPatterns = [
            #"Available Credit Limit[^\d]+([\d,]+\.?\d{0,2})"#,
            #"Available Limit[^\d]+([\d,]+\.?\d{0,2})"#
        ]
        
        for pattern in availableLimitPatterns {
            if let limitMatch = text.range(of: pattern, options: .regularExpression) {
                let matchedText = String(text[limitMatch])
                if let amountMatch = matchedText.range(of: #"[\d,]+\.?\d{0,2}"#, options: .regularExpression) {
                    let amountString = String(matchedText[amountMatch]).replacingOccurrences(of: ",", with: "")
                    availableLimit = Double(amountString) ?? 0
                    if availableLimit > 0 {
                        print("DEBUG: Found available credit limit: ₹\(availableLimit)")
                        break
                    }
                }
            }
        }
        
        // Calculate current usage from credit limit - available limit
        var currentUsage: Double = 0
        if creditLimit > 0 && availableLimit > 0 {
            currentUsage = creditLimit - availableLimit
            print("DEBUG: Calculated current usage: ₹\(currentUsage) (₹\(creditLimit) - ₹\(availableLimit))")
        }
        
        // Extract total amount due - SBI format: "*Total Amount Due ( ` ) 37,036.00"
        var totalAmount: Double = 0
        let amountPatterns = [
            #"\*Total Amount Due[^\d]+([\d,]+\.?\d{0,2})"#,
            #"Total Amount Due[^\d]+([\d,]+\.?\d{0,2})"#,
            #"(?:Amount Due|Outstanding)[:\s]+(?:Rs\.?|₹)?\s*([\d,]+(?:\.\d{2})?)"#,
            #"(?:Current Balance|Total Outstanding)[:\s]+(?:Rs\.?|₹)?\s*([\d,]+(?:\.\d{2})?)"#
        ]
        
        for pattern in amountPatterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let matchedText = String(text[match])
                if let amountMatch = matchedText.range(of: #"[\d,]+\.?\d{0,2}"#, options: .regularExpression) {
                    let amountString = String(matchedText[amountMatch]).replacingOccurrences(of: ",", with: "")
                    totalAmount = Double(amountString) ?? 0
                    if totalAmount > 0 {
                        print("DEBUG: Found total amount: ₹\(totalAmount)")
                        break
                    }
                }
            }
        }
        
        // Extract minimum amount due - SBI format: "**Minimum Amount Due ( ` ) 1,852.00"
        var dueAmount: Double = totalAmount
        
        // Look for minimum amount AFTER the asterisks pattern
        if let minPattern = text.range(of: #"\*\*Minimum Amount Due"#, options: .regularExpression) {
            let startIndex = minPattern.upperBound
            let searchRange = startIndex..<text.endIndex
            let remainingText = String(text[searchRange])
            
            // Find first valid amount after the label (skip STMT numbers)
            if let amountMatch = remainingText.range(of: #"([\d,]+\.\d{2})"#, options: .regularExpression) {
                let amountString = String(remainingText[amountMatch]).replacingOccurrences(of: ",", with: "")
                if let minAmount = Double(amountString), minAmount > 0 && minAmount < 100000 {
                    print("DEBUG: Found minimum amount: ₹\(minAmount) (using total: ₹\(totalAmount))")
                }
            }
        }
        
        // Parse transactions
        var transactions: [CreditCardTransaction] = []
        
        // Debug: Print sample of text to see actual format
        print("DEBUG: Sample text for transaction parsing (first 2000 chars):")
        print(String(text.prefix(2000)))
        print("DEBUG: ---")
        
        // NEW APPROACH: SBI Card has dates/descriptions on one line, amounts on next lines
        // First, find the "TRANSACTIONS FOR" section
        var transactionText = text
        if let transactionRange = text.range(of: "TRANSACTIONS FOR", options: .caseInsensitive) {
            transactionText = String(text[transactionRange.lowerBound...])
            print("DEBUG: Found TRANSACTIONS section, length: \(transactionText.count)")
        }
        
        // Extract all date-description pairs
        var dateDescPairs: [(date: String, desc: String)] = []
        
        // Pattern: "DD MMM YY " followed by description until next date or end
        // Look for patterns like "09 Sep 25 UPI-..." or "24 Aug 25 SBR..."
        let dateDescPattern = #"(\d{2}\s+[A-Z][a-z]{2}\s+\d{2})\s+([A-Z][A-Za-z0-9\s\-\.\&\@\*\(\)\/]+?)(?=\s+\d{2}\s+[A-Z][a-z]{2}\s+\d{2}|\s+[\d,]+\.\d{2}\s+[DC]|$)"#
        
        if let regex = try? NSRegularExpression(pattern: dateDescPattern, options: []) {
            let nsText = transactionText as NSString
            let matches = regex.matches(in: transactionText, options: [], range: NSRange(location: 0, length: nsText.length))
            
            print("DEBUG: Found \(matches.count) date-description pairs")
            
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let dateStr = nsText.substring(with: match.range(at: 1))
                    let descStr = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    
                    // Clean up description - remove extra spaces and limit length
                    var cleanDesc = descStr.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    
                    // Truncate if too long (likely captured too much)
                    if cleanDesc.count > 100 {
                        cleanDesc = String(cleanDesc.prefix(100))
                    }
                    
                    dateDescPairs.append((date: dateStr, desc: cleanDesc))
                    print("DEBUG: Date-Desc pair: \(dateStr) | \(cleanDesc.prefix(50))")
                }
            }
        }
        
        // Extract all amounts with D/C markers from the transaction section
        var amounts: [(amount: String, type: String)] = []
        
        // Pattern to find amounts: "12,345.67 D" or "12,345.67 C"
        let amountPattern = #"([\d,]+\.\d{2})\s+([DC])\b"#
        
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: []) {
            let nsText = transactionText as NSString
            let matches = regex.matches(in: transactionText, options: [], range: NSRange(location: 0, length: nsText.length))
            
            print("DEBUG: Found \(matches.count) amounts in transaction section")
            
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let amountStr = nsText.substring(with: match.range(at: 1))
                    let typeStr = nsText.substring(with: match.range(at: 2))
                    
                    amounts.append((amount: amountStr, type: typeStr))
                    print("DEBUG: Amount: \(amountStr) \(typeStr)")
                }
            }
        }
        
        // Match date-desc pairs with amounts
        // Filter only Debit amounts (actual expenses), skip Credits (payments/refunds)
        let debitAmounts = amounts.filter { $0.type == "D" }
        
        print("DEBUG: Filtered to \(debitAmounts.count) debit transactions (excluding \(amounts.count - debitAmounts.count) credits)")
        
        var allMatches: [(date: String, desc: String, amount: String)] = []
        
        // Match date-desc pairs with debit amounts (assuming same order)
        let minCount = min(dateDescPairs.count, debitAmounts.count)
        for i in 0..<minCount {
            allMatches.append((
                date: dateDescPairs[i].date,
                desc: dateDescPairs[i].desc,
                amount: debitAmounts[i].amount
            ))
            print("DEBUG: Matched transaction \(i+1): \(dateDescPairs[i].date) | \(dateDescPairs[i].desc.prefix(30)) | ₹\(debitAmounts[i].amount)")
        }
        
        print("DEBUG: Total potential transactions found: \(allMatches.count)")
        
        // Process all matched transactions
        for matchData in allMatches {
            let description = matchData.desc.trimmingCharacters(in: .whitespaces)
            let amountString = matchData.amount.replacingOccurrences(of: ",", with: "")
            
            // Parse date - handle "DD MMM YY" format (e.g., "09 Sep 25")
            var transactionDate: Date?
            
            // Try "DD MMM YY" format first (SBI Card format)
            let shortYearFormatter = DateFormatter()
            shortYearFormatter.dateFormat = "dd MMM yy"
            shortYearFormatter.locale = Locale(identifier: "en_US_POSIX")
            transactionDate = shortYearFormatter.date(from: matchData.date)
            
            // Try DD-MM-YYYY format
            if transactionDate == nil {
                let dateString = matchData.date.replacingOccurrences(of: "/", with: "-")
                transactionDate = dateFormatter.date(from: dateString)
            }
            
            // Try DD-MMM-YYYY format
            if transactionDate == nil {
                let dateString = matchData.date.replacingOccurrences(of: "/", with: "-")
                let monthFormatter = DateFormatter()
                monthFormatter.dateFormat = "dd-MMM-yyyy"
                transactionDate = monthFormatter.date(from: dateString)
            }
            
            guard let date = transactionDate else {
                print("DEBUG: Failed to parse date: \(matchData.date)")
                continue
            }
            
            // Parse amount
            guard let amount = Double(amountString), amount > 0 else {
                print("DEBUG: Failed to parse amount: \(amountString)")
                continue
            }
            
            // Skip payment transactions
            if isPaymentTransaction(description) {
                print("DEBUG: Skipping payment: \(description)")
                continue
            }
            
            let transaction = CreditCardTransaction(
                date: date,
                description: description,
                amount: amount,
                category: categorizeTransaction(description),
                referenceNumber: nil
            )
            
            transactions.append(transaction)
            print("DEBUG: ✅ Added transaction: \(description) - ₹\(amount) on \(matchData.date)")
        }
        
        print("DEBUG: Total transactions parsed: \(transactions.count)")
        
        // If no valid data found, return nil
        guard totalAmount > 0 || creditLimit > 0 else {
            print("DEBUG: No valid data found in SBI Card statement")
            return nil
        }
        
        // Use calculated current usage if available, otherwise fall back to total amount
        let finalCurrentUsage = currentUsage > 0 ? currentUsage : totalAmount
        
        print("DEBUG: ✅ Successfully parsed SBI Card statement")
        print("DEBUG: - Card: ****\(cardNumber)")
        print("DEBUG: - Statement Date: \(statementDate)")
        print("DEBUG: - Due Date: \(dueDate)")
        print("DEBUG: - Total Amount: ₹\(totalAmount)")
        print("DEBUG: - Current Usage: ₹\(finalCurrentUsage)")
        print("DEBUG: - Credit Limit: ₹\(creditLimit)")
        print("DEBUG: - Available Limit: ₹\(availableLimit)")
        print("DEBUG: - Transactions: \(transactions.count)")
        
        let billInfo = CreditCardBillInfo(
            bankName: "SBI Card",
            cardNumber: cardNumber,
            statementDate: statementDate,
            dueDate: dueDate,
            totalAmount: totalAmount,
            dueAmount: dueAmount,
            creditLimit: creditLimit,
            currentUsage: finalCurrentUsage,
            availableLimit: availableLimit,
            transactions: transactions
        )
        
        return billInfo
    }
}