import SwiftUI
import FirebaseFirestore
import Foundation

enum Currency: String, CaseIterable {
    case inr = "INR"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    
    var symbol: String {
        switch self {
        case .inr: return "₹"
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }
}

class CurrencySettings: ObservableObject {
    static let shared = CurrencySettings()
    private let db = Firestore.firestore()
    
    @AppStorage("selectedCurrency") var storedCurrency = Currency.inr.rawValue
    @Published var selectedCurrency: Currency {
        didSet {
            storedCurrency = selectedCurrency.rawValue
            syncToCloud()
        }
    }
    
    private init() {
        self.selectedCurrency = Currency(rawValue: UserDefaults.standard.string(forKey: "selectedCurrency") ?? Currency.inr.rawValue) ?? .inr
    }
    
    func syncToCloud() {
        Task { @MainActor in
            guard let userId = AuthenticationManager.shared.currentUser?.id else { return }
        
            db.collection("settings").document(userId).setData([
                "currency": selectedCurrency.rawValue
            ], merge: true) { error in
                if let error = error {
                    print("Error syncing currency settings: \(error)")
                }
            }
        }
    }
    
    func loadFromCloud() {
        Task { @MainActor in
            guard let userId = AuthenticationManager.shared.currentUser?.id else { return }
        
        db.collection("settings").document(userId).getDocument { [weak self] document, error in
            if let document = document, document.exists,
               let currencyString = document.data()?["currency"] as? String,
               let currency = Currency(rawValue: currencyString) {
                DispatchQueue.main.async {
                    self?.selectedCurrency = currency
                }
            }
        }
        }
    }
} 