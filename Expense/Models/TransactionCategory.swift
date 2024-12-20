import Foundation

enum TransactionCategory: Hashable {
    case food
    case transport
    case utilities
    case entertainment
    case shopping
    case health
    case education
    case other
    case custom(String)
    
    var rawValue: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Transport"
        case .utilities: return "Utilities"
        case .entertainment: return "Entertainment"
        case .shopping: return "Shopping"
        case .health: return "Health"
        case .education: return "Education"
        case .other: return "Other"
        case .custom(let name): return name
        }
    }
    
    var displayName: String {
        return rawValue
    }
    
    static var allCases: [TransactionCategory] {
        [.food, .transport, .utilities, .entertainment, .shopping, .health, .education, .other]
    }
    
    init(rawValue: String) {
        switch rawValue {
        case "Food": self = .food
        case "Transport": self = .transport
        case "Utilities": self = .utilities
        case "Entertainment": self = .entertainment
        case "Shopping": self = .shopping
        case "Health": self = .health
        case "Education": self = .education
        case "Other": self = .other
        default: self = .custom(rawValue)
        }
    }
}

enum AccountType: String, CaseIterable {
    // Assets
    case bankAccount = "Bank Account"
    case cash = "Cash"
    case investment = "Investment"
    case mutualFund = "Mutual Fund"
    case savings = "Savings"
    
    // Liabilities
    case creditCard = "Credit Card"
    case loan = "Loan"
    case mortgage = "Mortgage"
    
    var isAsset: Bool {
        switch self {
        case .bankAccount, .cash, .investment, .mutualFund, .savings:
            return true
        case .creditCard, .loan, .mortgage:
            return false
        }
    }
    
    var isMutualFund: Bool {
        self == .mutualFund
    }
} 