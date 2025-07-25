import Foundation
import CoreData
import Combine

class BudgetsViewModel: ObservableObject {
    @Published var budgets: [Budget] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddBudget = false
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
        loadBudgets()
    }
    
    private func setupBindings() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.loadBudgets()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadBudgets() {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Budget.isActive, ascending: false),
            NSSortDescriptor(keyPath: \Budget.name, ascending: true)
        ]
        
        do {
            budgets = try viewContext.fetch(request)
        } catch {
            errorMessage = "Failed to load budgets: \(error.localizedDescription)"
        }
    }
    
    func deleteBudget(_ budget: Budget) {
        viewContext.delete(budget)
        CoreDataStack.shared.save()
    }
    
    func toggleBudgetStatus(_ budget: Budget) {
        budget.isActive.toggle()
        budget.updatedAt = Date()
        CoreDataStack.shared.save()
    }
    
    func getBudgetProgress(for budget: Budget) -> BudgetProgress {
        guard let category = budget.category else {
            return BudgetProgress(spent: 0, limit: budget.amount as Decimal? ?? 0, progress: 0)
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate date range based on budget period
        let (startDate, endDate) = getBudgetPeriodDates(for: budget, from: now)
        
        // Fetch transactions for this category in the current period
        let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        transactionRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date >= %@ AND date <= %@", startDate as CVarArg, endDate as CVarArg),
            NSPredicate(format: "category == %@", category),
            NSPredicate(format: "type == %@", "expense")
        ])
        
        do {
            let transactions = try viewContext.fetch(transactionRequest)
            let spent = transactions.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
            
            let limit = budget.amount as Decimal? ?? 0
            let progress = limit > 0 ? min(Double(truncating: spent as NSNumber) / Double(truncating: limit as NSNumber), 1.0) : 0.0
            
            return BudgetProgress(spent: spent, limit: limit, progress: progress)
        } catch {
            return BudgetProgress(spent: 0, limit: budget.amount as Decimal? ?? 0, progress: 0)
        }
    }
    
    private func getBudgetPeriodDates(for budget: Budget, from date: Date) -> (Date, Date) {
        let calendar = Calendar.current
        
        switch budget.period {
        case "daily":
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return (startOfDay, endOfDay)
            
        case "weekly":
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            let endOfWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek)!
            return (startOfWeek, endOfWeek)
            
        case "monthly":
            let startOfMonth = calendar.dateInterval(of: .month, for: date)!.start
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            return (startOfMonth, endOfMonth)
            
        case "quarterly":
            let startOfQuarter = calendar.dateInterval(of: .quarter, for: date)!.start
            let endOfQuarter = calendar.date(byAdding: .quarter, value: 1, to: startOfQuarter)!
            return (startOfQuarter, endOfQuarter)
            
        case "yearly":
            let startOfYear = calendar.dateInterval(of: .year, for: date)!.start
            let endOfYear = calendar.date(byAdding: .year, value: 1, to: startOfYear)!
            return (startOfYear, endOfYear)
            
        default:
            // Default to monthly
            let startOfMonth = calendar.dateInterval(of: .month, for: date)!.start
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            return (startOfMonth, endOfMonth)
        }
    }
}

struct BudgetProgress {
    let spent: Decimal
    let limit: Decimal
    let progress: Double
    
    var remaining: Decimal {
        return limit - spent
    }
    
    var isOverBudget: Bool {
        return spent > limit
    }
    
    var progressColor: String {
        if progress >= 1.0 {
            return "#FF3B30" // Red
        } else if progress >= 0.8 {
            return "#FF9500" // Orange
        } else if progress >= 0.6 {
            return "#FFCC00" // Yellow
        } else {
            return "#34C759" // Green
        }
    }
}