import Foundation
import CoreData
import Combine

class AddBudgetViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var amount: String = ""
    @Published var selectedCategory: Category?
    @Published var selectedPeriod: BudgetPeriod = .monthly
    @Published var startDate: Date = Date()
    @Published var endDate: Date?
    @Published var isActive: Bool = true
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    enum BudgetPeriod: String, CaseIterable {
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"
        case quarterly = "quarterly"
        case yearly = "yearly"
        
        var displayName: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .quarterly: return "Quarterly"
            case .yearly: return "Yearly"
            }
        }
        
        var icon: String {
            switch self {
            case .daily: return "calendar"
            case .weekly: return "calendar.badge.clock"
            case .monthly: return "calendar.badge.plus"
            case .quarterly: return "calendar.badge.exclamationmark"
            case .yearly: return "calendar.badge.checkmark"
            }
        }
    }
    
    var expenseCategories: [Category] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@", "expense")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            return []
        }
    }
    
    var isFormValid: Bool {
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !amount.isEmpty &&
               Double(amount) != nil &&
               Double(amount)! > 0 &&
               selectedCategory != nil
    }
    
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
    }
    
    private func setupBindings() {
        // Update end date when period or start date changes
        Publishers.CombineLatest($selectedPeriod, $startDate)
            .sink { [weak self] period, startDate in
                self?.updateEndDate(for: period, startDate: startDate)
            }
            .store(in: &cancellables)
    }
    
    private func updateEndDate(for period: BudgetPeriod, startDate: Date) {
        let calendar = Calendar.current
        
        switch period {
        case .daily:
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate)
        case .weekly:
            endDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate)
        case .monthly:
            endDate = calendar.date(byAdding: .month, value: 1, to: startDate)
        case .quarterly:
            endDate = calendar.date(byAdding: .month, value: 3, to: startDate)
        case .yearly:
            endDate = calendar.date(byAdding: .year, value: 1, to: startDate)
        }
    }
    
    func saveBudget(completion: @escaping (Bool) -> Void) {
        guard isFormValid else {
            errorMessage = "Please fill in all required fields"
            completion(false)
            return
        }
        
        guard let amountValue = Double(amount) else {
            errorMessage = "Please enter a valid amount"
            completion(false)
            return
        }
        
        guard let category = selectedCategory else {
            errorMessage = "Please select a category"
            completion(false)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Check for existing active budget for this category and period
        let existingBudgetRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
        existingBudgetRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "category == %@", category),
            NSPredicate(format: "period == %@", selectedPeriod.rawValue),
            NSPredicate(format: "isActive == YES")
        ])
        
        do {
            let existingBudgets = try viewContext.fetch(existingBudgetRequest)
            if !existingBudgets.isEmpty {
                errorMessage = "An active budget for this category and period already exists"
                isLoading = false
                completion(false)
                return
            }
        } catch {
            errorMessage = "Failed to check existing budgets: \(error.localizedDescription)"
            isLoading = false
            completion(false)
            return
        }
        
        // Get current user
        let userRequest: NSFetchRequest<User> = User.fetchRequest()
        userRequest.fetchLimit = 1
        
        do {
            let users = try viewContext.fetch(userRequest)
            guard let currentUser = users.first else {
                errorMessage = "No user found"
                isLoading = false
                completion(false)
                return
            }
            
            // Create new budget
            let budget = Budget(context: viewContext)
            budget.id = UUID()
            budget.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            budget.amount = NSDecimalNumber(value: amountValue)
            budget.period = selectedPeriod.rawValue
            budget.startDate = startDate
            budget.endDate = endDate
            budget.isActive = isActive
            budget.category = category
            budget.user = currentUser
            budget.createdAt = Date()
            budget.updatedAt = Date()
            
            try viewContext.save()
            
            DispatchQueue.main.async {
                self.isLoading = false
                completion(true)
            }
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to save budget: \(error.localizedDescription)"
                self.isLoading = false
                completion(false)
            }
        }
    }
    
    func reset() {
        name = ""
        amount = ""
        selectedCategory = nil
        selectedPeriod = .monthly
        startDate = Date()
        endDate = nil
        isActive = true
        errorMessage = nil
    }
}