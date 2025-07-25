import Foundation
import CoreData
import Combine
import SwiftUI

class AnalyticsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: AnalyticsPeriod = .thisMonth
    @Published var categorySpending: [CategorySpending] = []
    @Published var monthlyTrends: [MonthlyTrend] = []
    @Published var incomeVsExpenses: IncomeExpenseData = IncomeExpenseData()
    @Published var topCategories: [TopCategory] = []
    @Published var spendingInsights: [SpendingInsight] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    
    enum AnalyticsPeriod: String, CaseIterable {
        case thisWeek = "thisWeek"
        case thisMonth = "thisMonth"
        case last3Months = "last3Months"
        case last6Months = "last6Months"
        case thisYear = "thisYear"
        
        var displayName: String {
            switch self {
            case .thisWeek: return "This Week"
            case .thisMonth: return "This Month"
            case .last3Months: return "Last 3 Months"
            case .last6Months: return "Last 6 Months"
            case .thisYear: return "This Year"
            }
        }
        
        var dateRange: (Date, Date) {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .thisWeek:
                let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
                return (weekInterval.start, weekInterval.end)
                
            case .thisMonth:
                let monthInterval = calendar.dateInterval(of: .month, for: now)!
                return (monthInterval.start, monthInterval.end)
                
            case .last3Months:
                let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
                return (calendar.startOfDay(for: threeMonthsAgo), now)
                
            case .last6Months:
                let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
                return (calendar.startOfDay(for: sixMonthsAgo), now)
                
            case .thisYear:
                let yearInterval = calendar.dateInterval(of: .year, for: now)!
                return (yearInterval.start, yearInterval.end)
            }
        }
    }
    
    struct CategorySpending: Identifiable {
        let id = UUID()
        let categoryName: String
        let amount: Decimal
        let color: String
        let percentage: Double
        let transactionCount: Int
    }
    
    struct MonthlyTrend: Identifiable {
        let id = UUID()
        let month: String
        let income: Decimal
        let expenses: Decimal
        let net: Decimal
    }
    
    struct IncomeExpenseData {
        var totalIncome: Decimal = 0
        var totalExpenses: Decimal = 0
        var netAmount: Decimal = 0
        var incomePercentage: Double = 0
        var expensePercentage: Double = 0
    }
    
    struct TopCategory: Identifiable {
        let id = UUID()
        let name: String
        let amount: Decimal
        let color: String
        let icon: String
        let changeFromPrevious: Double? // Percentage change from previous period
    }
    
    struct SpendingInsight: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let type: InsightType
        let icon: String
        let color: Color
        
        enum InsightType {
            case warning
            case positive
            case neutral
            case goal
        }
    }
    
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
        loadAnalytics()
    }
    
    private func setupBindings() {
        // Reload analytics when period changes
        $selectedPeriod
            .dropFirst()
            .sink { [weak self] _ in
                self?.loadAnalytics()
            }
            .store(in: &cancellables)
        
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadAnalytics()
            }
            .store(in: &cancellables)
    }
    
    func loadAnalytics() {
        isLoading = true
        errorMessage = nil
        
        let (startDate, endDate) = selectedPeriod.dateRange
        
        loadCategorySpending(startDate: startDate, endDate: endDate)
        loadMonthlyTrends()
        loadIncomeVsExpenses(startDate: startDate, endDate: endDate)
        loadTopCategories(startDate: startDate, endDate: endDate)
        generateSpendingInsights(startDate: startDate, endDate: endDate)
        
        isLoading = false
    }
    
    private func loadCategorySpending(startDate: Date, endDate: Date) {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date >= %@ AND date < %@", startDate as CVarArg, endDate as CVarArg),
            NSPredicate(format: "type == %@", "expense")
        ])
        
        do {
            let transactions = try viewContext.fetch(request)
            let grouped = Dictionary(grouping: transactions) { $0.category }
            
            var categoryData: [CategorySpending] = []
            let totalExpenses = transactions.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
            
            for (category, categoryTransactions) in grouped {
                guard let category = category else { continue }
                
                let categoryTotal = categoryTransactions.reduce(Decimal(0)) { sum, transaction in
                    sum + (transaction.amount as Decimal? ?? 0)
                }
                
                let percentage = totalExpenses > 0 ? Double(truncating: categoryTotal as NSNumber) / Double(truncating: totalExpenses as NSNumber) * 100 : 0
                
                let spending = CategorySpending(
                    categoryName: category.name ?? "Unknown",
                    amount: categoryTotal,
                    color: category.color ?? "#007AFF",
                    percentage: percentage,
                    transactionCount: categoryTransactions.count
                )
                
                categoryData.append(spending)
            }
            
            // Sort by amount descending
            categorySpending = categoryData.sorted { $0.amount > $1.amount }
            
        } catch {
            errorMessage = "Failed to load category spending: \(error.localizedDescription)"
        }
    }
    
    private func loadMonthlyTrends() {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .month, value: -5, to: now)!
        
        var trends: [MonthlyTrend] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        
        for i in 0..<6 {
            guard let monthStart = calendar.date(byAdding: .month, value: i, to: startDate),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { continue }
            
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@", monthStart as CVarArg, monthEnd as CVarArg)
            
            do {
                let transactions = try viewContext.fetch(request)
                
                let income = transactions.filter { $0.type == "income" }
                    .reduce(Decimal(0)) { sum, transaction in
                        sum + (transaction.amount as Decimal? ?? 0)
                    }
                
                let expenses = transactions.filter { $0.type == "expense" }
                    .reduce(Decimal(0)) { sum, transaction in
                        sum + (transaction.amount as Decimal? ?? 0)
                    }
                
                let trend = MonthlyTrend(
                    month: formatter.string(from: monthStart),
                    income: income,
                    expenses: expenses,
                    net: income - expenses
                )
                
                trends.append(trend)
                
            } catch {
                continue
            }
        }
        
        monthlyTrends = trends
    }
    
    private func loadIncomeVsExpenses(startDate: Date, endDate: Date) {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as CVarArg, endDate as CVarArg)
        
        do {
            let transactions = try viewContext.fetch(request)
            
            let income = transactions.filter { $0.type == "income" }
                .reduce(Decimal(0)) { sum, transaction in
                    sum + (transaction.amount as Decimal? ?? 0)
                }
            
            let expenses = transactions.filter { $0.type == "expense" }
                .reduce(Decimal(0)) { sum, transaction in
                    sum + (transaction.amount as Decimal? ?? 0)
                }
            
            let total = income + expenses
            
            incomeVsExpenses = IncomeExpenseData(
                totalIncome: income,
                totalExpenses: expenses,
                netAmount: income - expenses,
                incomePercentage: total > 0 ? Double(truncating: income as NSNumber) / Double(truncating: total as NSNumber) * 100 : 0,
                expensePercentage: total > 0 ? Double(truncating: expenses as NSNumber) / Double(truncating: total as NSNumber) * 100 : 0
            )
            
        } catch {
            errorMessage = "Failed to load income vs expenses: \(error.localizedDescription)"
        }
    }
    
    private func loadTopCategories(startDate: Date, endDate: Date) {
        let sortedCategories = categorySpending.prefix(5)
        
        topCategories = sortedCategories.compactMap { spending in
            // Find the category to get icon
            let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
            categoryRequest.predicate = NSPredicate(format: "name == %@", spending.categoryName)
            categoryRequest.fetchLimit = 1
            
            do {
                let categories = try viewContext.fetch(categoryRequest)
                guard let category = categories.first else { return nil }
                
                return TopCategory(
                    name: spending.categoryName,
                    amount: spending.amount,
                    color: spending.color,
                    icon: category.icon ?? "folder",
                    changeFromPrevious: nil // TODO: Calculate change from previous period
                )
            } catch {
                return nil
            }
        }
    }
    
    private func generateSpendingInsights(startDate: Date, endDate: Date) {
        var insights: [SpendingInsight] = []
        
        // High spending category insight
        if let topCategory = categorySpending.first, topCategory.percentage > 40 {
            insights.append(SpendingInsight(
                title: "High Spending Alert",
                description: "\(topCategory.categoryName) accounts for \(Int(topCategory.percentage))% of your expenses",
                type: .warning,
                icon: "exclamationmark.triangle.fill",
                color: .orange
            ))
        }
        
        // Positive net income insight
        if incomeVsExpenses.netAmount > 0 {
            insights.append(SpendingInsight(
                title: "Great Job!",
                description: "You saved \(incomeVsExpenses.netAmount.currencyFormatted) this period",
                type: .positive,
                icon: "checkmark.circle.fill",
                color: .green
            ))
        }
        
        // Budget comparison insight
        let budgetRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
        budgetRequest.predicate = NSPredicate(format: "isActive == YES")
        
        do {
            let budgets = try viewContext.fetch(budgetRequest)
            var overBudgetCount = 0
            
            for budget in budgets {
                guard let category = budget.category else { continue }
                
                if let spending = categorySpending.first(where: { $0.categoryName == category.name }) {
                    let budgetAmount = budget.amount as Decimal? ?? 0
                    if spending.amount > budgetAmount {
                        overBudgetCount += 1
                    }
                }
            }
            
            if overBudgetCount > 0 {
                insights.append(SpendingInsight(
                    title: "Budget Alert",
                    description: "You're over budget in \(overBudgetCount) categor\(overBudgetCount == 1 ? "y" : "ies")",
                    type: .warning,
                    icon: "chart.pie.fill",
                    color: .red
                ))
            }
            
        } catch {
            // Handle error silently for insights
        }
        
        spendingInsights = insights
    }
    
    func refreshData() {
        loadAnalytics()
    }
}