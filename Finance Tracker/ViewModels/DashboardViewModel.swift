import Foundation
import CoreData
import Combine

class DashboardViewModel: ObservableObject {
    @Published var totalBalance: Decimal = 0.0
    @Published var totalIncome: Decimal = 0.0
    @Published var totalExpenses: Decimal = 0.0
    @Published var recentTransactions: [Transaction] = []
    @Published var budgetOverviews: [BudgetOverview] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    
    struct BudgetOverview {
        let id: UUID
        let name: String
        let spent: Decimal
        let limit: Decimal
        let color: String
        let progress: Double
    }
    
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
        loadData()
    }
    
    private func setupBindings() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.loadData()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadData() {
        loadBalanceData()
        loadRecentTransactions()
        loadBudgetOverviews()
    }
    
    private func loadBalanceData() {
        let currentMonth = Calendar.current.dateInterval(of: .month, for: Date())
        guard let startDate = currentMonth?.start,
              let endDate = currentMonth?.end else { return }
        
        let predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as CVarArg, endDate as CVarArg)
        
        // Calculate income
        let incomeRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        incomeRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            NSPredicate(format: "type == %@", "income")
        ])
        
        // Calculate expenses
        let expenseRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        expenseRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            NSPredicate(format: "type == %@", "expense")
        ])
        
        do {
            let incomeTransactions = try viewContext.fetch(incomeRequest)
            let expenseTransactions = try viewContext.fetch(expenseRequest)
            
            let income = incomeTransactions.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
            
            let expenses = expenseTransactions.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
            
            DispatchQueue.main.async {
                self.totalIncome = income
                self.totalExpenses = expenses
                self.totalBalance = income - expenses
            }
        } catch {
            print("Failed to load balance data: \(error)")
        }
    }
    
    private func loadRecentTransactions() {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        request.fetchLimit = 5
        
        do {
            let transactions = try viewContext.fetch(request)
            DispatchQueue.main.async {
                self.recentTransactions = transactions
            }
        } catch {
            print("Failed to load recent transactions: \(error)")
        }
    }
    
    private func loadBudgetOverviews() {
        let currentMonth = Calendar.current.dateInterval(of: .month, for: Date())
        guard let startDate = currentMonth?.start,
              let endDate = currentMonth?.end else { return }
        
        let budgetRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
        budgetRequest.predicate = NSPredicate(format: "isActive == YES")
        
        do {
            let budgets = try viewContext.fetch(budgetRequest)
            var overviews: [BudgetOverview] = []
            
            for budget in budgets {
                guard let category = budget.category else { continue }
                
                // Calculate spent amount for this category in current month
                let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
                transactionRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "date >= %@ AND date < %@", startDate as CVarArg, endDate as CVarArg),
                    NSPredicate(format: "category == %@", category),
                    NSPredicate(format: "type == %@", "expense")
                ])
                
                let transactions = try viewContext.fetch(transactionRequest)
                let spent = transactions.reduce(Decimal(0)) { sum, transaction in
                    sum + (transaction.amount as Decimal? ?? 0)
                }
                
                let budgetAmount = budget.amount as Decimal? ?? 0
                let progress = budgetAmount > 0 ? min(Double(truncating: spent as NSNumber) / Double(truncating: budgetAmount as NSNumber), 1.0) : 0.0
                
                let overview = BudgetOverview(
                    id: budget.id ?? UUID(),
                    name: budget.name ?? "Unknown",
                    spent: spent,
                    limit: budgetAmount,
                    color: category.color ?? "#007AFF",
                    progress: progress
                )
                
                overviews.append(overview)
            }
            
            DispatchQueue.main.async {
                self.budgetOverviews = overviews
            }
        } catch {
            print("Failed to load budget overviews: \(error)")
        }
    }
    
    func refreshData() {
        loadData()
    }
}