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
    @NSManaged public var metadata: Data?
    
    // Ensure ID is always available for Identifiable conformance
    public var identifier: UUID {
        id ?? UUID()
    }
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
    
    var metadataDictionary: [String: String] {
        get {
            guard let data = metadata else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
        }
        set {
            metadata = try? JSONSerialization.data(withJSONObject: newValue)
        }
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
    
    // Ensure ID is always available for Identifiable conformance
    public var identifier: UUID {
        id ?? UUID()
    }
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