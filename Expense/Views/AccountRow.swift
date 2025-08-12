import SwiftUI

struct AccountRow: View {
    let account: CDAccount
    @StateObject private var currencySettings = CurrencySettings.shared
    
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
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 5)
    }
}

#if DEBUG
struct AccountRow_Previews: PreviewProvider {
    static var previews: some View {
        AccountRow(account: PreviewHelper.shared.sampleAccount())
    }
}
#endif 