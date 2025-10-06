import SwiftUI
import CoreData

struct AddCreditCardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var currencySettings = CurrencySettings.shared
    
    // Focus management for auto-navigation
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case cardSection1, cardSection2, cardSection3, cardSection4
        case expiryMonth, expiryYear, cvv
        case totalLimit, availableLimit
    }
    
    // Card Details
    @State private var cardSection1 = ""
    @State private var cardSection2 = ""
    @State private var cardSection3 = ""
    @State private var cardSection4 = ""
    @State private var expiryMonth = ""
    @State private var expiryYear = ""
    @State private var cvv = ""
    @State private var selectedBank: CreditCardBank = .axis
    @State private var selectedCardType: String = ""
    
    // Computed full card number
    private var fullCardNumber: String {
        cardSection1 + cardSection2 + cardSection3 + cardSection4
    }
    
    // Last 4 digits for display
    private var last4Digits: String {
        cardSection4
    }
    
    // Financial Details
    @State private var totalLimit = ""
    @State private var availableLimit = ""
    
    // UI States
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Computed current usage
    private var currentUsage: Double? {
        guard let total = Double(totalLimit), !totalLimit.isEmpty,
              let available = Double(availableLimit), !availableLimit.isEmpty else {
            return nil
        }
        return total - available
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Bank & Card Selection
                Section("Bank & Card Details") {
                    Picker("Select Bank", selection: $selectedBank) {
                        ForEach(CreditCardBank.allCases, id: \.self) { bank in
                            Text(bank.displayName).tag(bank)
                        }
                    }
                    .onChange(of: selectedBank) {
                        // Reset card type when bank changes
                        selectedCardType = ""
                    }
                    
                    Picker("Card Type", selection: $selectedCardType) {
                        Text("Select Card").tag("")
                        ForEach(selectedBank.cardTypes, id: \.self) { cardType in
                            Text(cardType).tag(cardType)
                        }
                    }
                }
                
                Section("Card Security") {
                    HStack {
                        SecureField("CVV", text: $cvv)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                            .focused($focusedField, equals: .cvv)
                            .onChange(of: cvv) { oldValue, newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered.count > 3 {
                                    cvv = String(filtered.prefix(3))
                                } else {
                                    cvv = filtered
                                }
                                // Auto-navigate to total limit when 3 digits entered
                                if cvv.count == 3 {
                                    focusedField = .totalLimit
                                }
                            }
                        
                        Spacer()
                        
                        Text("Card Security Code")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    HStack {
                        TextField("Total Credit Limit (Optional)", text: $totalLimit)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .totalLimit)
                            .onChange(of: totalLimit) { oldValue, newValue in
                                // Auto-navigate to available limit when user enters data
                                if !newValue.isEmpty && totalLimit.count > 3 {
                                    focusedField = .availableLimit
                                }
                                // Card name updates automatically via computed property
                            }
                        Picker("Currency", selection: $currencySettings.selectedCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    HStack {
                        TextField("Available Limit (Optional)", text: $availableLimit)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .availableLimit)
                        Picker("Currency", selection: $currencySettings.selectedCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    // Current Usage Display (only if values are provided)
                    if let usage = currentUsage {
                        HStack {
                            Text("Current Usage")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(usage, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                                .foregroundColor(usage > 0 ? .red : .secondary)
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Credit Limit Details (Optional)")
                } footer: {
                    Text("Leave empty to populate from email statements later")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Preview Section
                if !selectedCardType.isEmpty {
                    Section("Preview") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(generateCardName())
                                .font(.headline)
                            
                            if fullCardNumber.count > 0 {
                                Text(formatCardNumberForDisplay())
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            if !expiryMonth.isEmpty && !expiryYear.isEmpty {
                                Text("Expires: \(expiryMonth)/\(expiryYear)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let usage = currentUsage {
                                Text("Current Usage: \(usage, format: .currency(code: currencySettings.selectedCurrency.rawValue))")
                                    .font(.caption)
                                    .foregroundColor(usage > 0 ? .red : .green)
                            } else {
                                Text("Limits: To be populated from statements")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Add Credit Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCard() }
                        .disabled(!isFormValid)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isFormValid: Bool {
        // Required fields
        let hasBasicInfo = !selectedCardType.isEmpty &&
            cardSection1.count == 4 &&
            cardSection2.count == 4 &&
            cardSection3.count == 4 &&
            cardSection4.count == 4 &&
            expiryMonth.count == 2 &&
            expiryYear.count == 2 &&
            !cvv.isEmpty
        
        // If limits are provided, they must be valid numbers
        let limitsValid: Bool
        if !totalLimit.isEmpty || !availableLimit.isEmpty {
            // If one is provided, both should be provided and valid
            limitsValid = !totalLimit.isEmpty &&
                         !availableLimit.isEmpty &&
                         Double(totalLimit) != nil &&
                         Double(availableLimit) != nil
        } else {
            // Both empty is fine
            limitsValid = true
        }
        
        return hasBasicInfo && limitsValid
    }
    
    private func generateCardName() -> String {
        return "\(selectedBank.displayName) \(selectedCardType) ****\(last4Digits)"
    }
    
    private func formatCardNumberForDisplay() -> String {
        var display = ""
        if !cardSection1.isEmpty {
            display += cardSection1.padding(toLength: 4, withPad: "•", startingAt: 0)
        } else {
            display += "••••"
        }
        display += " "
        
        if !cardSection2.isEmpty {
            display += cardSection2.padding(toLength: 4, withPad: "•", startingAt: 0)
        } else {
            display += "••••"
        }
        display += " "
        
        if !cardSection3.isEmpty {
            display += cardSection3.padding(toLength: 4, withPad: "•", startingAt: 0)
        } else {
            display += "••••"
        }
        display += " "
        
        if !cardSection4.isEmpty {
            display += cardSection4.padding(toLength: 4, withPad: "•", startingAt: 0)
        } else {
            display += "••••"
        }
        
        return display
    }
    
    private func saveCard() {
        // Validate limits if provided
        var totalLimitValue: Double? = nil
        var availableLimitValue: Double? = nil
        
        if !totalLimit.isEmpty || !availableLimit.isEmpty {
            guard let total = Double(totalLimit),
                  let available = Double(availableLimit) else {
                errorMessage = "Please enter valid credit limit amounts or leave both empty"
                showingError = true
                return
            }
            
            guard available <= total else {
                errorMessage = "Available limit cannot be greater than total limit"
                showingError = true
                return
            }
            
            totalLimitValue = total
            availableLimitValue = available
        }
        
        guard let month = Int(expiryMonth),
              month >= 1 && month <= 12 else {
            errorMessage = "Invalid expiry month (1-12)"
            showingError = true
            return
        }
        
        // Calculate current usage (stored as negative for credit cards)
        let usage: Double
        let balance: Double
        
        if let total = totalLimitValue, let available = availableLimitValue {
            usage = total - available
            balance = -usage // Negative balance for credit cards
        } else {
            usage = 0.0
            balance = 0.0 // Will be updated from email statements later
        }
        
        // Build metadata
        var metadata: [String: String] = [
            "bankName": selectedBank.displayName,
            "cardType": selectedCardType,
            "cardNumber": last4Digits,
            "fullCardNumber": fullCardNumber, // Store full card number securely
            "expiryMonth": expiryMonth,
            "expiryYear": expiryYear,
            "cvv": cvv, // Store CVV
            "emailAddress": selectedBank.rawValue,
            "lastUpdated": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Add limit values only if provided
        if let total = totalLimitValue {
            metadata["totalLimit"] = String(total)
        }
        if let available = availableLimitValue {
            metadata["availableLimit"] = String(available)
        }
        if totalLimitValue != nil && availableLimitValue != nil {
            metadata["currentUsage"] = String(usage)
        }
        
        // Create account name
        let accountName = generateCardName()
        
        // Add account using ViewModel
        viewModel.addAccount(
            name: accountName,
            type: .creditCard,
            balance: balance,
            creditLimit: totalLimitValue ?? 0.0,
            metadata: metadata
        )
        
        print("✅ Credit card added: \(accountName)")
        if let total = totalLimitValue, let available = availableLimitValue {
            print("   Total Limit: ₹\(total)")
            print("   Available: ₹\(available)")
            print("   Current Usage: ₹\(usage)")
        } else {
            print("   Limits will be populated from email statements")
        }
        
        dismiss()
    }
}

#Preview {
    AddCreditCardView(viewModel: ExpenseViewModel(context: PersistenceController.preview.container.viewContext))
}
