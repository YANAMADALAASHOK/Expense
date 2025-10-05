import Foundation

// MARK: - Credit Card Bank Configuration
enum CreditCardBank: String, CaseIterable {
    case axis = "cc.statements@axisbank.com"
    case icici = "credit_cards@icicibank.com"
    case hdfc = "emailstatements.cards@hdfcbank.net"
    case sbi = "sbicard.alert@sbicard.com"
    case kotak = "creditcard@kotak.com"
    
    var displayName: String {
        switch self {
        case .axis: return "Axis Bank"
        case .icici: return "ICICI Bank"
        case .hdfc: return "HDFC Bank"
        case .sbi: return "SBI Card"
        case .kotak: return "Kotak Bank"
        }
    }
    
    var cardTypes: [String] {
        switch self {
        case .axis:
            return [
                "My Zone",
                "Neo",
                "Ace",
                "Flipkart",
                "Magnus",
                "Vistara",
                "Reserve",
                "Atlas"
            ]
        case .icici:
            return [
                "Amazon Pay",
                "Coral",
                "Rubyx",
                "Sapphiro",
                "Emeralde",
                "Platinum",
                "Manchester United"
            ]
        case .hdfc:
            return [
                "Millennia",
                "Regalia",
                "Diners Club",
                "Infinia",
                "MoneyBack",
                "Tata Neu"
            ]
        case .sbi:
            return [
                "SimplyCLICK",
                "SimplySAVE",
                "Cashback",
                "Elite",
                "Prime",
                "Octane"
            ]
        case .kotak:
            return [
                "811",
                "Essentia",
                "Royale Signature",
                "White",
                "League Platinum"
            ]
        }
    }
}
