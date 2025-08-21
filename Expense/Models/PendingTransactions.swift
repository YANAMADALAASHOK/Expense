import Foundation

struct PendingTransactionItem: Codable, Identifiable, Equatable {
    let id: UUID
    var subject: String
    var body: String
    var amount: Double
    var date: Date
    var isCredit: Bool
    var suggestedCategory: String
    var notes: String?

    init(id: UUID = UUID(), subject: String, body: String, amount: Double, date: Date, isCredit: Bool, suggestedCategory: String, notes: String? = nil) {
        self.id = id
        self.subject = subject
        self.body = body
        self.amount = amount
        self.date = date
        self.isCredit = isCredit
        self.suggestedCategory = suggestedCategory
        self.notes = notes
    }
}


