import SwiftUI

struct AccountRow: View {
    let account: CDAccount
    @StateObject private var currencySettings = CurrencySettings.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(account.wrappedAccountName)
                    .font(.headline)
                Spacer()
                Text(account.balance, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                    .foregroundColor(account.wrappedAccountType.isAsset ? .primary : .red)
            }
            
            if account.accountType == AccountType.creditCard.rawValue {
                let utilization = account.creditLimit > 0 ? (account.balance / account.creditLimit) * 100 : 0
                Text("Credit Utilization: \(String(format: "%.1f", utilization))%")
                    .font(.caption)
                    .foregroundColor(utilization < 30 ? .green : utilization < 70 ? .yellow : .red)
            } else if account.accountType == AccountType.loan.rawValue {
                let originalAmount = account.creditLimit
                let remainingAmount = account.balance
                let repaidAmount = originalAmount - remainingAmount
                let repaidPercentage = originalAmount > 0 ? (repaidAmount / originalAmount) * 100 : 0
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Original Amount:")
                        Text(originalAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("Repaid Amount:")
                        Text(repaidAmount, format: .currency(code: currencySettings.selectedCurrency.rawValue))
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("Repaid:")
                        Text("\(String(format: "%.1f", repaidPercentage))%")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct AccountRow_Previews: PreviewProvider {
    static var previews: some View {
        AccountRow(account: PreviewHelper.shared.sampleAccount())
    }
}
#endif 