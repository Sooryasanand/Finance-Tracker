import SwiftUI
import Charts

struct AnalyticsView: View {
    @StateObject private var viewModel = AnalyticsViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Period Selector
                    PeriodSelectorView(viewModel: viewModel)
                        .padding(.horizontal)
                    
                    if viewModel.categorySpending.isEmpty && !viewModel.isLoading {
                        EmptyAnalyticsView()
                    } else {
                        // Spending Insights
                        if !viewModel.spendingInsights.isEmpty {
                            InsightsSection(insights: viewModel.spendingInsights)
                                .padding(.horizontal)
                        }
                        
                        // Income vs Expenses Overview
                        IncomeExpenseOverviewCard(data: viewModel.incomeVsExpenses)
                            .padding(.horizontal)
                        
                        // Category Spending Chart
                        if !viewModel.categorySpending.isEmpty {
                            CategorySpendingChart(categoryData: viewModel.categorySpending)
                                .padding(.horizontal)
                        }
                        
                        // Monthly Trends Chart
                        if !viewModel.monthlyTrends.isEmpty {
                            MonthlyTrendsChart(trends: viewModel.monthlyTrends)
                                .padding(.horizontal)
                        }
                        
                        // Top Categories List
                        if !viewModel.topCategories.isEmpty {
                            TopCategoriesSection(categories: viewModel.topCategories)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Analytics")
            .refreshable {
                viewModel.refreshData()
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .overlay(
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                }
            }
        )
    }
}

struct PeriodSelectorView: View {
    @ObservedObject var viewModel: AnalyticsViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AnalyticsViewModel.AnalyticsPeriod.allCases, id: \.self) { period in
                    Button(action: {
                        viewModel.selectedPeriod = period
                    }) {
                        Text(period.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.selectedPeriod == period ? .white : .blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedPeriod == period ? Color.blue : Color.blue.opacity(0.1))
                            .cornerRadius(20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }
}

struct EmptyAnalyticsView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Data Available")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Add some transactions to see your spending analytics and insights")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct InsightsSection: View {
    let insights: [AnalyticsViewModel.SpendingInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 8) {
                ForEach(insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }
}

struct InsightCard: View {
    let insight: AnalyticsViewModel.SpendingInsight
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title3)
                .foregroundColor(insight.color)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(insight.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct IncomeExpenseOverviewCard: View {
    let data: AnalyticsViewModel.IncomeExpenseData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Income vs Expenses")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                        Text("Income")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(data.totalIncome.currencyFormatted)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    
                    Text("\(Int(data.incomePercentage))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("Expenses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(data.totalExpenses.currencyFormatted)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                    
                    Text("\(Int(data.expensePercentage))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Net")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(data.netAmount.currencyFormatted)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(data.netAmount >= 0 ? .green : .red)
                }
            }
            
            // Simple progress bar representation
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * CGFloat(data.incomePercentage / 100))
                    
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * CGFloat(data.expensePercentage / 100))
                }
            }
            .frame(height: 8)
            .cornerRadius(4)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct CategorySpendingChart: View {
    let categoryData: [AnalyticsViewModel.CategorySpending]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spending by Category")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Pie chart representation using simple bars for now
            VStack(spacing: 8) {
                ForEach(categoryData.prefix(5)) { category in
                    HStack {
                        Circle()
                            .fill(Color(hex: category.color))
                            .frame(width: 12, height: 12)
                        
                        Text(category.categoryName)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(category.amount.currencyFormatted)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("\(Int(category.percentage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color(hex: category.color).opacity(0.3))
                            .frame(width: geometry.size.width * CGFloat(category.percentage / 100), height: 4)
                            .cornerRadius(2)
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct MonthlyTrendsChart: View {
    let trends: [AnalyticsViewModel.MonthlyTrend]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly Trends")
                .font(.headline)
                .fontWeight(.semibold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(trends) { trend in
                        VStack(spacing: 8) {
                            Text(trend.month)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: 20, height: max(20, CGFloat(Double(truncating: trend.income as NSNumber) / 1000 * 60)))
                                    .cornerRadius(2)
                                
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 20, height: max(20, CGFloat(Double(truncating: trend.expenses as NSNumber) / 1000 * 60)))
                                    .cornerRadius(2)
                            }
                            
                            Text(trend.net.currencyFormatted)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(trend.net >= 0 ? .green : .red)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct TopCategoriesSection: View {
    let categories: [AnalyticsViewModel.TopCategory]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Categories")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 8) {
                ForEach(categories) { category in
                    TopCategoryRow(category: category)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct TopCategoryRow: View {
    let category: AnalyticsViewModel.TopCategory
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundColor(Color(hex: category.color))
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let change = category.changeFromPrevious {
                    Text("\(change > 0 ? "+" : "")\(Int(change))% from last period")
                        .font(.caption)
                        .foregroundColor(change > 0 ? .red : .green)
                }
            }
            
            Spacer()
            
            Text(category.amount.currencyFormatted)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AnalyticsView()
        .environment(\.managedObjectContext, CoreDataStack.shared.context)
}