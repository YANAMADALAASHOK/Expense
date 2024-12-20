import Foundation

enum Currency: String, CaseIterable {
    case usd = "USD"
    case inr = "INR"
    
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .inr: return "₹"
        }
    }
    
    var exchangeRate: Double {
        switch self {
        case .usd: return 1.0
        case .inr: return 83.0 // You can update this with real-time rates
        }
    }
}

class CurrencySettings: ObservableObject {
    static let shared = CurrencySettings()
    
    @Published var selectedCurrency: Currency {
        didSet {
            UserDefaults.standard.set(selectedCurrency.rawValue, forKey: "SelectedCurrency")
        }
    }
    
    private init() {
        let savedCurrency = UserDefaults.standard.string(forKey: "SelectedCurrency") ?? Currency.usd.rawValue
        selectedCurrency = Currency(rawValue: savedCurrency) ?? .usd
    }
} 