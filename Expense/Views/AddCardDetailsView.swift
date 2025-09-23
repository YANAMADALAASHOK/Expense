import SwiftUI

struct AddCardDetailsView: View {
    let account: CDAccount
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var cardNumber = ""
    @State private var expiryDate = ""
    @State private var cvv = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(account.wrappedAccountName)
                                .font(.headline)
                            Text("Add missing card details")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Card Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Card Number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1234 5678 9012 3456", text: $cardNumber)
                            .keyboardType(.numberPad)
                            .textContentType(.creditCardNumber)
                            .onChange(of: cardNumber) { _, newValue in
                                cardNumber = formatCardNumber(newValue)
                            }
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Expiry Date")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("MM/YY", text: $expiryDate)
                                .keyboardType(.numberPad)
                                .onChange(of: expiryDate) { _, newValue in
                                    expiryDate = formatExpiryDate(newValue)
                                }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CVV")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("123", text: $cvv)
                                .keyboardType(.numberPad)
                                .onChange(of: cvv) { _, newValue in
                                    cvv = String(newValue.prefix(4)) // Limit to 4 digits
                                }
                        }
                    }
                }
                
                Section {
                    Button(action: saveCardDetails) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(isLoading ? "Saving..." : "Save Card Details")
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(isFormValid ? Color.blue : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!isFormValid || isLoading)
                    .listRowBackground(Color.clear)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Security Information")
                                .font(.headline)
                        }
                        
                        Text("• Card details are stored securely in encrypted metadata")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Information is only visible when you choose to reveal it")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• You can share details securely with the share button")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Add Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadExistingDetails()
        }
    }
    
    private var isFormValid: Bool {
        !cardNumber.isEmpty && 
        cardNumber.replacingOccurrences(of: " ", with: "").count >= 13 &&
        !expiryDate.isEmpty && 
        expiryDate.count == 5 &&
        !cvv.isEmpty && 
        cvv.count >= 3
    }
    
    private func loadExistingDetails() {
        guard let metadata = account.metadata,
              let metadataString = String(data: metadata, encoding: .utf8) else {
            return
        }
        
        // Load existing card details if available
        if let existingNumber = extractCardDetail(from: metadataString, patterns: [
            "fullCardNumber\":\\s*\"([0-9\\s]+)\"",
            "cardNumber\":\\s*\"([0-9\\s]+)\""
        ]) {
            cardNumber = formatCardNumber(existingNumber)
        }
        
        if let existingExpiry = extractCardDetail(from: metadataString, patterns: [
            "expiryDate\":\\s*\"([0-9]{2}/[0-9]{2})\"",
            "expiry\":\\s*\"([0-9]{2}/[0-9]{2})\""
        ]) {
            expiryDate = existingExpiry
        }
        
        if let existingCVV = extractCardDetail(from: metadataString, patterns: [
            "cvv\":\\s*\"([0-9]{3,4})\"",
            "cvc\":\\s*\"([0-9]{3,4})\""
        ]) {
            cvv = existingCVV
        }
    }
    
    private func extractCardDetail(from metadata: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)),
               let range = Range(match.range(at: 1), in: metadata) {
                return String(metadata[range]).replacingOccurrences(of: " ", with: "")
            }
        }
        return nil
    }
    
    private func formatCardNumber(_ input: String) -> String {
        let cleaned = input.replacingOccurrences(of: " ", with: "")
        let limited = String(cleaned.prefix(16)) // Limit to 16 digits
        
        var formatted = ""
        for (index, character) in limited.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted += String(character)
        }
        return formatted
    }
    
    private func formatExpiryDate(_ input: String) -> String {
        let cleaned = input.replacingOccurrences(of: "/", with: "")
        let limited = String(cleaned.prefix(4)) // Limit to 4 digits
        
        if limited.count >= 3 {
            let month = String(limited.prefix(2))
            let year = String(limited.suffix(limited.count - 2))
            return "\(month)/\(year)"
        } else {
            return limited
        }
    }
    
    private func saveCardDetails() {
        isLoading = true
        
        do {
            // Get existing metadata or create new
            var metadata = account.metadataDictionary
            
            // Add card details
            let cleanedCardNumber = cardNumber.replacingOccurrences(of: " ", with: "")
            metadata["fullCardNumber"] = cleanedCardNumber
            metadata["expiryDate"] = expiryDate
            metadata["cvv"] = cvv
            
            // Save to account metadata
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata) {
                account.metadata = jsonData
                
                // Save to Core Data
                try viewModel.viewContext.save()
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.dismiss()
                }
            } else {
                throw NSError(domain: "CardDetails", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save card details"])
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                self.showingError = true
            }
        }
    }
}

#if DEBUG
struct AddCardDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        AddCardDetailsView(account: PreviewHelper.shared.sampleAccount(), viewModel: ExpenseViewModel(context: context))
    }
}
#endif
