import Foundation

enum TransactionCategory: Hashable {
    case food
    case transportation
    case shopping
    case entertainment
    case utilities
    case healthcare
    case education
    case rent
    case salary
    case investment
    case interest
    case emiPayment
    case creditCardPayment
    case other
    case custom(String)
    
    var displayName: String {
        switch self {
        case .food: return "Food"
        case .transportation: return "Transportation"
        case .shopping: return "Shopping"
        case .entertainment: return "Entertainment"
        case .utilities: return "Utilities"
        case .healthcare: return "Healthcare"
        case .education: return "Education"
        case .rent: return "Rent"
        case .salary: return "Salary"
        case .investment: return "Investment"
        case .interest: return "Interest"
        case .emiPayment: return "EMI Payment"
        case .creditCardPayment: return "Credit Card Payment"
        case .other: return "Other"
        case .custom(let name): return name
        }
    }
    
    var rawValue: String {
        switch self {
        case .food: return "Food"
        case .transportation: return "Transportation"
        case .shopping: return "Shopping"
        case .entertainment: return "Entertainment"
        case .utilities: return "Utilities"
        case .healthcare: return "Healthcare"
        case .education: return "Education"
        case .rent: return "Rent"
        case .salary: return "Salary"
        case .investment: return "Investment"
        case .interest: return "Interest"
        case .emiPayment: return "EMI Payment"
        case .creditCardPayment: return "Credit Card Payment"
        case .other: return "Other"
        case .custom(let name): return name
        }
    }
    
    static var allCases: [TransactionCategory] {
        [.food, .transportation, .shopping, .entertainment, .utilities, .healthcare, .education, .rent, .salary, .investment, .interest, .emiPayment, .creditCardPayment, .other]
    }
    
    init(rawValue: String) {
        switch rawValue {
        case "Food": self = .food
        case "Transportation": self = .transportation
        case "Shopping": self = .shopping
        case "Entertainment": self = .entertainment
        case "Utilities": self = .utilities
        case "Healthcare": self = .healthcare
        case "Education": self = .education
        case "Rent": self = .rent
        case "Salary": self = .salary
        case "Investment": self = .investment
        case "Interest": self = .interest
        case "EMI Payment": self = .emiPayment
        case "Credit Card Payment": self = .creditCardPayment
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
    case personalLoanGiven = "Personal Loan (Given)"
    
    // Liabilities
    case creditCard = "Credit Card"
    case loan = "Loan"
    case mortgage = "Mortgage"
    
    var isAsset: Bool {
        switch self {
        case .bankAccount, .cash, .investment, .mutualFund, .savings, .personalLoanGiven:
            return true
        case .creditCard, .loan, .mortgage:
            return false
        }
    }
    
    var isMutualFund: Bool {
        self == .mutualFund
    }
} 