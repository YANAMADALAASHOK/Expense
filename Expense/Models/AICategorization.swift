import Foundation
import NaturalLanguage

// MARK: - AI Categorization System
class AICategorizationManager: ObservableObject {
    static let shared = AICategorizationManager()
    private let userRulesKey = "UserCategorizationRules"
    
    // Training data for categorization
    private let categoryKeywords: [String: [String]] = [
        "Food": ["restaurant", "cafe", "coffee", "food", "meal", "lunch", "dinner", "breakfast", "pizza", "burger", "mcdonalds", "starbucks", "uber eats", "doordash", "grubhub", "delivery", "takeout", "grocery", "supermarket", "walmart", "target", "kroger", "safeway", "whole foods", "trader joes"],
        "Transportation": ["uber", "lyft", "taxi", "gas", "fuel", "parking", "metro", "subway", "bus", "train", "airline", "flight", "car", "auto", "maintenance", "repair", "insurance", "dmv", "registration"],
        "Shopping": ["amazon", "ebay", "walmart", "target", "best buy", "apple", "nike", "adidas", "clothing", "shoes", "electronics", "phone", "laptop", "computer", "accessories", "jewelry", "watch", "bag", "purse"],
        "Entertainment": ["netflix", "spotify", "hulu", "disney", "youtube", "movie", "theater", "concert", "show", "game", "playstation", "xbox", "nintendo", "ticket", "event", "party", "bar", "club", "casino"],
        "Utilities": ["electricity", "gas", "water", "internet", "phone", "cable", "tv", "wifi", "utility", "bill", "service", "provider", "at&t", "verizon", "comcast", "spectrum"],
        "Healthcare": ["doctor", "hospital", "pharmacy", "medicine", "prescription", "dental", "vision", "insurance", "medical", "health", "clinic", "urgent care", "emergency", "cvs", "walgreens", "rite aid"],
        "Education": ["school", "college", "university", "tuition", "books", "textbook", "course", "class", "training", "workshop", "seminar", "education", "student", "loan", "scholarship"],
        "Rent": ["rent", "lease", "apartment", "house", "property", "landlord", "tenant", "housing", "accommodation"],
        // Keep salary terms specific; avoid generic matches like "payment", "deposit", "job", "work" which caused false positives
        "Salary": ["salary", "wage", "income", "paycheck", "payroll", "direct deposit"],
        "Investment": ["investment", "stock", "bond", "mutual fund", "etf", "portfolio", "trading", "broker", "fidelity", "vanguard", "schwab", "robinhood", "dividend", "interest", "capital gains"],
        "Interest": ["interest", "dividend", "yield", "return", "investment income", "savings interest"],
        "EMI Payment": ["emi", "loan", "payment", "installment", "mortgage", "car loan", "personal loan", "credit"],
        "Credit Card Payment": ["credit card", "payment", "bill", "statement", "balance", "minimum payment", "due"],
        "Other": ["other", "misc", "miscellaneous", "unknown", "unclassified"]
    ]
    
    // Amount-based categorization rules
    private let amountRules: [(range: ClosedRange<Double>, category: String)] = [
        (0...50, "Food"),
        (50...200, "Shopping"),
        (200...1000, "Entertainment"),
        (1000...5000, "Investment"),
        (5000...Double.infinity, "Other")
    ]
    
    // User-learned rules (persisted)
    private(set) var userRules: [UserRule] = []
    
    private init() {
        loadUserRules()
    }
    
    // MARK: - Main Categorization Method
    func categorizeTransaction(title: String, amount: Double, isCredit: Bool? = nil, notes: String? = nil) -> String {
        let text = "\(title) \(notes ?? "")".lowercased()
        
        // First, check user-learned rules (all keywords must match)
        if let matched = userRules.first(where: { rule in
            // Scope filter
            if let isCredit = isCredit {
                switch rule.scope {
                case .all: break
                case .creditOnly: if !isCredit { return false }
                case .debitOnly: if isCredit { return false }
                }
            }
            let tokens = rule.pattern
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return tokens.allSatisfy { text.contains($0) }
        }) {
            return matched.category
        }
        
        // Then, try keyword-based categorization
        if let category = categorizeByKeywords(text) {
            return category
        }
        
        // If no keyword match, try amount-based categorization
        return categorizeByAmount(amount)
    }

    // Returns the first user rule that matches (all tokens must be present), else nil
    func findMatchingRule(in text: String, isCredit: Bool) -> UserRule? {
        let lowered = text.lowercased()
        return userRules.first(where: { rule in
            switch rule.scope {
            case .all: break
            case .creditOnly: if !isCredit { return false }
            case .debitOnly: if isCredit { return false }
            }
            let tokens = rule.pattern
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return tokens.allSatisfy { lowered.contains($0) }
        })
    }

    // Backwards-compatible helper
    func matchUserRule(in text: String, isCredit: Bool) -> String? {
        findMatchingRule(in: text, isCredit: isCredit)?.category
    }

    // MARK: - User Rules Management
    func addOrUpdateRule(pattern: String, category: String, scope: RuleScope = .all, excludeFromDashboard: Bool = false) {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let idx = userRules.firstIndex(where: { $0.pattern.caseInsensitiveCompare(pattern) == .orderedSame }) {
            userRules[idx] = UserRule(pattern: pattern, category: category, scope: scope, excludeFromDashboard: excludeFromDashboard)
        } else {
            userRules.append(UserRule(pattern: pattern, category: category, scope: scope, excludeFromDashboard: excludeFromDashboard))
        }
        saveUserRules()
    }
    
    private func loadUserRules() {
        if let data = UserDefaults.standard.data(forKey: userRulesKey),
           let rules = try? JSONDecoder().decode([UserRule].self, from: data) {
            self.userRules = rules
        }
    }
    
    private func saveUserRules() {
        if let data = try? JSONEncoder().encode(userRules) {
            UserDefaults.standard.set(data, forKey: userRulesKey)
        }
    }

    // Expose rules for UI
    func getUserRules() -> [UserRule] { userRules }
    func replaceUserRules(_ rules: [UserRule]) {
        userRules = rules
        saveUserRules()
    }
    func updateRule(at index: Int, to rule: UserRule) {
        guard userRules.indices.contains(index) else { return }
        userRules[index] = rule
        saveUserRules()
    }
    func removeRule(at index: Int) {
        guard userRules.indices.contains(index) else { return }
        userRules.remove(at: index)
        saveUserRules()
    }
    func removeRule(matching pattern: String) {
        if let idx = userRules.firstIndex(where: { $0.pattern.caseInsensitiveCompare(pattern) == .orderedSame }) {
            removeRule(at: idx)
        }
    }
    
    // MARK: - Keyword-based Categorization
    private func categorizeByKeywords(_ text: String) -> String? {
        var categoryScores: [String: Int] = [:]
        
        for (category, keywords) in categoryKeywords {
            var score = 0
            for keyword in keywords {
                if text.contains(keyword.lowercased()) {
                    score += 1
                }
            }
            if score > 0 {
                categoryScores[category] = score
            }
        }
        
        // Return the category with the highest score
        return categoryScores.max(by: { $0.value < $1.value })?.key
    }
    
    // MARK: - Amount-based Categorization
    private func categorizeByAmount(_ amount: Double) -> String {
        for rule in amountRules {
            if rule.range.contains(amount) {
                return rule.category
            }
        }
        return "Other"
    }
    
    // MARK: - Machine Learning Enhancement
    func trainWithUserData(transactions: [CDTransaction]) {
        // This would implement actual ML training
        // For now, we'll use a simple frequency-based approach
        
        var userCategoryKeywords: [String: [String]] = [:]
        
        for transaction in transactions {
            guard let category = transaction.category else { continue }
            let text = "\(category) \(transaction.notes ?? "")".lowercased()
            
            // Extract words from the transaction text
            let words = text.components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 2 } // Filter out short words
            
            if userCategoryKeywords[category] == nil {
                userCategoryKeywords[category] = []
            }
            
            userCategoryKeywords[category]?.append(contentsOf: words)
        }
        
        // Note: We can't modify categoryKeywords as it's a let constant
        // In a real implementation, you would store user-specific keywords separately
        // For now, we'll just use the existing static keywords
    }
    
    // MARK: - Confidence Scoring
    func getCategorizationConfidence(title: String, amount: Double, notes: String? = nil) -> Double {
        let text = "\(title) \(notes ?? "")".lowercased()
        
        // Calculate confidence based on keyword matches
        var maxScore = 0
        var totalKeywords = 0
        
        for (_, keywords) in categoryKeywords {
            totalKeywords += keywords.count
            var score = 0
            for keyword in keywords {
                if text.contains(keyword.lowercased()) {
                    score += 1
                }
            }
            maxScore = max(maxScore, score)
        }
        
        // Normalize confidence to 0-1 range
        return Double(maxScore) / Double(totalKeywords)
    }
    
    // MARK: - Suggest Categories
    func suggestCategories(for text: String, amount: Double) -> [String] {
        let categorized = categorizeTransaction(title: text, amount: amount)
        let confidence = getCategorizationConfidence(title: text, amount: amount)
        
        var suggestions = [categorized]
        
        // Add alternative suggestions based on amount
        if confidence < 0.3 {
            suggestions.append(categorizeByAmount(amount))
        }
        
        // Add common categories
        suggestions.append(contentsOf: ["Food", "Transportation", "Shopping", "Other"])
        
        // Remove duplicates and return unique suggestions
        return Array(Set(suggestions))
    }
}

// MARK: - Natural Language Processing Enhancement
extension AICategorizationManager {
    func analyzeTransactionText(_ text: String) -> [String: Double] {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        
        var entities: [String: Double] = [:]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let _ = tag {
                let word = String(text[tokenRange]).lowercased()
                entities[word] = 1.0
            }
            return true
        }
        
        return entities
    }
}

// MARK: - Transaction Categorization Extension
extension CDTransaction {
    func autoCategorize() {
        let aiManager = AICategorizationManager.shared
        let suggestedCategory = aiManager.categorizeTransaction(
            title: self.notes ?? self.category ?? "",
            amount: self.amount,
            isCredit: self.isCredit,
            notes: self.notes
        )
        
        self.category = suggestedCategory
    }
    
    func getCategorizationConfidence() -> Double {
        let aiManager = AICategorizationManager.shared
        return aiManager.getCategorizationConfidence(
            title: self.category ?? "",
            amount: self.amount,
            notes: self.notes
        )
    }
} 

// MARK: - UserRule Model
struct UserRule: Codable, Equatable {
    var pattern: String
    var category: String
    var scope: RuleScope = .all
    var excludeFromDashboard: Bool = false
}

// removed let-only helper; using var fields so exclude/scope can be stored directly

enum RuleScope: String, Codable, CaseIterable {
    case all
    case creditOnly
    case debitOnly
}