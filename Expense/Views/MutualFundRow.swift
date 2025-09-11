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
            
            // Units and Folio
            HStack(spacing: 12) {
                let md = account.metadataDictionary
                if let unitsStr = md["units"], let units = Double(unitsStr) {
                    Text("Units: \(String(format: "%.4f", units))")
                } else {
                    Text("Units: —")
                        .foregroundColor(.secondary)
                }
                Divider()
                let folioKeys = ["folio","folioNumber","folio_no","Folio","Folio No","folioNo"]
                let folioVal: String? = folioKeys.compactMap { md[$0] }.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                Text("Folio: \(folioVal?.isEmpty == false ? folioVal! : "—")")
                    .foregroundColor((folioVal?.isEmpty == false) ? .primary : .secondary)
            }
            .font(.caption)

            // Scheme code and last NAV
            HStack(spacing: 12) {
                let md = account.metadataDictionary
                Text("Code: \(md["amfiSchemeCode"] ?? "—")")
                    .foregroundColor(md["amfiSchemeCode"] == nil ? .secondary : .primary)
                Divider()
                Text("NAV: \(md["lastNAV"] ?? "—")")
                    .foregroundColor(md["lastNAV"] == nil ? .secondary : .primary)
                if let d = md["lastNAVDate"], !d.isEmpty {
                    Divider()
                    Text(d)
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption2)

            if let tsIso = account.metadataDictionary["lastNAVUpdateAt"],
               let ts = ISO8601DateFormatter().date(from: tsIso) {
                Text("Updated: \(ts.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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