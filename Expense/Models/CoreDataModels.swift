import Foundation
import CoreData

@objc(CDAccount)
public class CDAccount: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var accountName: String?
    @NSManaged public var accountType: String?
    @NSManaged public var balance: Double
    @NSManaged public var creditLimit: Double
    @NSManaged public var transactions: Set<CDTransaction>?
    @NSManaged public var metadata: [String: String]?
}

// MARK: - Account Extensions
extension CDAccount {
    var wrappedAccountName: String {
        accountName ?? "Unknown Account"
    }
    
    var wrappedAccountType: AccountType {
        AccountType(rawValue: accountType ?? "") ?? .bankAccount
    }
    
    var transactionsArray: [CDTransaction] {
        let set = transactions ?? []
        return set.sorted { $0.date ?? Date() > $1.date ?? Date() }
    }
    
    // Generated accessors for transactions
    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: CDTransaction)
    
    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: CDTransaction)
    
    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)
    
    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)
}

@objc(CDTransaction)
public class CDTransaction: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID?
    @NSManaged public var amount: Double
    @NSManaged public var category: String?
    @NSManaged public var date: Date?
    @NSManaged public var isCredit: Bool
    @NSManaged public var notes: String?
    @NSManaged public var account: CDAccount?
}

// MARK: - Transaction Extensions
extension CDTransaction {
    var wrappedCategory: String {
        category ?? "Uncategorized"
    }
    
    var wrappedDate: Date {
        date ?? Date()
    }
    
    var wrappedNotes: String {
        notes ?? ""
    }
} 