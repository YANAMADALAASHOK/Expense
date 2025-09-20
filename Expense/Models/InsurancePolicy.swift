import Foundation

struct InsurancePolicy: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var premiumAmount: Double
    var dayOfMonth: Int // 1...31
    var accountId: UUID
    var notes: String?
    var lastPaidAt: Date?
    var isActive: Bool

    init(id: UUID = UUID(), name: String, premiumAmount: Double, dayOfMonth: Int, accountId: UUID, notes: String? = nil, lastPaidAt: Date? = nil, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.premiumAmount = premiumAmount
        self.dayOfMonth = dayOfMonth
        self.accountId = accountId
        self.notes = notes
        self.lastPaidAt = lastPaidAt
        self.isActive = isActive
    }
}
