import SwiftUI

struct TransactionRow: View {
    let transaction: CDTransaction
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.wrappedCategory)
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

#if DEBUG
struct TransactionRow_Previews: PreviewProvider {
    static var previews: some View {
        TransactionRow(transaction: PreviewHelper.shared.sampleTransaction())
    }
}
#endif 