import Foundation
import CoreData

// MARK: - Credit Card Bill Model
struct CreditCardBill: Identifiable, Codable {
    let id: UUID
    let cardAccountId: UUID
    let statementDate: Date
    let dueDate: Date
    let totalAmount: Double
    let minimumDue: Double
    let availableLimit: Double
    let creditLimit: Double
    let currentUsage: Double
    var isPaid: Bool
    var balanceAdjusted: Bool  // Track if balance was already adjusted for this payment
    let pdfFileName: String?
    let transactions: [BillTransaction]
    
    init(
        id: UUID = UUID(),
        cardAccountId: UUID,
        statementDate: Date,
        dueDate: Date,
        totalAmount: Double,
        minimumDue: Double,
        availableLimit: Double,
        creditLimit: Double,
        currentUsage: Double,
        isPaid: Bool = false,
        balanceAdjusted: Bool = false,
        pdfFileName: String? = nil,
        transactions: [BillTransaction] = []
    ) {
        self.id = id
        self.cardAccountId = cardAccountId
        self.statementDate = statementDate
        self.dueDate = dueDate
        self.totalAmount = totalAmount
        self.minimumDue = minimumDue
        self.availableLimit = availableLimit
        self.creditLimit = creditLimit
        self.currentUsage = currentUsage
        self.isPaid = isPaid
        self.balanceAdjusted = balanceAdjusted
        self.pdfFileName = pdfFileName
        self.transactions = transactions
    }
}

// MARK: - Bill Transaction Model
struct BillTransaction: Identifiable, Codable {
    let id: UUID
    let date: Date
    let description: String
    let amount: Double
    let category: String
    
    init(
        id: UUID = UUID(),
        date: Date,
        description: String,
        amount: Double,
        category: String
    ) {
        self.id = id
        self.date = date
        self.description = description
        self.amount = amount
        self.category = category
    }
}

// MARK: - Bill Storage Helper
class CreditCardBillStorage {
    static let shared = CreditCardBillStorage()
    private init() {}
    
    private let billsKey = "CreditCardBills"
    
    // Save bills for a specific card
    func saveBills(_ bills: [CreditCardBill], for cardId: UUID) {
        var allBills = loadAllBills()
        // Remove existing bills for this card
        allBills.removeAll { $0.cardAccountId == cardId }
        // Add new bills
        allBills.append(contentsOf: bills)
        
        if let encoded = try? JSONEncoder().encode(allBills) {
            UserDefaults.standard.set(encoded, forKey: billsKey)
        }
    }
    
    // Add a single bill (used during fetching)
    func addBill(_ bill: CreditCardBill) {
        var allBills = loadAllBills()
        
        // Check if bill already exists (prevent duplicates)
        if !allBills.contains(where: { $0.id == bill.id }) {
            allBills.append(bill)
            
            if let encoded = try? JSONEncoder().encode(allBills) {
                UserDefaults.standard.set(encoded, forKey: billsKey)
                print("DEBUG: ✅ Added bill to storage: \(bill.statementDate) - ₹\(bill.totalAmount)")
            }
        } else {
            print("DEBUG: ⚠️ Bill already exists, skipping: \(bill.statementDate)")
        }
    }
    
    func loadBills(for cardId: UUID) -> [CreditCardBill] {
        return loadAllBills().filter { $0.cardAccountId == cardId }
            .sorted { $0.statementDate < $1.statementDate } // Oldest first
    }
    
    // Load all bills from storage (with migration for balanceAdjusted)
    func loadAllBills() -> [CreditCardBill] {
        guard let data = UserDefaults.standard.data(forKey: billsKey),
              let bills = try? JSONDecoder().decode([CreditCardBill].self, from: data) else {
            return []
        }
        
        // Migration: Mark all paid bills as balance-adjusted to prevent re-processing
        var migratedBills = bills
        var needsMigration = false
        for (index, bill) in migratedBills.enumerated() {
            if bill.isPaid && !bill.balanceAdjusted {
                migratedBills[index].balanceAdjusted = true
                needsMigration = true
            }
        }
        
        // Save migrated data back
        if needsMigration {
            if let encoded = try? JSONEncoder().encode(migratedBills) {
                UserDefaults.standard.set(encoded, forKey: billsKey)
                print("DEBUG: Migrated \(migratedBills.filter { $0.isPaid && $0.balanceAdjusted }.count) paid bills to mark as balance-adjusted")
            }
        }
        
        return migratedBills
    }
    
    // Update a specific bill
    func updateBill(_ bill: CreditCardBill) {
        var allBills = loadAllBills()
        if let index = allBills.firstIndex(where: { $0.id == bill.id }) {
            allBills[index] = bill
            if let encoded = try? JSONEncoder().encode(allBills) {
                UserDefaults.standard.set(encoded, forKey: billsKey)
            }
        }
    }
    
    // Mark bill as paid and balance adjusted
    func markBillAsPaid(_ billId: UUID, balanceAdjusted: Bool = true) {
        var allBills = loadAllBills()
        if let index = allBills.firstIndex(where: { $0.id == billId }) {
            var bill = allBills[index]
            bill.isPaid = true
            bill.balanceAdjusted = balanceAdjusted
            allBills[index] = bill
            if let encoded = try? JSONEncoder().encode(allBills) {
                UserDefaults.standard.set(encoded, forKey: billsKey)
            }
        }
    }
    
    // Clean up orphaned bills (bills for deleted credit card accounts)
    func cleanupOrphanedBills(validAccountIds: Set<UUID>) {
        let allBills = loadAllBills()
        let validBills = allBills.filter { validAccountIds.contains($0.cardAccountId) }
        let orphanedCount = allBills.count - validBills.count
        
        if orphanedCount > 0 {
            if let encoded = try? JSONEncoder().encode(validBills) {
                UserDefaults.standard.set(encoded, forKey: billsKey)
                print("DEBUG: 🧹 Cleaned up \(orphanedCount) orphaned bills, kept \(validBills.count) valid bills")
            }
        }
    }
    
    // Clear all bills (for testing/debugging)
    func clearAllBills() {
        UserDefaults.standard.removeObject(forKey: billsKey)
        print("DEBUG: 🗑️ Cleared all bills from storage")
    }
    
    // Clear bills for a specific account and return the account ID for metadata reset
    func clearBillsForAccount(_ accountId: UUID) {
        var allBills = loadAllBills()
        let billsToRemove = allBills.filter { $0.cardAccountId == accountId }
        allBills.removeAll { $0.cardAccountId == accountId }
        
        if let encoded = try? JSONEncoder().encode(allBills) {
            UserDefaults.standard.set(encoded, forKey: billsKey)
            print("DEBUG: 🧹 Cleared \(billsToRemove.count) bills for account \(accountId)")
        }
    }
    
    // Auto-mark old bills as paid when new bill arrives
    func autoMarkOldBillsAsPaid(for cardId: UUID, exceptBillId: UUID) {
        var allBills = loadAllBills()
        var modified = false
        
        for index in allBills.indices {
            if allBills[index].cardAccountId == cardId &&
               allBills[index].id != exceptBillId &&
               !allBills[index].isPaid {
                allBills[index].isPaid = true
                modified = true
            }
        }
        
        if modified {
            if let encoded = try? JSONEncoder().encode(allBills) {
                UserDefaults.standard.set(encoded, forKey: billsKey)
            }
        }
    }
}
