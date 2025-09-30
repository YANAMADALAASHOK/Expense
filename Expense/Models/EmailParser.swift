import Foundation

struct ParsedEmailTransaction {
    let subject: String
    let body: String
    let amount: Double
    let date: Date
    let isCredit: Bool
    let description: String
    let suggestedCategory: String
}

enum EmailParseError: Error, LocalizedError {
    case notRecognized
    case amountMissing
    case dateMissing

    var errorDescription: String? {
        switch self {
        case .notRecognized: return "Email format not recognized"
        case .amountMissing: return "Could not find amount in email"
        case .dateMissing: return "Could not find date in email"
        }
    }
}

final class EmailParser {
    #if DEBUG
    static var debugEnabled = true
    #else
    static var debugEnabled = false
    #endif
    static func parse(subject: String?, body: String?) throws -> ParsedEmailTransaction {
        let subj = subject ?? ""
        let bodyText = (body ?? "")
        let plainBody = htmlToPlainText(bodyText)
        let full = (subj + "\n" + plainBody)
        
        // Try bank-specific parsers FIRST for better accuracy (no pre-filter)
        if let axisTx = parseAxisBankTransaction(subject: subj, body: plainBody) {
            return axisTx
        }
        if let iciciTx = parseICICIBankTransaction(subject: subj, body: plainBody) {
            return iciciTx
        }
        
        // Pre-filter: Only process emails that look like transaction notifications
        // Be permissive, but still avoid obvious non-transactionals
        if !isTransactionEmail(subject: subj, body: plainBody) {
            if debugEnabled {
                print("[EmailParser] Pre-filter rejected email:")
                print("Subject: \(subj)")
                print("Body preview: \(String(plainBody.prefix(200)))")
            }
            throw EmailParseError.notRecognized
        }

        // Determine credit/debit (ICICI phrasing + generic)
        let containsCredited = full.range(of: "credited", options: .caseInsensitive) != nil ||
                               full.range(of: "amount credited", options: .caseInsensitive) != nil ||
                               full.range(of: "refund", options: .caseInsensitive) != nil
        let containsDebited = full.range(of: "debited", options: .caseInsensitive) != nil ||
                              full.range(of: "amount debited", options: .caseInsensitive) != nil ||
                              full.range(of: "has been used for a transaction", options: .caseInsensitive) != nil
        let isCredit = containsCredited && !containsDebited
        let isDeb = containsDebited && !containsCredited
        let creditFlag = isCredit && !isDeb

        // Amount: prefer ICICI pattern "transaction of INR xxx" then fallback to first INR/Rs/₹ occurrence
        var amount: Double = 0
        let primaryAmountRegex = try! NSRegularExpression(pattern: "transaction\\s+of\\s+(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)", options: .caseInsensitive)
        if let m = primaryAmountRegex.firstMatch(in: full, options: [], range: NSRange(location: 0, length: full.utf16.count)) {
            let amountStr = (full as NSString).substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
            amount = Double(amountStr) ?? 0
        } else {
            // Try on a whitespace-collapsed version to avoid line-break issues
            let collapsed = full.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if let m2 = primaryAmountRegex.firstMatch(in: collapsed, options: [], range: NSRange(location: 0, length: collapsed.utf16.count)) {
                let amountStr = (collapsed as NSString).substring(with: m2.range(at: 1)).replacingOccurrences(of: ",", with: "")
                amount = Double(amountStr) ?? 0
            } else {
                let amountRegex = try! NSRegularExpression(pattern: "(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)", options: [])
                if let aMatch = amountRegex.firstMatch(in: full, options: [], range: NSRange(location: 0, length: full.utf16.count)) {
                    let amountStr = (full as NSString).substring(with: aMatch.range(at: 1)).replacingOccurrences(of: ",", with: "")
                    amount = Double(amountStr) ?? 0
                } else if let aMatch2 = amountRegex.firstMatch(in: collapsed, options: [], range: NSRange(location: 0, length: collapsed.utf16.count)) {
                    let amountStr = (collapsed as NSString).substring(with: aMatch2.range(at: 1)).replacingOccurrences(of: ",", with: "")
                    amount = Double(amountStr) ?? 0
                } else {
                    throw EmailParseError.amountMissing
                }
            }
        }

        // Date: try Axis style "Date & Time:" first, then generic, then ICICI style
        var parsedDate: Date? = extractAxisDate(from: full)
        if parsedDate == nil {
            // ICICI Gmail example: "on Sep 06, 2025 at 04:21:53" or "Sep 06, 2025 at 04:21"
            if let dt = extractICICIGmailDate(from: full) {
                parsedDate = dt
            }
        }
        // Date: dd-MM-yy or dd-MM-yyyy (optionally with time)
        let dateRegexes = [
            // Specific pattern for "20-09-25, 14:23:24 IST" format
            "(\\b[0-3]?[0-9]-[0-1]?[0-9]-[0-9]{2,4}),\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])\\s*(?:IST|GMT|UTC)?",
            // General patterns
            "(\\b[0-3]?[0-9]-[0-1]?[0-9]-[0-9]{2,4}),?\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])?\\s*(?:IST|GMT|UTC)?",
            "(\\b[0-3]?[0-9]/[0-1]?[0-9]/[0-9]{2,4}),?\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])?\\s*(?:IST|GMT|UTC)?",
            // Additional patterns for common email formats
            "(\\b[0-3]?[0-9]\\s+[A-Za-z]{3,9}\\s+[0-9]{4}),?\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])?\\s*(?:IST|GMT|UTC)?",
            "(\\b[A-Za-z]{3,9}\\s+[0-3]?[0-9],?\\s+[0-9]{4}),?\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])?\\s*(?:IST|GMT|UTC)?"
        ]
        outer: for pattern in dateRegexes {
            let re = try! NSRegularExpression(pattern: pattern)
            if let m = re.firstMatch(in: full, options: [], range: NSRange(location: 0, length: full.utf16.count)) {
                let dStr = (full as NSString).substring(with: m.range(at: 1))
                let tStr = m.range(at: 2).location != NSNotFound ? (full as NSString).substring(with: m.range(at: 2)) : nil
                
                if debugEnabled {
                    print("[EmailParser] Generic date extraction:")
                    print("  Pattern: \(pattern)")
                    print("  Date string: '\(dStr)'")
                    print("  Time string: '\(tStr ?? "nil")'")
                }
                
                let fmts = [
                    "dd-MM-yy HH:mm:ss",
                    "dd-MM-yyyy HH:mm:ss",
                    "dd/MM/yy HH:mm:ss",
                    "dd/MM/yyyy HH:mm:ss",
                    "dd MMM yyyy HH:mm:ss",
                    "d MMM yyyy HH:mm:ss",
                    "MMM dd, yyyy HH:mm:ss",
                    "MMM d, yyyy HH:mm:ss",
                    "dd-MM-yy",
                    "dd-MM-yyyy",
                    "dd/MM/yy",
                    "dd/MM/yyyy",
                    "dd MMM yyyy",
                    "d MMM yyyy",
                    "MMM dd, yyyy",
                    "MMM d, yyyy"
                ]
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_IN")
                for f in fmts {
                    df.dateFormat = f
                    let combined = [dStr, tStr].compactMap{$0}.joined(separator: " ")
                    if let dt = df.date(from: combined) { 
                        if debugEnabled {
                            print("  Matched format '\(f)' with '\(combined)' -> \(dt)")
                        }
                        parsedDate = dt; break outer 
                    }
                }
                if debugEnabled {
                    print("  No format matched for: '\([dStr, tStr].compactMap{$0}.joined(separator: " "))'")
                }
            }
        }
        // If date not found, fallback to now instead of failing the parse
        let date = parsedDate ?? Date()
        
        // Ensure we preserve the time component if it was parsed
        if parsedDate == nil {
            if debugEnabled {
                print("[EmailParser] No date found in email, using current time: \(date)")
            }
        }
        
        if debugEnabled {
            print("[EmailParser] Date parsing result:")
            print("  Parsed date: \(parsedDate?.description ?? "nil")")
            print("  Final date: \(date)")
            print("  Date components: \(Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date))")
        }

        // Description
        var desc = extractTransactionInfo(from: full)
        // ICICI Gmail often has "Info: ..." line
        if desc.isEmpty, let info = extractICICIInfo(from: full) {
            desc = info
        }
        // Append masked card if present (e.g., XX3000)
        if let masked = extractICICIMaskedCard(from: full), !masked.isEmpty {
            let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { desc = "Card: \(masked)" } else { desc = "\(trimmed) [Card: \(masked)]" }
        }
        if desc.isEmpty { desc = subj }

        // Suggested category
        let lc = (desc + "\n" + full).lowercased()
        let suggested: String
        if lc.contains("zomato") { suggested = TransactionCategory.food.rawValue }
        else if lc.contains("amazon") || lc.contains("flipkart") { suggested = TransactionCategory.shopping.rawValue }
        else if lc.contains("salary") || lc.contains("payroll") { suggested = TransactionCategory.salary.rawValue }
        else if lc.range(of: "\\b(cred|credit card|cc bill|card payment)\\b", options: .regularExpression) != nil { suggested = TransactionCategory.creditCardPayment.rawValue }
        else if lc.contains("groww") || lc.contains("bse") || lc.contains("nse") || lc.contains("mf ") { suggested = TransactionCategory.investment.rawValue }
        else { suggested = TransactionCategory.other.rawValue }

        if debugEnabled {
            print("[EmailParser] --- DEBUG ---")
            print("Subject: \(subj)")
            print("Body (first 400): \(String(plainBody.prefix(400)))")
            print("Detected amount: \(amount)")
            print("IsCredit: \(creditFlag)")
            print("Date: \(date)")
            print("Description: \(desc)")
            print("Suggested: \(suggested)")
        }
        return ParsedEmailTransaction(subject: subj, body: plainBody, amount: amount, date: date, isCredit: creditFlag, description: desc, suggestedCategory: suggested)
    }

    static func htmlToPlainText(_ htmlOrText: String) -> String {
        guard htmlOrText.contains("<") else { return normalized(htmlOrText) }
        if let data = htmlOrText.data(using: .utf8),
           let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
            return normalized(attr.string)
        }
        // Fallback strip tags roughly
        let stripped = htmlOrText.replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return normalized(stripped)
    }

    // Lightweight, non-blocking HTML to text converter for previews
    static func htmlToPlainTextLightweight(_ htmlOrText: String) -> String {
        guard htmlOrText.contains("<") else { return normalized(htmlOrText) }
        // Avoid heavy NSAttributedString parsing; just strip common tags/entities
        let stripped = htmlOrText
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return normalized(stripped)
    }

    private static func normalized(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ") // non-breaking space
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\r", with: "")
    }

    private static func extractAxisDate(from text: String) -> Date? {
        // Look for a line after "Date & Time:"
        if let range = text.range(of: "Date & Time:", options: .caseInsensitive) {
            let after = text[range.upperBound...]
            let valueLine = after.split(separator: "\n").first.map(String.init) ?? ""
            let cleaned = valueLine.replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "IST", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if debugEnabled {
                print("[EmailParser] Axis date extraction:")
                print("  Raw value line: '\(valueLine)'")
                print("  Cleaned: '\(cleaned)'")
            }
            let fmts = [
                "dd-MM-yy HH:mm:ss",
                "dd-MM-yyyy HH:mm:ss",
                "dd/MM/yy HH:mm:ss",
                "dd/MM/yyyy HH:mm:ss",
                "dd-MM-yy",
                "dd-MM-yyyy",
                "dd/MM/yy",
                "dd/MM/yyyy"
            ]
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_IN")
            df.timeZone = TimeZone(identifier: "Asia/Kolkata")
            for f in fmts {
                df.dateFormat = f
                if let dt = df.date(from: cleaned) { 
                    if debugEnabled {
                        print("  Matched format '\(f)' -> \(dt)")
                    }
                    return dt 
                }
            }
            if debugEnabled {
                print("  No format matched for: '\(cleaned)'")
            }
        }
        return nil
    }

    // Generic dd-MM-yy(/yyyy) with optional time fallback, using IST timezone
    private static func extractGenericINDate(from text: String) -> Date? {
        let patterns = [
            "(\\b[0-3]?[0-9]-[0-1]?[0-9]-[0-9]{2,4}),\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])\\s*(?:IST|GMT|UTC)?",
            "(\\b[0-3]?[0-9]-[0-1]?[0-9]-[0-9]{2,4})",
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_IN")
        df.timeZone = TimeZone(identifier: "Asia/Kolkata")
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(location: 0, length: text.utf16.count)
                if let m = re.firstMatch(in: text, options: [], range: range) {
                    let dStr = (text as NSString).substring(with: m.range(at: 1))
                    let tStr = m.numberOfRanges > 2 && m.range(at: 2).location != NSNotFound ? (text as NSString).substring(with: m.range(at: 2)) : nil
                    let fmts: [String]
                    if let t = tStr, !t.isEmpty {
                        fmts = ["dd-MM-yy HH:mm:ss", "dd-MM-yyyy HH:mm:ss"]
                    } else {
                        fmts = ["dd-MM-yy", "dd-MM-yyyy"]
                    }
                    for f in fmts {
                        df.dateFormat = f
                        let composed = tStr != nil ? "\(dStr) \(tStr!)" : dStr
                        if let dt = df.date(from: composed) { return dt }
                    }
                }
            }
        }
        return nil
    }

    private static func extractICICIGmailDate(from text: String) -> Date? {
        // Matches: (optional "on ")Sep 06, 2025 at 04:21[:53] [IST]
        let pattern = "(?:on\\s+)?([A-Za-z]{3,9})\\s+([0-3]?\\d),\\s+(\\d{4})\\s+at\\s+([0-2]\\d:[0-5]\\d(?::[0-5]\\d)?)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        if let m = re.firstMatch(in: text, options: [], range: range) {
            let month = (text as NSString).substring(with: m.range(at: 1))
            let day = (text as NSString).substring(with: m.range(at: 2))
            let year = (text as NSString).substring(with: m.range(at: 3))
            let time = (text as NSString).substring(with: m.range(at: 4))
            let dateStr = "\(day) \(month) \(year) \(time)"
            
            if debugEnabled {
                print("[EmailParser] ICICI date extraction:")
                print("  Matched: month=\(month), day=\(day), year=\(year), time=\(time)")
                print("  Date string: '\(dateStr)'")
            }
            
            let fmts = ["d MMM yyyy HH:mm:ss", "dd MMM yyyy HH:mm:ss", "d MMM yyyy HH:mm", "dd MMM yyyy HH:mm"]
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "Asia/Kolkata")
            for f in fmts { 
                df.dateFormat = f
                if let dt = df.date(from: dateStr) { 
                    if debugEnabled {
                        print("  Matched format '\(f)' -> \(dt)")
                    }
                    return dt 
                }
            }
            if debugEnabled {
                print("  No format matched for: '\(dateStr)'")
            }
        }
        return nil
    }

    private static func extractICICIInfo(from text: String) -> String? {
        if let range = text.range(of: "Info:", options: .caseInsensitive) {
            let after = text[range.upperBound...]
            var info = after.components(separatedBy: CharacterSet.newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Trim trailing punctuation
            info = info.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return info.isEmpty ? nil : info
        }
        return nil
    }

    private static func extractICICIMaskedCard(from text: String) -> String? {
        // Matches: "Credit Card XX3000" and captures XX3000
        let pattern = "Credit\\s+Card\\s+(XX[0-9]{4})"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        if let m = re.firstMatch(in: text, options: [], range: range), m.numberOfRanges >= 2 {
            return (text as NSString).substring(with: m.range(at: 1))
        }
        return nil
    }

    private static func extractTransactionInfo(from text: String) -> String {
        // Prefer explicit label
        if let range = text.range(of: "Transaction Info:", options: .caseInsensitive) {
            let after = text[range.upperBound...]
            let candidate = after.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !candidate.isEmpty { return candidate }
        }
        // Common fallback patterns
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        // Look for UPI/IMPS/NEFT/ATM lines
        if let l = lines.first(where: { $0.range(of: "^(UPI|IMPS|NEFT|ATM|DEBIT CARD|CREDIT CARD)/", options: [.regularExpression, .caseInsensitive]) != nil }) {
            return l
        }
        // Look for a line that contains a long reference-like token and a merchant (ALL CAPS words)
        if let l = lines.first(where: { $0.contains("/") && $0.split(separator: "/").count >= 3 && $0.range(of: "[A-Z]{3,}", options: .regularExpression) != nil }) {
            return l
        }
        return ""
    }
    
    /// Pre-filter to only process emails that look like transaction notifications
    private static func isTransactionEmail(subject: String, body: String) -> Bool {
        let content = (subject + "\n" + body).lowercased()
        
        // Enhanced bank detection for Axis and ICICI
        let isAxisBank = content.contains("axis") || 
                        subject.lowercased().contains("axis bank") ||
                        content.contains("axisbank") ||
                        content.contains("axis.co.in")
        
        let isICICIBank = content.contains("icici") || 
                         subject.lowercased().contains("icici bank") ||
                         content.contains("icicibank") ||
                         content.contains("icici.com")
        
        // For Axis/ICICI emails, be more permissive but still filter out obvious non-transactions
        if isAxisBank || isICICIBank {
            // Specific transaction indicators for these banks
            let bankTransactionKeywords = [
                "transaction", "credited", "debited", "payment", "purchase",
                "withdrawal", "deposit", "deposited", "transfer", "upi", "imps", "neft",
                "atm", "card", "amount", "rs.", "inr", "₹", "account",
                "balance", "debit card", "credit card", "mobile banking",
                "credit transaction alert", "debit transaction alert", "salary"
            ]
            
            let hasBankTransactionKeyword = bankTransactionKeywords.contains { keyword in
                content.contains(keyword)
            }
            
            // Must have amount pattern for bank emails too
            let amountPattern = try! NSRegularExpression(pattern: "(?:inr|rs\\.?|₹)\\s*[0-9,]+(?:\\.[0-9]{1,2})?", options: .caseInsensitive)
            let hasAmount = amountPattern.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)) != nil
            
            // Exclude obvious non-transaction bank emails
            let bankExcludeKeywords = [
                "newsletter", "welcome to", "thank you for choosing", "promotional",
                "offer expires", "limited time offer", "exclusive offer",
                "monthly statement", "quarterly statement", "annual statement"
            ]
            
            let hasBankExcludeKeyword = bankExcludeKeywords.contains { keyword in
                content.contains(keyword)
            }
            
            return hasBankTransactionKeyword && hasAmount && !hasBankExcludeKeyword
        }
        
        // For other emails, check for basic transaction indicators
        let transactionKeywords = [
            "transaction", "credited", "debited", "payment", "purchase", 
            "withdrawal", "deposit", "transfer", "upi", "imps", "neft", 
            "atm", "card", "amount", "rs.", "inr", "₹"
        ]
        
        let hasTransactionKeyword = transactionKeywords.contains { keyword in
            content.contains(keyword)
        }
        
        // Must have amount pattern to be a real transaction
        let amountPattern = try! NSRegularExpression(pattern: "(?:inr|rs\\.?|₹)\\s*[0-9,]+(?:\\.[0-9]{1,2})?", options: .caseInsensitive)
        let hasAmount = amountPattern.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)) != nil
        
        // For non-bank emails, require both transaction keyword and amount
        if !hasTransactionKeyword || !hasAmount {
            return false
        }
        
        // Exclude obvious promotional emails
        let excludeKeywords = [
            "offer", "promotion", "discount", "sale", "cashback", "reward",
            "newsletter", "welcome", "thank you", "regards", "best regards"
        ]
        
        let hasExcludeKeyword = excludeKeywords.contains { keyword in
            content.contains(keyword)
        }
        
        return !hasExcludeKeyword
    }
    
    /// Enhanced bank-specific parsing for better accuracy
    static func parseAxisBankTransaction(subject: String, body: String) -> ParsedEmailTransaction? {
        let full = subject + "\n" + body
        
        // Axis Bank specific patterns
        let axisPatterns = [
            // Subject styles like: "INR 65.00 was debited from your A/c no. XX5739."
            "(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)\\s+was\\s+(debited|credited)\\b",
            // Fallback without word-boundary (some subjects end with a dot/extra token)
            "(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)\\s+was\\s+(debited|credited)",
            // Credit transaction alert pattern: "Credit transaction alert for Axis Bank A/c"
            "(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)\\s+(?:has been\\s+)?(credited|deposited)\\s+(?:to|in)\\s+(?:your\\s+)?(?:Axis\\s+Bank\\s+)?A/c",
            "Credit\\s+transaction\\s+alert.*?(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)\\s+(?:has been\\s+)?(credited|deposited)",
            // Salary credit patterns
            "(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)\\s+(?:has been\\s+)?(credited|deposited).*?salary",
            "salary.*?(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)\\s+(?:has been\\s+)?(credited|deposited)",
            "Dear Customer, INR ([0-9,]+(?:\\.[0-9]{2})?) has been (debited|credited)",
            "transaction of INR ([0-9,]+(?:\\.[0-9]{2})?) (debited|credited)",
            "Amount: INR ([0-9,]+(?:\\.[0-9]{2})?) (Debited|Credited)"
        ]
        
        for pattern in axisPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: full, options: [], range: NSRange(location: 0, length: full.utf16.count)) {
                
                let amountStr = (full as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                let typeStr = (full as NSString).substring(with: match.range(at: 2))
                
                if let amount = Double(amountStr) {
                    let isCredit = typeStr.lowercased().contains("credit") || typeStr.lowercased().contains("deposit")
                    
                    // Try to extract date using Axis method, then generic fallback
                    let date = extractAxisDate(from: full) ?? extractGenericINDate(from: full) ?? Date()
                    
                    // Enhanced category detection for Axis Bank
                    let fullText = (subject + "\n" + body).lowercased()
                    let suggestedCategory: String
                    if isCredit {
                        if fullText.contains("salary") || fullText.contains("payroll") || fullText.contains("sal cr") {
                            suggestedCategory = TransactionCategory.salary.rawValue
                        } else if fullText.contains("interest") {
                            suggestedCategory = TransactionCategory.interest.rawValue
                        } else {
                            suggestedCategory = TransactionCategory.other.rawValue
                        }
                    } else {
                        suggestedCategory = TransactionCategory.other.rawValue
                    }
                    
                    return ParsedEmailTransaction(
                        subject: subject,
                        body: body,
                        amount: amount,
                        date: date,
                        isCredit: isCredit,
                        description: extractTransactionInfo(from: full),
                        suggestedCategory: suggestedCategory
                    )
                }
            }
        }
        
        return nil
    }
    
    /// Enhanced ICICI bank parsing
    static func parseICICIBankTransaction(subject: String, body: String) -> ParsedEmailTransaction? {
        let full = subject + "\n" + body
        
        // ICICI Bank specific patterns
        let iciciPatterns = [
            "Rs\\.([0-9,]+(?:\\.[0-9]{2})?) (debited|credited)",
            "INR ([0-9,]+(?:\\.[0-9]{2})?) has been (debited|credited)",
            "Amount: Rs\\.([0-9,]+(?:\\.[0-9]{2})?) (Debited|Credited)"
        ]
        
        for pattern in iciciPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: full, options: [], range: NSRange(location: 0, length: full.utf16.count)) {
                
                let amountStr = (full as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                let typeStr = (full as NSString).substring(with: match.range(at: 2))
                
                if let amount = Double(amountStr) {
                    let isCredit = typeStr.lowercased().contains("credit")
                    
                    // Try to extract date using existing method
                    let date = extractICICIGmailDate(from: full) ?? Date()
                    
                    // Enhanced category detection for ICICI Bank
                    let fullText = (subject + "\n" + body).lowercased()
                    let suggestedCategory: String
                    if isCredit {
                        if fullText.contains("salary") || fullText.contains("payroll") {
                            suggestedCategory = TransactionCategory.salary.rawValue
                        } else if fullText.contains("interest") {
                            suggestedCategory = TransactionCategory.interest.rawValue
                        } else {
                            suggestedCategory = TransactionCategory.other.rawValue
                        }
                    } else {
                        suggestedCategory = TransactionCategory.other.rawValue
                    }
                    
                    return ParsedEmailTransaction(
                        subject: subject,
                        body: body,
                        amount: amount,
                        date: date,
                        isCredit: isCredit,
                        description: extractICICIInfo(from: full) ?? extractTransactionInfo(from: full),
                        suggestedCategory: suggestedCategory
                    )
                }
            }
        }
        
        return nil
    }
}


