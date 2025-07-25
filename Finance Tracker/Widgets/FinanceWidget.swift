//
//  FinanceWidget.swift
//  Finance Tracker
//
//  Created by Soorya Narayanan Sanand on 25/7/2025.
//

import WidgetKit
import SwiftUI
import CoreData

struct FinanceWidget: Widget {
    let kind: String = "FinanceWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceWidgetProvider()) { entry in
            FinanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Finance Tracker")
        .description("Track your spending and budget status")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FinanceWidgetEntry: TimelineEntry {
    let date: Date
    let balance: Decimal
    let income: Decimal
    let expenses: Decimal
    let budgetStatus: [BudgetStatus]
    let isDataAvailable: Bool
    let lastUpdated: Date
}

struct BudgetStatus {
    let name: String
    let spent: Decimal
    let limit: Decimal
    let progress: Double
    let isOverBudget: Bool
    let color: String
}

struct FinanceWidgetProvider: TimelineProvider {
    let coreDataStack = CoreDataStack.shared
    
    func placeholder(in context: Context) -> FinanceWidgetEntry {
        FinanceWidgetEntry(
            date: Date(),
            balance: 1250.00,
            income: 3000.00,
            expenses: 1750.00,
            budgetStatus: [
                BudgetStatus(name: "Food", spent: 450, limit: 500, progress: 0.9, isOverBudget: false, color: "#FF6B6B"),
                BudgetStatus(name: "Transport", spent: 200, limit: 300, progress: 0.67, isOverBudget: false, color: "#4ECDC4")
            ],
            isDataAvailable: true,
            lastUpdated: Date()
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (FinanceWidgetEntry) -> Void) {
        let entry = FinanceWidgetEntry(
            date: Date(),
            balance: 1250.00,
            income: 3000.00,
            expenses: 1750.00,
            budgetStatus: [
                BudgetStatus(name: "Food", spent: 450, limit: 500, progress: 0.9, isOverBudget: false, color: "#FF6B6B"),
                BudgetStatus(name: "Transport", spent: 200, limit: 300, progress: 0.67, isOverBudget: false, color: "#4ECDC4")
            ],
            isDataAvailable: true,
            lastUpdated: Date()
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceWidgetEntry>) -> Void) {
        Task {
            let currentDate = Date()
            let entry = await loadWidgetData()
            
            // Update every 30 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            completion(timeline)
        }
    }
    
    private func loadWidgetData() async -> FinanceWidgetEntry {
        let context = coreDataStack.context
        
        // Calculate current month's data
        let currentMonth = Calendar.current.dateInterval(of: .month, for: Date())
        guard let startDate = currentMonth?.start,
              let endDate = currentMonth?.end else {
            return createEmptyEntry()
        }
        
        let predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as CVarArg, endDate as CVarArg)
        
        // Calculate income and expenses
        let incomeRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        incomeRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            NSPredicate(format: "type == %@", "income")
        ])
        
        let expenseRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        expenseRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            NSPredicate(format: "type == %@", "expense")
        ])
        
        do {
            let incomeTransactions = try context.fetch(incomeRequest)
            let expenseTransactions = try context.fetch(expenseRequest)
            
            let income = incomeTransactions.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
            
            let expenses = expenseTransactions.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
            
            let balance = income - expenses
            
            // Load budget status
            let budgetStatus = await loadBudgetStatus(context: context, startDate: startDate, endDate: endDate)
            
            return FinanceWidgetEntry(
                date: Date(),
                balance: balance,
                income: income,
                expenses: expenses,
                budgetStatus: budgetStatus,
                isDataAvailable: true,
                lastUpdated: Date()
            )
        } catch {
            return createEmptyEntry()
        }
    }
    
    private func loadBudgetStatus(context: NSManagedObjectContext, startDate: Date, endDate: Date) async -> [BudgetStatus] {
        let budgetRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
        budgetRequest.predicate = NSPredicate(format: "isActive == YES")
        
        do {
            let budgets = try context.fetch(budgetRequest)
            var budgetStatus: [BudgetStatus] = []
            
            for budget in budgets.prefix(3) { // Limit to 3 budgets for widget
                guard let category = budget.category else { continue }
                
                // Calculate spent amount for this category
                let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                transactionRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "date >= %@ AND date < %@", startDate as CVarArg, endDate as CVarArg),
                    NSPredicate(format: "category == %@", category),
                    NSPredicate(format: "type == %@", "expense")
                ])
                
                let transactions = try context.fetch(transactionRequest)
                let spent = transactions.reduce(Decimal(0)) { sum, transaction in
                    sum + (transaction.amount as Decimal? ?? 0)
                }
                
                let limit = budget.amount as Decimal? ?? 0
                let progress = limit > 0 ? min(Double(truncating: (spent / limit) as NSNumber), 1.0) : 0.0
                let isOverBudget = spent > limit
                
                let status = BudgetStatus(
                    name: budget.name ?? "Unknown",
                    spent: spent,
                    limit: limit,
                    progress: progress,
                    isOverBudget: isOverBudget,
                    color: category.color ?? "#007AFF"
                )
                
                budgetStatus.append(status)
            }
            
            return budgetStatus
        } catch {
            return []
        }
    }
    
    private func createEmptyEntry() -> FinanceWidgetEntry {
        FinanceWidgetEntry(
            date: Date(),
            balance: 0,
            income: 0,
            expenses: 0,
            budgetStatus: [],
            isDataAvailable: false,
            lastUpdated: Date()
        )
    }
}

struct FinanceWidgetEntryView: View {
    var entry: FinanceWidgetEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct SmallWidgetView: View {
    let entry: FinanceWidgetEntry
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.lastUpdated.timeAgoDisplay)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(entry.balance.currencyFormatted)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(entry.balance >= 0 ? .primary : .red)
            
            Spacer()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Income")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(entry.income.currencyFormatted)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Expenses")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(entry.expenses.currencyFormatted)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

struct MediumWidgetView: View {
    let entry: FinanceWidgetEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Balance section
            VStack(alignment: .leading, spacing: 8) {
                Text("Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(entry.balance.currencyFormatted)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(entry.balance >= 0 ? .primary : .red)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Income")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(entry.income.currencyFormatted)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Expenses")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(entry.expenses.currencyFormatted)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Divider()
            
            // Budget section
            VStack(alignment: .leading, spacing: 8) {
                Text("Budgets")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if entry.budgetStatus.isEmpty {
                    Text("No active budgets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entry.budgetStatus.prefix(2), id: \.name) { budget in
                        BudgetProgressRow(budget: budget)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

struct LargeWidgetView: View {
    let entry: FinanceWidgetEntry
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Finance Tracker")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.lastUpdated.timeAgoDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Balance card
            VStack(spacing: 8) {
                Text("Current Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(entry.balance.currencyFormatted)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(entry.balance >= 0 ? .primary : .red)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Income")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(entry.income.currencyFormatted)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Expenses")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(entry.expenses.currencyFormatted)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Budget status
            VStack(alignment: .leading, spacing: 8) {
                Text("Budget Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if entry.budgetStatus.isEmpty {
                    Text("No active budgets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entry.budgetStatus, id: \.name) { budget in
                        BudgetProgressRow(budget: budget)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

struct BudgetProgressRow: View {
    let budget: BudgetStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(budget.name)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(budget.spent.currencyFormatted) / \(budget.limit.currencyFormatted)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: budget.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: budget.isOverBudget ? .red : .blue))
                .scaleEffect(x: 1, y: 0.5, anchor: .center)
        }
    }
}

// MARK: - Extensions

extension Date {
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Widget Bundle

struct FinanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        FinanceWidget()
    }
} 