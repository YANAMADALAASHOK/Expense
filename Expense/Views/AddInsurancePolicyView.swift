import SwiftUI

struct AddInsurancePolicyView: View {
    // Pass accounts and persistence closures from parent to avoid dynamicMember issues
    var accounts: [CDAccount]
    var initial: InsurancePolicy?
    var onSave: (InsurancePolicy) -> Void
    var onDelete: ((InsurancePolicy) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var premiumAmount: String = ""
    @State private var dayOfMonth: Int = 1
    @State private var selectedAccountId: UUID?
    @State private var notes: String = ""
    @State private var isActive: Bool = true

    private var isEditing: Bool { initial != nil }

    var body: some View {
        NavigationView {
            Form {
                Section("Policy Details") {
                    TextField("Policy Name", text: $name)
                    TextField("Premium Amount", text: $premiumAmount)
                        .keyboardType(.decimalPad)
                    Stepper(value: $dayOfMonth, in: 1...31) {
                        Text("Debit Day: \(dayOfMonth)")
                    }
                    Toggle("Active", isOn: $isActive)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }

                Section("Debit From Account") {
                    Picker("Account", selection: $selectedAccountId) {
                        Text("Select Account").tag(nil as UUID?)
                        ForEach(accounts) { acc in
                            Text(acc.wrappedAccountName).tag(acc.id as UUID?)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let p = initial {
                                onDelete?(p)
                                dismiss()
                            }
                        } label: {
                            Label("Delete Policy", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Insurance" : "Add Insurance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePolicy() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadInitial)
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard Double(premiumAmount.replacingOccurrences(of: ",", with: "")) != nil else { return false }
        guard selectedAccountId != nil else { return false }
        return true
    }

    private func loadInitial() {
        if let p = initial {
            name = p.name
            premiumAmount = String(format: "%.2f", p.premiumAmount)
            dayOfMonth = p.dayOfMonth
            selectedAccountId = p.accountId
            notes = p.notes ?? ""
            isActive = p.isActive
        } else {
            // Defaults
            dayOfMonth = Calendar.current.component(.day, from: Date())
            selectedAccountId = accounts.first?.id
        }
    }

    private func savePolicy() {
        guard let accountId = selectedAccountId else { return }
        let amount = Double(premiumAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        var policy = InsurancePolicy(
            id: initial?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            premiumAmount: amount,
            dayOfMonth: dayOfMonth,
            accountId: accountId,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            lastPaidAt: initial?.lastPaidAt,
            isActive: isActive
        )
        onSave(policy)
        dismiss()
    }
}

#if DEBUG
struct AddInsurancePolicyView_Previews: PreviewProvider {
    static var previews: some View {
        AddInsurancePolicyView(accounts: [], initial: nil, onSave: { _ in })
    }
}
#endif
