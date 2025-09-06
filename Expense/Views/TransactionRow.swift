import SwiftUI

struct TransactionRow: View {
    let transaction: CDTransaction
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(displayCategory)
                    .font(.headline)
                if let notes = transaction.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(transaction.amount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .foregroundColor(transaction.isCredit ? .green : .red)
                Text(transaction.wrappedDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension TransactionRow {
    var displayCategory: String {
        let raw = transaction.wrappedCategory
        if let range = raw.range(of: "::"), !raw.hasPrefix("::"), !raw.hasSuffix("::") {
            let parent = String(raw[..<range.lowerBound])
            let sub = String(raw[range.upperBound...])
            return "\(parent) • \(sub)"
        }
        return raw
    }
}

#if DEBUG
struct TransactionRow_Previews: PreviewProvider {
    static var previews: some View {
        TransactionRow(transaction: PreviewHelper.shared.sampleTransaction())
    }
}
#endif 