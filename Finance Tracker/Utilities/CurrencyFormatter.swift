import Foundation

struct CurrencyFormatter {
    static let shared = CurrencyFormatter()
    
    private let formatter: NumberFormatter
    
    private init() {
        formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
    }
    
    func string(from decimal: Decimal) -> String {
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "$0.00"
    }
    
    func string(from double: Double) -> String {
        return formatter.string(from: NSNumber(value: double)) ?? "$0.00"
    }
    
    func signedString(from decimal: Decimal, type: String) -> String {
        let formattedAmount = string(from: decimal)
        let prefix = type == "income" ? "+" : "-"
        return prefix + formattedAmount
    }
    
    func signedString(from double: Double, type: String) -> String {
        let formattedAmount = string(from: double)
        let prefix = type == "income" ? "+" : "-"
        return prefix + formattedAmount
    }
}