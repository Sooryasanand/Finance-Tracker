import Foundation
import CoreData
import Combine

class TransactionViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var filteredTransactions: [Transaction] = []
    @Published var searchText: String = "" {
        didSet {
            filterTransactions()
        }
    }
    @Published var selectedFilter: TransactionFilter = .all {
        didSet {
            filterTransactions()
        }
    }
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case income = "Income"
        case expense = "Expense"
        
        var systemImage: String {
            switch self {
            case .all: return "list.bullet"
            case .income: return "arrow.up.circle.fill"
            case .expense: return "arrow.down.circle.fill"
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
        loadTransactions()
    }
    
    private func setupBindings() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.loadTransactions()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadTransactions() {
        isLoading = true
        errorMessage = nil
        
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        
        do {
            let fetchedTransactions = try viewContext.fetch(request)
            DispatchQueue.main.async {
                self.transactions = fetchedTransactions
                self.filterTransactions()
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to load transactions: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func filterTransactions() {
        filteredTransactions = transactions.filter { transaction in
            let matchesSearch = searchText.isEmpty ||
                transaction.category?.name?.localizedCaseInsensitiveContains(searchText) == true ||
                transaction.notes?.localizedCaseInsensitiveContains(searchText) == true
            
            let matchesFilter = selectedFilter == .all || transaction.type == selectedFilter.rawValue.lowercased()
            
            return matchesSearch && matchesFilter
        }
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        viewContext.delete(transaction)
        
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Failed to delete transaction: \(error.localizedDescription)"
        }
    }
    
    func groupedTransactions() -> [(key: String, value: [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: transaction.date ?? Date())
        }
        
        return grouped.sorted { first, second in
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let firstDate = formatter.date(from: first.key) ?? Date.distantPast
            let secondDate = formatter.date(from: second.key) ?? Date.distantPast
            return firstDate > secondDate
        }
    }
    
    func refreshTransactions() {
        loadTransactions()
    }
}