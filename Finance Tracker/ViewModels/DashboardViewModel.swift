import Foundation
import CoreData
import Combine
import os.log

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var totalBalance: Decimal = 0.0
    @Published var totalIncome: Decimal = 0.0
    @Published var totalExpenses: Decimal = 0.0
    @Published var recentTransactions: [Transaction] = []
    @Published var budgetOverviews: [BudgetOverview] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    private let logger = Logger(subsystem: "FinanceTracker", category: "DashboardViewModel")
    private var lastRefreshDate: Date = Date()
    
    // MARK: - Data Models
    struct BudgetOverview: Identifiable {
        let id: UUID
        let name: String
        let spent: Decimal
        let limit: Decimal
        let color: String
        let progress: Double
        let remaining: Decimal
        let isOverBudget: Bool
        
        init(budget: Budget) {
            self.id = budget.id ?? UUID()
            self.name = budget.name ?? "Unknown"
            self.limit = budget.amount as Decimal? ?? 0
            self.spent = budget.spent as Decimal? ?? 0
            self.color = budget.category?.color ?? "#007AFF"
            self.remaining = self.limit - self.spent
            self.isOverBudget = self.spent > self.limit
            self.progress = self.limit > 0 ? min(Double(truncating: (self.spent / self.limit) as NSNumber), 1.0) : 0.0
        }
    }
    
    // MARK: - Initialization
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
        loadData()
    }
    
    // MARK: - Public Methods
    
    func loadData() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await loadBalanceData()
                try await loadRecentTransactions()
                try await loadBudgetOverviews()
                
                lastRefreshDate = Date()
                logger.info("Dashboard data loaded successfully")
            } catch {
                logger.error("Failed to load dashboard data: \(error.localizedDescription)")
                errorMessage = "Failed to load data: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
    
    func refreshData() {
        loadData()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleDataChange()
                }
            }
            .store(in: &cancellables)
        
        // Listen for CloudKit sync status changes
        NotificationCenter.default.publisher(for: .cloudKitSyncStatusChanged)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleSyncStatusChange()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleDataChange() {
        // Only refresh if data has changed significantly
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshDate)
        if timeSinceLastRefresh > 1.0 { // Debounce rapid changes
            loadData()
        }
    }
    
    private func handleSyncStatusChange() {
        // Refresh data when sync completes
        loadData()
    }
    
    private func loadBalanceData() async throws {
        let currentMonth = Calendar.current.dateInterval(of: .month, for: Date())
        guard let startDate = currentMonth?.start,
              let endDate = currentMonth?.end else {
            throw DashboardError.invalidDateRange
        }
        
        let predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as CVarArg, endDate as CVarArg)
        
        // Calculate income
        let incomeRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        incomeRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            NSPredicate(format: "type == %@", TransactionType.income.rawValue)
        ])
        
        // Calculate expenses
        let expenseRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        expenseRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            NSPredicate(format: "type == %@", TransactionType.expense.rawValue)
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
            
            self.totalIncome = income
            self.totalExpenses = expenses
            self.totalBalance = income - expenses
            
            logger.debug("Balance data loaded - Income: \(income), Expenses: \(expenses), Balance: \(self.totalBalance)")
        } catch {
            logger.error("Failed to fetch balance data: \(error.localizedDescription)")
            throw DashboardError.failedToFetchBalanceData(error)
        }
    }
    
    private func loadRecentTransactions() async throws {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        request.fetchLimit = 10
        
        do {
            let transactions = try viewContext.fetch(request)
            self.recentTransactions = transactions
            logger.debug("Loaded \(transactions.count) recent transactions")
        } catch {
            logger.error("Failed to fetch recent transactions: \(error.localizedDescription)")
            throw DashboardError.failedToFetchTransactions(error)
        }
    }
    
    private func loadBudgetOverviews() async throws {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Budget.name, ascending: true)]
        
        do {
            let budgets = try viewContext.fetch(request)
            self.budgetOverviews = budgets.map { BudgetOverview(budget: $0) }
            logger.debug("Loaded \(budgets.count) budget overviews")
        } catch {
            logger.error("Failed to fetch budgets: \(error.localizedDescription)")
            throw DashboardError.failedToFetchBudgets(error)
        }
    }
}

// MARK: - Enums

enum DashboardError: LocalizedError {
    case invalidDateRange
    case failedToFetchBalanceData(Error)
    case failedToFetchTransactions(Error)
    case failedToFetchBudgets(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Invalid date range for calculations"
        case .failedToFetchBalanceData(let error):
            return "Failed to fetch balance data: \(error.localizedDescription)"
        case .failedToFetchTransactions(let error):
            return "Failed to fetch transactions: \(error.localizedDescription)"
        case .failedToFetchBudgets(let error):
            return "Failed to fetch budgets: \(error.localizedDescription)"
        }
    }
}

enum TransactionType: String, CaseIterable {
    case income = "income"
    case expense = "expense"
    
    var displayName: String {
        switch self {
        case .income:
            return "Income"
        case .expense:
            return "Expense"
        }
    }
    
    var icon: String {
        switch self {
        case .income:
            return "arrow.down.circle.fill"
        case .expense:
            return "arrow.up.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .income:
            return "green"
        case .expense:
            return "red"
        }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let cloudKitSyncStatusChanged = Notification.Name("cloudKitSyncStatusChanged")
}