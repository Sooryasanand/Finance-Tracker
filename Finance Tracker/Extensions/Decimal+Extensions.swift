import Foundation

extension Decimal {
    var doubleValue: Double {
        return NSDecimalNumber(decimal: self).doubleValue
    }
    
    var currencyFormatted: String {
        return CurrencyFormatter.shared.string(from: self)
    }
    
    func signedCurrencyFormatted(type: String) -> String {
        return CurrencyFormatter.shared.signedString(from: self, type: type)
    }
    
    static func from(double: Double) -> Decimal {
        return NSDecimalNumber(value: double).decimalValue
    }
    
    static func from(string: String) -> Decimal? {
        guard let double = Double(string) else { return nil }
        return NSDecimalNumber(value: double).decimalValue
    }
}