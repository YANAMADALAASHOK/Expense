import Foundation
import CoreData

class InsuranceManager {
    static let shared = InsuranceManager()
    private init() {}
    
    private let policiesKey = "InsurancePoliciesStore"
    
    func loadPolicies() -> [InsurancePolicy] {
        if let data = UserDefaults.standard.data(forKey: policiesKey),
           let policies = try? JSONDecoder().decode([InsurancePolicy].self, from: data) {
            return policies
        }
        return []
    }
    
    func savePolicies(_ policies: [InsurancePolicy]) {
        if let data = try? JSONEncoder().encode(policies) {
            UserDefaults.standard.set(data, forKey: policiesKey)
        }
    }
    
    func processInsurancePremiums(context: NSManagedObjectContext, accounts: [CDAccount]) {
        let policies = loadPolicies()
        let calendar = Calendar.current
        let today = Date()
        let todayDay = calendar.component(.day, from: today)
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        
        for policy in policies where policy.isActive {
            // Check if premium is due today
            if policy.dayOfMonth == todayDay {
                // Check if we already processed this month
                let lastProcessedKey = "insurance_\(policy.id)_lastProcessed"
                let lastProcessed = UserDefaults.standard.object(forKey: lastProcessedKey) as? Date
                
                var shouldProcess = true
                if let lastProcessed = lastProcessed {
                    let lastMonth = calendar.component(.month, from: lastProcessed)
                    let lastYear = calendar.component(.year, from: lastProcessed)
                    
                    // Don't process if already done this month
                    if lastMonth == currentMonth && lastYear == currentYear {
                        shouldProcess = false
                    }
                }
                
                if shouldProcess {
                    createPremiumTransaction(for: policy, context: context, accounts: accounts)
                    UserDefaults.standard.set(today, forKey: lastProcessedKey)
                }
            }
        }
    }
    
    private func createPremiumTransaction(for policy: InsurancePolicy, context: NSManagedObjectContext, accounts: [CDAccount]) {
        // Find the account to debit
        guard let account = accounts.first(where: { $0.id == policy.accountId }) else {
            print("Account not found for policy: \(policy.name)")
            return
        }
        
        // Create the transaction
        let transaction = CDTransaction(context: context)
        transaction.id = UUID()
        transaction.amount = policy.premiumAmount
        transaction.category = TransactionCategory.utilities.rawValue
        transaction.isCredit = false // Debit
        transaction.account = account
        transaction.notes = "Insurance Premium: \(policy.name)"
        transaction.date = Date()
        
        // Update account balance based on account type
        if account.accountType == AccountType.creditCard.rawValue {
            // For credit cards: debit increases the balance (more debt)
            account.balance += policy.premiumAmount
        } else {
            // For all other accounts: debit decreases the balance
            account.balance -= policy.premiumAmount
        }
        
        // Save the context
        do {
            try context.save()
            print("✅ Created premium transaction for \(policy.name): ₹\(policy.premiumAmount)")
            print("✅ Updated account balance: \(account.wrappedAccountName) = ₹\(account.balance)")
        } catch {
            print("❌ Failed to save premium transaction: \(error)")
        }
    }
}
