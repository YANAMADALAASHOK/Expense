import Foundation
import CoreData

struct LoanDetails {
    let principalAmount: Double
    let interestRate: Double // Annual interest rate in percentage
    let loanDate: Date
    let lastInterestCalculationDate: Date
    let outstandingAmount: Double
    let notes: String?
    let emiAmount: Double?
    
    var monthlyInterestRate: Double {
        interestRate / 12.0 // Convert annual rate to monthly
    }
    
    var calculatedInterest: Double {
        let months = Calendar.current.dateComponents([.month], from: lastInterestCalculationDate, to: Date()).month ?? 0
        let days = Calendar.current.dateComponents([.day], from: lastInterestCalculationDate, to: Date()).day ?? 0
        
        // If it's been at least a month, calculate monthly interest
        if months > 0 || days >= 30 {
            return outstandingAmount * (monthlyInterestRate / 100.0)
        }
        return 0
    }
    
    var totalAmountWithInterest: Double {
        outstandingAmount + calculatedInterest
    }
    
    var nextInterestCalculationDate: Date {
        // Next interest calculation will be next month from the last calculation date
        Calendar.current.date(byAdding: .month, value: 1, to: lastInterestCalculationDate) ?? Date()
    }
    
    var daysUntilNextCalculation: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextInterestCalculationDate).day ?? 0
        return max(0, days)
    }
    
    var calculatedEMI: Double {
        guard monthlyInterestRate > 0 else { return 0 }
        
        // Calculate EMI using the formula: EMI = P × r × (1 + r)^n / ((1 + r)^n - 1)
        // Where P = principal, r = monthly interest rate, n = total number of months
        let monthlyRate = monthlyInterestRate / 100.0
        let totalMonths = 60 // Assuming 5 years for car loan, can be made configurable
        
        if monthlyRate == 0 { return principalAmount / Double(totalMonths) }
        
        let numerator = principalAmount * monthlyRate * pow(1 + monthlyRate, Double(totalMonths))
        let denominator = pow(1 + monthlyRate, Double(totalMonths)) - 1
        
        return numerator / denominator
    }
}

class LoanManager: ObservableObject {
    static let shared = LoanManager()
    
    private init() {}
    
    func calculateInterestForLoan(_ account: CDAccount) -> Double {
        let metadata = account.metadataDictionary
        guard let interestRateString = metadata["interestRate"],
              let interestRate = Double(interestRateString),
              let lastCalculationString = metadata["lastInterestCalculationDate"],
              let lastCalculationDate = ISO8601DateFormatter().date(from: lastCalculationString) else {
            return 0
        }
        
        let months = Calendar.current.dateComponents([.month], from: lastCalculationDate, to: Date()).month ?? 0
        let days = Calendar.current.dateComponents([.day], from: lastCalculationDate, to: Date()).day ?? 0
        
        // Calculate monthly interest if it's been at least a month or 30 days
        if months > 0 || days >= 30 {
            let monthlyRate = interestRate / 12.0
            return account.balance * (monthlyRate / 100.0)
        }
        
        return 0
    }
    
    func shouldCalculateInterest(_ account: CDAccount) -> Bool {
        let metadata = account.metadataDictionary
        guard let lastCalculationString = metadata["lastInterestCalculationDate"],
              let lastCalculationDate = ISO8601DateFormatter().date(from: lastCalculationString) else {
            // If no last calculation date, calculate interest
            return true
        }
        
        // Calculate interest if it's been at least one month or 30 days since last calculation
        let monthsSinceLastCalculation = Calendar.current.dateComponents([.month], from: lastCalculationDate, to: Date()).month ?? 0
        let daysSinceLastCalculation = Calendar.current.dateComponents([.day], from: lastCalculationDate, to: Date()).day ?? 0
        
        return monthsSinceLastCalculation > 0 || daysSinceLastCalculation >= 30
    }
    
    func updateLoanWithInterest(_ account: CDAccount, in context: NSManagedObjectContext) {
        guard account.accountType == AccountType.loan.rawValue || 
              account.accountType == AccountType.personalLoanGiven.rawValue else {
            return
        }
        
        let interest = calculateInterestForLoan(account)
        if interest > 0 {
            // Add interest to outstanding amount
            account.balance += interest
            
            // Update last calculation date to next month
            var metadata = account.metadataDictionary
            let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            metadata["lastInterestCalculationDate"] = ISO8601DateFormatter().string(from: nextMonth)
            account.metadataDictionary = metadata
            
            // Add interest transaction
            let transaction = CDTransaction(context: context)
            transaction.id = UUID()
            transaction.amount = interest
            transaction.category = "Interest"
            transaction.date = Date()
            transaction.isCredit = account.accountType == AccountType.personalLoanGiven.rawValue
            transaction.notes = "Monthly interest accrued on loan"
            transaction.account = account
            
            try? context.save()
            
            print("Monthly interest applied: \(interest) for account: \(account.wrappedAccountName)")
        }
    }
    
    func getLoanDetails(_ account: CDAccount) -> LoanDetails? {
        let metadata = account.metadataDictionary
        
        // Try to migrate old loan data if needed
        if shouldMigrateLoanData(account) {
            migrateLoanData(account)
        }
        
        // Get principal amount
        guard let principalString = metadata["principalAmount"],
              let principal = Double(principalString) else {
            print("Failed to get principal amount for account: \(account.wrappedAccountName)")
            return nil
        }
        
        // Get interest rate - handle both string and number formats
        let interestRate: Double
        if let interestRateString = metadata["interestRate"] {
            if let rate = Double(interestRateString) {
                interestRate = rate
            } else {
                print("Failed to parse interest rate: \(interestRateString) for account: \(account.wrappedAccountName)")
                return nil
            }
        } else {
            print("No interest rate found for account: \(account.wrappedAccountName)")
            return nil
        }
        
        // Get loan date
        guard let loanDateString = metadata["loanDate"],
              let loanDate = ISO8601DateFormatter().date(from: loanDateString) else {
            print("Failed to get loan date for account: \(account.wrappedAccountName)")
            return nil
        }
        
        // Get last calculation date, default to loan date if not found
        let lastCalculationDate = metadata["lastInterestCalculationDate"].flatMap { 
            ISO8601DateFormatter().date(from: $0) 
        } ?? loanDate
        
        let emiAmount = metadata["emiAmount"].flatMap { Double($0) }
        
        return LoanDetails(
            principalAmount: principal,
            interestRate: interestRate,
            loanDate: loanDate,
            lastInterestCalculationDate: lastCalculationDate,
            outstandingAmount: account.balance,
            notes: metadata["notes"],
            emiAmount: emiAmount
        )
    }
    
    private func shouldMigrateLoanData(_ account: CDAccount) -> Bool {
        let metadata = account.metadataDictionary
        return metadata["principalAmount"] == nil || metadata["loanDate"] == nil
    }
    
    private func migrateLoanData(_ account: CDAccount) {
        var metadata = account.metadataDictionary
        
        // If no principal amount, use credit limit or current balance
        if metadata["principalAmount"] == nil {
            let principal = account.creditLimit > 0 ? account.creditLimit : account.balance
            metadata["principalAmount"] = String(principal)
        }
        
        // If no loan date, use today's date
        if metadata["loanDate"] == nil {
            metadata["loanDate"] = ISO8601DateFormatter().string(from: Date())
        }
        
        // If no last interest calculation date, use loan date
        if metadata["lastInterestCalculationDate"] == nil {
            metadata["lastInterestCalculationDate"] = metadata["loanDate"]
        }
        
        // Fix old metadata key
        if let oldLastInterestDate = metadata["lastInterestDate"] {
            metadata["lastInterestCalculationDate"] = oldLastInterestDate
            metadata.removeValue(forKey: "lastInterestDate")
        }
        
        account.metadataDictionary = metadata
        print("Migrated loan data for account: \(account.wrappedAccountName)")
    }
    
    func createLoanAccount(
        name: String,
        principalAmount: Double,
        interestRate: Double,
        loanDate: Date,
        notes: String?,
        isPersonalLoanGiven: Bool,
        emiAmount: Double? = nil,
        loanTenure: Int = 60,
        in context: NSManagedObjectContext
    ) -> CDAccount {
        let account = CDAccount(context: context)
        account.id = UUID()
        account.accountName = name
        account.accountType = isPersonalLoanGiven ? AccountType.personalLoanGiven.rawValue : AccountType.loan.rawValue
        account.balance = principalAmount
        account.creditLimit = principalAmount
        
        var metadata: [String: String] = [
            "principalAmount": String(principalAmount),
            "interestRate": String(interestRate),
            "loanDate": ISO8601DateFormatter().string(from: loanDate),
            "lastInterestCalculationDate": ISO8601DateFormatter().string(from: loanDate),
            "loanTenure": String(loanTenure),
            "notes": notes ?? ""
        ]
        
        if let emi = emiAmount {
            metadata["emiAmount"] = String(emi)
        }
        
        account.metadataDictionary = metadata
        
        return account
    }
} 