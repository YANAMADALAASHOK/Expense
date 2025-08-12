import SwiftUI

struct AxisAccountPickerView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    let onPick: (CDAccount) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: CDAccount?
    @State private var showCreate = false
    @State private var newAccountName: String = "Axis Bank"

    var body: some View {
        List {
            Section("Select Account") {
                ForEach(viewModel.accounts) { account in
                    Button(action: { selectedAccount = account }) {
                        HStack {
                            Text(account.wrappedAccountName)
                            Spacer()
                            if selectedAccount?.objectID == account.objectID { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Section("Or Create New Account") {
                TextField("Account Name", text: $newAccountName)
                Button("Create and Use") {
                    viewModel.addAccount(name: newAccountName, type: .bankAccount, balance: 0)
                    if let created = viewModel.accounts.first(where: { $0.wrappedAccountName == newAccountName }) {
                        selectedAccount = created
                    }
                }
            }
        }
        .navigationTitle("Choose Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    if let acc = selectedAccount ?? viewModel.accounts.first { onPick(acc) }
                }.disabled((selectedAccount == nil) && viewModel.accounts.isEmpty)
            }
        }
    }
}


