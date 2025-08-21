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
    static func parse(subject: String?, body: String?) throws -> ParsedEmailTransaction {
        let subj = subject ?? ""
        let bodyText = (body ?? "")
        let plainBody = htmlToPlainText(bodyText)
        let full = (subj + "\n" + plainBody)

        // Determine credit/debit
        let isCredit = full.range(of: "credited", options: .caseInsensitive) != nil ||
                       full.range(of: "amount credited", options: .caseInsensitive) != nil
        let isDeb = full.range(of: "debited", options: .caseInsensitive) != nil ||
                    full.range(of: "amount debited", options: .caseInsensitive) != nil
        let creditFlag = isCredit && !isDeb

        // Amount (INR/Rs/₹)
        let amountRegex = try! NSRegularExpression(pattern: "(?:INR|Rs\\.?|₹)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)", options: [])
        guard let aMatch = amountRegex.firstMatch(in: full, options: [], range: NSRange(location: 0, length: full.utf16.count)) else {
            throw EmailParseError.amountMissing
        }
        let amountStr = (full as NSString).substring(with: aMatch.range(at: 1)).replacingOccurrences(of: ",", with: "")
        let amount = Double(amountStr) ?? 0

        // Date: try Axis style "Date & Time:" first, then generic
        var parsedDate: Date? = extractAxisDate(from: full)
        // Date: dd-MM-yy or dd-MM-yyyy (optionally with time)
        let dateRegexes = [
            "(\\b[0-3]?[0-9]-[0-1]?[0-9]-[0-9]{2,4}),?\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])?\\s*(?:IST|GMT|UTC)?",
            "(\\b[0-3]?[0-9]/[0-1]?[0-9]/[0-9]{2,4}),?\\s*([0-2][0-9]:[0-5][0-9]:[0-5][0-9])?\\s*(?:IST|GMT|UTC)?"
        ]
        outer: for pattern in dateRegexes {
            let re = try! NSRegularExpression(pattern: pattern)
            if let m = re.firstMatch(in: full, options: [], range: NSRange(location: 0, length: full.utf16.count)) {
                let dStr = (full as NSString).substring(with: m.range(at: 1))
                let tStr = m.range(at: 2).location != NSNotFound ? (full as NSString).substring(with: m.range(at: 2)) : nil
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
                for f in fmts {
                    df.dateFormat = f
                    if let dt = df.date(from: [dStr, tStr].compactMap{$0}.joined(separator: " ")) { parsedDate = dt; break outer }
                }
            }
        }
        guard let date = parsedDate else { throw EmailParseError.dateMissing }

        // Description
        var desc = extractTransactionInfo(from: full)
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
            for f in fmts {
                df.dateFormat = f
                if let dt = df.date(from: cleaned) { return dt }
            }
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
}


