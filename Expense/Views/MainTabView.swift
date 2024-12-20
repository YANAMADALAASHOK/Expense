import SwiftUI
import CoreData

struct MainTabView: View {
    @StateObject private var viewModel: ExpenseViewModel
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
    }
    
    var body: some View {
        TabView {
            AccountsView(viewModel: viewModel)
                .tabItem {
                    Label("Accounts", systemImage: "banknote")
                }
            
            TransactionView(viewModel: viewModel)
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet")
                }
            
            ReportsView(viewModel: viewModel)
                .tabItem {
                    Label("Reports", systemImage: "chart.pie")
                }
            
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#if DEBUG
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView(context: PreviewHelper.shared.viewContext)
    }
}
#endif 