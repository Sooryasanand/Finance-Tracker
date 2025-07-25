import SwiftUI

struct BudgetProgressCard: View {
    let budget: DashboardViewModel.BudgetOverview
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(budget.name)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(budget.spent.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("of \(budget.limit.currencyFormatted)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(budget.progress), height: 6)
                        .cornerRadius(3)
                        .animation(.easeInOut(duration: 0.3), value: budget.progress)
                }
            }
            .frame(height: 6)
            
            HStack {
                Text("\(Int(budget.progress * 100))% used")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                let remaining = budget.limit - budget.spent
                Text("\(remaining.currencyFormatted) left")
                    .font(.caption)
                    .foregroundColor(remaining >= 0 ? .secondary : .red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var progressColor: Color {
        if budget.progress >= 1.0 {
            return .red
        } else if budget.progress >= 0.8 {
            return .orange
        } else if budget.progress >= 0.6 {
            return .yellow
        } else {
            return Color(hex: budget.color)
        }
    }
}