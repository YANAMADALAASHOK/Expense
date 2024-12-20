import SwiftUI

struct MutualFundRow: View {
    let account: CDAccount
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var investedAmount: Double {
        account.creditLimit
    }
    
    var currentValue: Double {
        account.balance
    }
    
    var profit: Double {
        currentValue - investedAmount
    }
    
    var returns: Double {
        guard investedAmount > 0 else { return 0 }
        return ((currentValue - investedAmount) / investedAmount) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(account.wrappedAccountName)
                    .font(.headline)
                Spacer()
                Text(currentValue, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .font(.subheadline)
            }
            
            HStack {
                Text("Initial Investment:")
                Text(investedAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .foregroundColor(.secondary)
            }
            .font(.caption)
            
            HStack {
                Text("Profit/Loss:")
                Text(profit, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .foregroundColor(profit >= 0 ? .green : .red)
            }
            .font(.caption)
            
            HStack {
                Text("Returns:")
                Text("\(String(format: "%.1f", returns))%")
                    .foregroundColor(returns >= 0 ? .green : .red)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct MutualFundRow_Previews: PreviewProvider {
    static var previews: some View {
        MutualFundRow(account: PreviewHelper.shared.sampleAccount())
    }
}
#endif