import CoreData

class PreviewData {
    static let shared = PreviewData()
    
    let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }
    
    init() {
        container = NSPersistentContainer(name: "Expense")
        container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
    }
} 