import Foundation
import CoreData

// MARK: - Recurring Transaction Model
struct RecurringTransaction: Identifiable, Codable {
    let id: UUID
    var title: String // This will be stored in the category field
    var amount: Double
    var category: String
    var accountId: String
    var frequency: RecurrenceFrequency
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    var lastProcessedDate: Date?
    var nextDueDate: Date
    var notes: String?
    var type: RecurringTransactionType
    
    init(title: String, amount: Double, category: String, accountId: String, frequency: RecurrenceFrequency, startDate: Date, endDate: Date? = nil, notes: String? = nil, type: RecurringTransactionType = .expense) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.category = category
        self.accountId = accountId
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = true
        self.lastProcessedDate = nil
        self.nextDueDate = startDate
        self.notes = notes
        self.type = type
    }
    
    mutating func updateNextDueDate() {
        guard let nextDate = frequency.nextDate(from: nextDueDate) else { return }
        nextDueDate = nextDate
        lastProcessedDate = Date()
    }
    
    func shouldProcessToday() -> Bool {
        guard isActive else { return false }
        
        let today = Date()
        
        // Check if we've reached the end date
        if let endDate = endDate, today > endDate {
            return false
        }
        
        // Check if it's time to process
        return today >= nextDueDate
    }
}

// MARK: - Recurrence Frequency
enum RecurrenceFrequency: String, CaseIterable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Bi-weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
    case custom = "Custom"
    
    func nextDate(from date: Date) -> Date? {
        let calendar = Calendar.current
        
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        case .custom:
            return nil // Custom logic needed
        }
    }
    
    var displayName: String {
        return rawValue
    }
}



// MARK: - Core Data Extension for Recurring Transactions
extension CDTransaction {
    static func createFromRecurring(_ recurring: RecurringTransaction, context: NSManagedObjectContext) -> CDTransaction {
        let transaction = CDTransaction(context: context)
        transaction.id = UUID()
        transaction.amount = recurring.amount
        transaction.category = recurring.title // Store title in category field
        transaction.date = Date()
        
        // Combine category and notes
        var notes = recurring.category
        if let recurringNotes = recurring.notes, !recurringNotes.isEmpty {
            notes += " - " + recurringNotes
        }
        transaction.notes = notes
        
        transaction.isCredit = (recurring.type == .income)
        
        // Find and set the account
        if let account = findAccount(withId: recurring.accountId, context: context) {
            transaction.account = account
        }
        
        return transaction
    }
    
    private static func findAccount(withId accountId: String, context: NSManagedObjectContext) -> CDAccount? {
        let request = NSFetchRequest<CDAccount>(entityName: "CDAccount")
        request.predicate = NSPredicate(format: "id == %@", accountId)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Error fetching account: \(error)")
            return nil
        }
    }
}

// MARK: - Recurring Transaction Manager
class RecurringTransactionManager: ObservableObject {
    @Published var recurringTransactions: [RecurringTransaction] = []
    private let userDefaults = UserDefaults.standard
    private let recurringTransactionsKey = "RecurringTransactions"
    
    init() {
        loadRecurringTransactions()
    }
    
    func addRecurringTransaction(_ transaction: RecurringTransaction) {
        recurringTransactions.append(transaction)
        saveRecurringTransactions()
    }
    
    func updateRecurringTransaction(_ transaction: RecurringTransaction) {
        if let index = recurringTransactions.firstIndex(where: { $0.id == transaction.id }) {
            recurringTransactions[index] = transaction
            saveRecurringTransactions()
        }
    }
    
    func deleteRecurringTransaction(_ transaction: RecurringTransaction) {
        recurringTransactions.removeAll { $0.id == transaction.id }
        saveRecurringTransactions()
    }
    
    func processRecurringTransactions(context: NSManagedObjectContext) {
        let _ = Date()  // today was never used
        
        for i in 0..<recurringTransactions.count {
            var transaction = recurringTransactions[i]
            
            if transaction.shouldProcessToday() {
                // Create the transaction
                let _ = CDTransaction.createFromRecurring(transaction, context: context)  // newTransaction was never used
                
                // Update the recurring transaction
                transaction.updateNextDueDate()
                recurringTransactions[i] = transaction
                
                // Save context
                do {
                    try context.save()
                } catch {
                    print("Error saving recurring transaction: \(error)")
                }
            }
        }
        
        saveRecurringTransactions()
    }
    
    private func loadRecurringTransactions() {
        if let data = userDefaults.data(forKey: recurringTransactionsKey),
           let transactions = try? JSONDecoder().decode([RecurringTransaction].self, from: data) {
            recurringTransactions = transactions
        }
    }
    
    private func saveRecurringTransactions() {
        if let data = try? JSONEncoder().encode(recurringTransactions) {
            userDefaults.set(data, forKey: recurringTransactionsKey)
        }
    }
} 