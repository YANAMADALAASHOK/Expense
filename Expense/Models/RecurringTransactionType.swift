import Foundation

// MARK: - Recurring Transaction Type
enum RecurringTransactionType: String, CaseIterable, Codable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"
    
    var displayName: String {
        return rawValue
    }
} 