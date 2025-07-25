import Foundation
import CoreData
import Combine

class TransactionsViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var filteredTransactions: [Transaction] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: TransactionFilter = .all
    @Published var selectedDateRange: DateRange = .thisMonth
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    
    enum TransactionFilter: String, CaseIterable {
        case all = "all"
        case income = "income"
        case expense = "expense"
        
        var displayName: String {
            switch self {
            case .all: return "All"
            case .income: return "Income"
            case .expense: return "Expenses"
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .income: return "arrow.up.circle.fill"
            case .expense: return "arrow.down.circle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .all: return "#007AFF"
            case .income: return "#34C759"
            case .expense: return "#FF3B30"
            }
        }
    }
    
    enum DateRange: String, CaseIterable {
        case today = "today"
        case thisWeek = "thisWeek"
        case thisMonth = "thisMonth"
        case last30Days = "last30Days"
        case last90Days = "last90Days"
        case thisYear = "thisYear"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .today: return "Today"
            case .thisWeek: return "This Week"
            case .thisMonth: return "This Month"
            case .last30Days: return "Last 30 Days"
            case .last90Days: return "Last 90 Days"
            case .thisYear: return "This Year"
            case .custom: return "Custom Range"
            }
        }
        
        var dateRange: (Date, Date) {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .today:
                let startOfDay = calendar.startOfDay(for: now)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                return (startOfDay, endOfDay)
                
            case .thisWeek:
                let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
                return (weekInterval.start, weekInterval.end)
                
            case .thisMonth:
                let monthInterval = calendar.dateInterval(of: .month, for: now)!
                return (monthInterval.start, monthInterval.end)
                
            case .last30Days:
                let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
                return (calendar.startOfDay(for: thirtyDaysAgo), now)
                
            case .last90Days:
                let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now)!
                return (calendar.startOfDay(for: ninetyDaysAgo), now)
                
            case .thisYear:
                let yearInterval = calendar.dateInterval(of: .year, for: now)!
                return (yearInterval.start, yearInterval.end)
                
            case .custom:
                // Default to this month for custom, will be overridden by user selection
                let monthInterval = calendar.dateInterval(of: .month, for: now)!
                return (monthInterval.start, monthInterval.end)
            }
        }
    }
    
    // Summary data
    @Published var totalIncome: Decimal = 0
    @Published var totalExpenses: Decimal = 0
    @Published var netAmount: Decimal = 0
    @Published var transactionCount: Int = 0
    
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
        loadTransactions()
    }
    
    private func setupBindings() {
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.loadTransactions()
                }
            }
            .store(in: &cancellables)
        
        // Filter transactions when search text or filters change
        Publishers.CombineLatest4($transactions, $searchText, $selectedFilter, $selectedDateRange)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] transactions, searchText, filter, dateRange in
                self?.filterTransactions(transactions: transactions, searchText: searchText, filter: filter, dateRange: dateRange)
            }
            .store(in: &cancellables)
    }
    
    func loadTransactions() {
        isLoading = true
        
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        
        do {
            transactions = try viewContext.fetch(request)
            calculateSummary()
        } catch {
            errorMessage = "Failed to load transactions: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func filterTransactions(transactions: [Transaction], searchText: String, filter: TransactionFilter, dateRange: DateRange) {
        var filtered = transactions
        
        // Apply date range filter
        let (startDate, endDate) = dateRange.dateRange
        filtered = filtered.filter { transaction in
            guard let transactionDate = transaction.date else { return false }
            return transactionDate >= startDate && transactionDate < endDate
        }
        
        // Apply type filter
        switch filter {
        case .all:
            break // No additional filtering
        case .income:
            filtered = filtered.filter { $0.type == "income" }
        case .expense:
            filtered = filtered.filter { $0.type == "expense" }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { transaction in
                let categoryName = transaction.category?.name?.lowercased() ?? ""
                let notes = transaction.notes?.lowercased() ?? ""
                let searchLower = searchText.lowercased()
                
                return categoryName.contains(searchLower) || notes.contains(searchLower)
            }
        }
        
        filteredTransactions = filtered
        calculateFilteredSummary()
    }
    
    private func calculateSummary() {
        let income = transactions.filter { $0.type == "income" }
            .reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
        
        let expenses = transactions.filter { $0.type == "expense" }
            .reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
        
        totalIncome = income
        totalExpenses = expenses
        netAmount = income - expenses
        transactionCount = transactions.count
    }
    
    private func calculateFilteredSummary() {
        let income = filteredTransactions.filter { $0.type == "income" }
            .reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
        
        let expenses = filteredTransactions.filter { $0.type == "expense" }
            .reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
        
        totalIncome = income
        totalExpenses = expenses
        netAmount = income - expenses
        transactionCount = filteredTransactions.count
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        viewContext.delete(transaction)
        CoreDataStack.shared.save()
    }
    
    func refreshData() {
        loadTransactions()
    }
    
    // Group transactions by date for better organization
    func groupedTransactions() -> [(String, [Transaction])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            guard let date = transaction.date else { return "Unknown Date" }
            
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "Today"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else {
                return formatter.string(from: date)
            }
        }
        
        return grouped.sorted { first, second in
            if first.key == "Today" { return true }
            if second.key == "Today" { return false }
            if first.key == "Yesterday" { return true }
            if second.key == "Yesterday" { return false }
            
            // For other dates, sort by the first transaction's date
            guard let firstDate = first.value.first?.date,
                  let secondDate = second.value.first?.date else {
                return false
            }
            return firstDate > secondDate
        }
    }
}