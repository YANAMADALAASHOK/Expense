import SwiftUI

struct AccountRow: View {
    let account: CDAccount
    @StateObject private var currencySettings = CurrencySettings.shared
    @State private var showCardDetails = false
    @State private var showingShareSheet = false
    
    // Check if this is a credit card account
    private var isCreditCard: Bool {
        account.accountType == AccountType.creditCard.rawValue
    }
    
    // Extract card details from metadata
    private var cardDetails: (number: String, expiry: String, cvv: String) {
        guard let metadata = account.metadata,
              let metadataString = String(data: metadata, encoding: .utf8) else {
            print("DEBUG: No metadata found for account: \(account.wrappedAccountName)")
            return ("****", "MM/YY", "***")
        }
        
        print("DEBUG: Metadata for \(account.wrappedAccountName): \(metadataString)")
        
        let fullNumber = extractCardDetail(from: metadataString, patterns: [
            "fullCardNumber\":\\s*\"([0-9\\s]+)\"",
            "cardNumber\":\\s*\"([0-9\\s]+)\""
        ]) ?? "****"
        
        // Try direct dictionary access first, then regex patterns
        let metadataDict = account.metadataDictionary
        let expiry = metadataDict["expiryDate"] ?? 
                    metadataDict["expiry"] ?? 
                    extractCardDetail(from: metadataString, patterns: [
                        "\"expiryDate\"\\s*:\\s*\"([^\"]+)\"",
                        "\"expiry\"\\s*:\\s*\"([^\"]+)\"",
                        "expiryDate\":\\s*\"([0-9]{1,2}/[0-9]{1,4})\"",
                        "expiry\":\\s*\"([0-9]{1,2}/[0-9]{1,4})\""
                    ]) ?? "MM/YY"
        
        let cvv = extractCardDetail(from: metadataString, patterns: [
            "cvv\":\\s*\"([0-9]{3,4})\"",
            "cvc\":\\s*\"([0-9]{3,4})\""
        ]) ?? "***"
        
        print("DEBUG: Extracted - Number: \(fullNumber), Expiry: \(expiry), CVV: \(cvv)")
        
        return (fullNumber, expiry, cvv)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(account.wrappedAccountName)
                    .font(.headline)
                Spacer()
                Text(account.balance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(account.wrappedAccountType.isAsset ? .green : .red)
            }
            
            if let type = account.accountType {
                Text(type)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show credit card details if it's a credit card
            if isCreditCard {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Card Number")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(showCardDetails ? formatCardNumber(cardDetails.number) : "****  ****  ****  \(String(cardDetails.number.suffix(4)))")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            Button(action: { 
                                showCardDetails.toggle() 
                            }) {
                                Image(systemName: showCardDetails ? "eye.slash" : "eye")
                                    .foregroundColor(.blue)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Expiry")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(cardDetails.expiry)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("CVV")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(showCardDetails ? cardDetails.cvv : "***")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            Button(action: { 
                                showingShareSheet = true 
                            }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(.blue)
                        Text("Card Details")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [createShareText()])
        }
    }
    
    private func extractCardDetail(from metadata: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)),
               let range = Range(match.range(at: 1), in: metadata) {
                let extracted = String(metadata[range])
                // Only remove spaces for card numbers, preserve "/" for expiry dates
                if extracted.contains("/") {
                    return extracted.trimmingCharacters(in: .whitespaces)
                } else {
                    return extracted.replacingOccurrences(of: " ", with: "")
                }
            }
        }
        return nil
    }
    
    private func formatCardNumber(_ number: String) -> String {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        var formatted = ""
        for (index, character) in cleaned.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += "  "
            }
            formatted += String(character)
        }
        return formatted
    }
    
    private func createShareText() -> String {
        let details = cardDetails
        return """
        💳 \(account.wrappedAccountName)
        
        Card Number: \(details.number)
        Expiry Date: \(details.expiry)
        CVV: \(details.cvv)
        
        💰 Balance: \(account.balance.formatted(.currency(code: currencySettings.selectedCurrency.rawValue)))
        
        📱 Shared from Expense Tracker App
        """
    }
}

#if DEBUG
struct AccountRow_Previews: PreviewProvider {
    static var previews: some View {
        AccountRow(account: PreviewHelper.shared.sampleAccount())
    }
}
#endif 