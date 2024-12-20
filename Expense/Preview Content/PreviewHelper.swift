import CoreData

struct PreviewHelper {
    static let shared = PreviewHelper()
    private let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }
    
    private init() {
        container = NSPersistentContainer(name: "Expense")
        container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
    }
    
    // Sample data for previews
    func sampleAccount() -> CDAccount {
        let account = CDAccount(context: viewContext)
        account.id = UUID()
        account.accountName = "Sample Account"
        account.accountType = AccountType.bankAccount.rawValue
        account.balance = 1000
        account.creditLimit = 0
        return account
    }
    
    func sampleTransaction() -> CDTransaction {
        let transaction = CDTransaction(context: viewContext)
        transaction.id = UUID()
        transaction.amount = 50
        transaction.category = TransactionCategory.food.rawValue
        transaction.date = Date()
        transaction.isCredit = false
        transaction.notes = "Sample transaction"
        transaction.account = sampleAccount()
        return transaction
    }
} 