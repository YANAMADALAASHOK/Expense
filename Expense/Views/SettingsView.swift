import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    @AppStorage("showDecimals") private var showDecimals = true
    @AppStorage("defaultAccountType") private var defaultAccountType = AccountType.bankAccount.rawValue
    @State private var showingCategoryManagement = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Currency") {
                    Picker("Currency", selection: $currencySettings.selectedCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text("\(currency.symbol) (\(currency.rawValue))").tag(currency)
                        }
                    }
                }
                
                Section("Categories") {
                    Button(action: { showingCategoryManagement = true }) {
                        HStack {
                            Text("Manage Categories")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("Display Settings") {
                    Toggle("Show Decimal Places", isOn: $showDecimals)
                    
                    Picker("Default Account Type", selection: $defaultAccountType) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type.rawValue)
                        }
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingCategoryManagement) {
                CategoryManagementView(viewModel: viewModel)
            }
        }
    }
} 