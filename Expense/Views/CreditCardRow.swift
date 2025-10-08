import SwiftUI

struct CreditCardRow: View {
    let account: CDAccount
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showingCardDetails = false
    @State private var showingBills = false
    
    private var metadata: [String: String] {
        account.metadataDictionary
    }
    
    private var bankName: String {
        metadata["bankName"] ?? "Unknown Bank"
    }
    
    private var cardType: String {
        metadata["cardType"] ?? ""
    }
    
    private var cardNumber: String {
        metadata["cardNumber"] ?? ""
    }
    
    private var totalLimit: Double {
        Double(metadata["totalLimit"] ?? "0") ?? account.creditLimit
    }
    
    private var currentUsage: Double {
        Double(metadata["currentUsage"] ?? "0") ?? abs(account.balance)
    }
    
    private var availableLimit: Double {
        totalLimit - currentUsage
    }
    
    private var usagePercentage: Double {
        guard totalLimit > 0 else { return 0 }
        return (currentUsage / totalLimit) * 100
    }
    
    private var usageColor: Color {
        switch usagePercentage {
        case 0..<30: return .green
        case 30..<60: return .yellow
        case 60..<80: return .orange
        default: return .red
        }
    }
    
    private var expiryDate: String? {
        guard let month = metadata["expiryMonth"],
              let year = metadata["expiryYear"] else {
            return nil
        }
        return "\(month)/\(year)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card Name and Number
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.wrappedAccountName)
                        .font(.headline)
                    
                    if !cardNumber.isEmpty {
                        Text("****\(cardNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Bills Button
                Button(action: {
                    showingBills = true
                }) {
                    Image(systemName: "doc.text.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                
                // Card Details Button
                Button(action: {
                    showingCardDetails = true
                }) {
                    Image(systemName: "creditcard.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(currentUsage, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    if let expiry = expiryDate {
                        Text("Exp: \(expiry)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Usage Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Usage")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(usagePercentage))%")
                        .font(.caption2)
                        .foregroundColor(usageColor)
                        .fontWeight(.semibold)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(usageColor)
                            .frame(width: min(geometry.size.width * (usagePercentage / 100), geometry.size.width), height: 6)
                    }
                }
                .frame(height: 6)
            }
            
            // Limits Info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(availableLimit, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Limit")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(totalLimit, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingCardDetails) {
            CardDetailsView(account: account)
        }
        .sheet(isPresented: $showingBills) {
            CreditCardBillsListView(account: account)
        }
    }
}

// MARK: - Card Details View
struct CardDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let account: CDAccount
    @State private var showingShareSheet = false
    
    private var metadata: [String: String] {
        account.metadataDictionary
    }
    
    private var bankName: String {
        metadata["bankName"] ?? "Unknown Bank"
    }
    
    private var cardType: String {
        metadata["cardType"] ?? "Unknown Card"
    }
    
    private var fullCardNumber: String {
        metadata["fullCardNumber"] ?? ""
    }
    
    private var formattedCardNumber: String {
        guard fullCardNumber.count == 16 else {
            return "****" + (metadata["cardNumber"] ?? "****")
        }
        // Format as: 4512 3456 7890 6988
        let section1 = String(fullCardNumber.prefix(4))
        let section2 = String(fullCardNumber.dropFirst(4).prefix(4))
        let section3 = String(fullCardNumber.dropFirst(8).prefix(4))
        let section4 = String(fullCardNumber.dropFirst(12).prefix(4))
        return "\(section1) \(section2) \(section3) \(section4)"
    }
    
    private var cvv: String {
        metadata["cvv"] ?? "N/A"
    }
    
    private var expiryMonth: String {
        metadata["expiryMonth"] ?? "MM"
    }
    
    private var expiryYear: String {
        metadata["expiryYear"] ?? "YY"
    }
    
    private var shareText: String {
        """
        💳 Credit Card Details
        
        Bank: \(bankName)
        Card Type: \(cardType)
        Card Number: \(formattedCardNumber)
        Expiry: \(expiryMonth)/\(expiryYear)
        CVV: \(cvv)
        
        Account: \(account.wrappedAccountName)
        """
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Card Visual Representation
                    VStack(alignment: .leading, spacing: 16) {
                        // Bank and Card Type
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bankName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(cardType)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        Spacer()
                        
                        // Card Number
                        Text(formattedCardNumber)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .tracking(2)
                        
                        // Expiry and CVV
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("VALID THRU")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text("\(expiryMonth)/\(expiryYear)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("CVV")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text(cvv)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .padding(.horizontal)
                    
                    // Card Details List
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(label: "Bank Name", value: bankName)
                        DetailRow(label: "Card Type", value: cardType)
                        DetailRow(label: "Card Number", value: formattedCardNumber)
                        DetailRow(label: "Expiry Date", value: "\(expiryMonth)/\(expiryYear)")
                        DetailRow(label: "CVV", value: cvv)
                        DetailRow(label: "Account Name", value: account.wrappedAccountName)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Share Button
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Card Details")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: [shareText])
            }
        }
    }
}

// MARK: - Detail Row Helper
private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

#Preview {
    List {
        CreditCardRow(account: {
            let context = PersistenceController.preview.container.viewContext
            let account = CDAccount(context: context)
            account.id = UUID()
            account.accountName = "Axis Bank My Zone ****6988"
            account.accountType = AccountType.creditCard.rawValue
            account.balance = -45000
            account.creditLimit = 200000
            let metadataDict: [String: String] = [
                "bankName": "Axis Bank",
                "cardType": "My Zone",
                "cardNumber": "6988",
                "fullCardNumber": "4512345678906988",
                "expiryMonth": "12",
                "expiryYear": "26",
                "cvv": "123",
                "totalLimit": "200000"
            ]
            account.metadataDictionary = metadataDict
            return account
        }())
    }
}
