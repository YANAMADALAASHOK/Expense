//
//  CDAccount+CoreDataProperties.swift
//  Expense
//
//  Created by Ashok Naidu on 24/12/24.
//
//

import Foundation
import CoreData


extension CDAccount {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDAccount> {
        return NSFetchRequest<CDAccount>(entityName: "Account")
    }

    @NSManaged public var accountName: String?
    @NSManaged public var accountType: String?
    @NSManaged public var balance: Double
    @NSManaged public var creditLimit: Double
    @NSManaged public var id: UUID?
    @NSManaged public var metadata: [String:String]?
    @NSManaged public var userId: String?
    @NSManaged public var transactions: NSSet?

    var wrappedUserId: String {
        userId ?? ""
    }
    
    var wrappedAccountName: String {
        accountName ?? ""
    }
    
    var wrappedAccountType: String {
        accountType ?? ""
    }
    
    var wrappedTransactions: [CDTransaction] {
        let set = transactions as? Set<CDTransaction> ?? []
        return set.sorted { $0.wrappedDate > $1.wrappedDate }
    }

}

// MARK: Generated accessors for transactions
extension CDAccount {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: CDTransaction)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: CDTransaction)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}
