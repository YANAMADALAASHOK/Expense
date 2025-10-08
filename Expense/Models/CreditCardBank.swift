import Foundation

// MARK: - Credit Card Bank Configuration
enum CreditCardBank: String, CaseIterable {
    case axis = "cc.statements@axisbank.com"
    case icici = "credit_cards@icicibank.com"
    case hdfc = "Emailstatements.cards@hdfcbank.net"
    case sbi = "Statements@sbicard.com"
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
                "BPCL",
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
    
    // Group banks for processing
    var bankGroup: String {
        switch self {
        case .axis: return "AXIS"
        case .icici: return "ICICI"
        case .hdfc: return "HDFC"
        case .sbi: return "SBI"
        case .kotak: return "KOTAK"
        }
    }
    
    // Check if this is an HDFC bank
    var isHDFC: Bool {
        return self == .hdfc
    }
    
    // Get all email addresses for this bank (HDFC has multiple)
    var emailAddresses: [String] {
        switch self {
        case .hdfc:
            return [
                "Emailstatements.cards@hdfcbank.net",
                "InstaEmailstatements.cards@hdfcbank.net"
            ]
        default:
            return [self.rawValue]
        }
    }
}
