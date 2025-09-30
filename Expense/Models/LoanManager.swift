import Foundation
import CoreData

struct LoanDetails {
    let principalAmount: Double
    let interestRate: Double // Annual interest rate in percentage
    let loanDate: Date
    let lastInterestGeneratedDate: Date?
    let interestDayOfMonth: Int?
    let outstandingAmount: Double
    let notes: String?
    let emiAmount: Double?
    let loanTenure: Int
    let monthsElapsed: Int?
    let remainingPayments: Int?
    let repaymentType: String?
    let emiDayOfMonth: Int?
    
    var monthlyInterestRate: Double {
        interestRate / 12.0 // Convert annual rate to monthly
    }
    
    var calculatedInterest: Double {
        // Calculate monthly interest on current outstanding amount
        return outstandingAmount * (monthlyInterestRate / 100.0)
    }
    
    var totalAmountWithInterest: Double {
        outstandingAmount + calculatedInterest
    }
    
    var nextInterestGenerationDate: Date {
        guard let interestDay = interestDayOfMonth else { return Date() }
        
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        let currentDay = calendar.component(.day, from: today)
        
        // If interest day hasn't passed this month, use this month
        if currentDay < interestDay {
            return calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: interestDay)) ?? today
        } else {
            // Otherwise, use next month
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
            let nextMonthComponents = calendar.dateComponents([.year, .month], from: nextMonth)
            return calendar.date(from: DateComponents(year: nextMonthComponents.year, month: nextMonthComponents.month, day: interestDay)) ?? today
        }
    }
    
    var daysUntilNextInterestGeneration: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextInterestGenerationDate).day ?? 0
        return max(0, days)
    }
    
    var lastInterestGeneratedText: String {
        if let lastDate = lastInterestGeneratedDate {
            return lastDate.formatted(date: .abbreviated, time: .omitted)
        } else {
            return "Not yet generated"
        }
    }
    
    var calculatedEMI: Double {
        guard monthlyInterestRate > 0 else { return 0 }
        
        // Calculate EMI using the formula: EMI = P × r × (1 + r)^n / ((1 + r)^n - 1)
        // Where P = principal, r = monthly interest rate, n = total number of months
        let monthlyRate = monthlyInterestRate / 100.0
        let totalMonths = loanTenure
        
        if monthlyRate == 0 { return principalAmount / Double(totalMonths) }
        
        let numerator = principalAmount * monthlyRate * pow(1 + monthlyRate, Double(totalMonths))
        let denominator = pow(1 + monthlyRate, Double(totalMonths)) - 1
        
        return numerator / denominator
    }
    
    var effectiveEMI: Double {
        return emiAmount ?? calculatedEMI
    }
    
    var calculatedMonthsElapsed: Int {
        if let elapsed = monthsElapsed {
            return elapsed
        }
        // Calculate months elapsed from loan date
        return Calendar.current.dateComponents([.month], from: loanDate, to: Date()).month ?? 0
    }
    
    var calculatedRemainingPayments: Int {
        if let remaining = remainingPayments {
            return remaining
        }
        return max(0, loanTenure - calculatedMonthsElapsed)
    }
    
    var totalInterestAccumulated: Double {
        let monthsElapsed = calculatedMonthsElapsed
        let monthlyRate = monthlyInterestRate / 100.0
        
        if monthlyRate == 0 {
            return 0
        }
        
        // Calculate total interest paid so far using EMI formula
        let emi = effectiveEMI
        let totalPaid = emi * Double(monthsElapsed)
        let principalPaid = principalAmount - outstandingAmount
        
        return max(0, totalPaid - principalPaid)
    }
    
    var loanProgress: Double {
        guard loanTenure > 0 else { return 0 }
        return Double(calculatedMonthsElapsed) / Double(loanTenure)
    }
    
    var isEMILoan: Bool {
        return repaymentType == "EMI" || emiAmount != nil
    }
    
    var nextEMIPaymentDate: Date? {
        guard isEMILoan, let emiDay = emiDayOfMonth else { return nil }
        
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        let currentDay = calendar.component(.day, from: today)
        
        // If EMI day hasn't passed this month, use this month
        if currentDay < emiDay {
            return calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: emiDay))
        } else {
            // Otherwise, use next month
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
            let nextMonthComponents = calendar.dateComponents([.year, .month], from: nextMonth)
            return calendar.date(from: DateComponents(year: nextMonthComponents.year, month: nextMonthComponents.month, day: emiDay))
        }
    }
    
    var daysUntilNextEMIPayment: Int? {
        guard let nextEMI = nextEMIPaymentDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextEMI).day ?? 0
        return max(0, days)
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
        
        // Get last interest generated date
        let lastInterestGenerated = metadata["lastInterestGenerated"].flatMap { 
            ISO8601DateFormatter().date(from: $0) 
        }
        
        // Get interest day of month
        let interestDay = metadata["interestDayOfMonth"].flatMap { Int($0) }
        
        // Get EMI amount from metadata
        let emiAmount = metadata["emiAmount"].flatMap { Double($0) }
        
        // Get loan tenure
        let loanTenure = metadata["loanTenure"].flatMap { Int($0) } ?? 60
        
        // Get months elapsed and remaining payments
        let monthsElapsed = metadata["monthsElapsed"].flatMap { Int($0) }
        let remainingPayments = metadata["remainingPayments"].flatMap { Int($0) }
        
        // Get repayment type
        let repaymentType = metadata["repaymentType"]
        
        // Get EMI day of month
        let emiDay = metadata["emiDayOfMonth"].flatMap { Int($0) }
        
        return LoanDetails(
            principalAmount: principal,
            interestRate: interestRate,
            loanDate: loanDate,
            lastInterestGeneratedDate: lastInterestGenerated,
            interestDayOfMonth: interestDay,
            outstandingAmount: account.balance,
            notes: metadata["notes"],
            emiAmount: emiAmount,
            loanTenure: loanTenure,
            monthsElapsed: monthsElapsed,
            remainingPayments: remainingPayments,
            repaymentType: repaymentType,
            emiDayOfMonth: emiDay
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
        repaymentType: String? = nil, // "EMI" or "ONE_TIME"
        emiDayOfMonth: Int? = nil,
        interestDayOfMonth: Int? = nil,
        emiFundingAccountId: UUID? = nil,
        monthsElapsed: Int? = nil,
        remainingPayments: Int? = nil,
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
            "loanTenure": String(loanTenure),
            "notes": notes ?? ""
        ]
        
        if let emi = emiAmount {
            metadata["emiAmount"] = String(emi)
        }
        if let repaymentType = repaymentType {
            metadata["repaymentType"] = repaymentType
        }
        if let emiDay = emiDayOfMonth {
            metadata["emiDayOfMonth"] = String(emiDay)
        }
        if let interestDay = interestDayOfMonth {
            metadata["interestDayOfMonth"] = String(interestDay)
        }
        if let fundingId = emiFundingAccountId {
            metadata["emiFundingAccountId"] = fundingId.uuidString
        }
        if let elapsed = monthsElapsed {
            metadata["monthsElapsed"] = String(elapsed)
        }
        if let remaining = remainingPayments {
            metadata["remainingPayments"] = String(remaining)
        }
        
        account.metadataDictionary = metadata
        
        return account
    }
} 