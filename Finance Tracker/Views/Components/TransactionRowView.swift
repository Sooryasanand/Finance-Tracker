import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    
    var body: some View {
        HStack(spacing: 12) {
            // Category Icon
            Image(systemName: transaction.category?.icon ?? "questionmark.circle")
                .font(.title2)
                .foregroundColor(Color(hex: transaction.category?.color ?? "#007AFF"))
                .frame(width: 40, height: 40)
                .background(Color(hex: transaction.category?.color ?? "#007AFF").opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.category?.name ?? "Unknown")
                    .font(.headline)
                    .fontWeight(.medium)
                
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text(transaction.date?.formatted(date: .abbreviated, time: .shortened) ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatAmount(transaction.amount as Decimal?, type: transaction.type))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.type == "income" ? .green : .red)
                
                if transaction.receiptImageData != nil {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func formatAmount(_ amount: Decimal?, type: String?) -> String {
        guard let amount = amount else { return "$0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        
        let prefix = type == "income" ? "+" : "-"
        return prefix + (formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}