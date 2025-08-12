//
//  CDTransaction+CoreDataProperties.swift
//  Expense
//
//  Created by Ashok Naidu on 24/12/24.
//
//

import Foundation
import CoreData


extension CDTransaction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTransaction> {
        return NSFetchRequest<CDTransaction>(entityName: "Transaction")
    }

    @NSManaged public var amount: Double
    @NSManaged public var category: String?
    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isCredit: Bool
    @NSManaged public var notes: String?
    @NSManaged public var userId: String?
    @NSManaged public var account: CDAccount?

}

extension CDTransaction : Identifiable {

    var wrappedUserId: String {
        userId ?? ""
    }
    
    var wrappedCategory: String {
        category ?? "Other"
    }
    
    var wrappedDate: Date {
        date ?? Date()
    }
    
    var wrappedNotes: String {
        notes ?? ""
    }
    
    var wrappedAccount: CDAccount {
        account ?? CDAccount()
    }

}
