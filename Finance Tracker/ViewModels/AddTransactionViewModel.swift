import Foundation
import CoreData
import Combine

class AddTransactionViewModel: ObservableObject {
    @Published var amount: String = ""
    @Published var selectedType: TransactionType = .expense
    @Published var selectedCategory: Category?
    @Published var notes: String = ""
    @Published var date: Date = Date()
    @Published var categories: [Category] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    enum TransactionType: String, CaseIterable {
        case income = "income"
        case expense = "expense"
        
        var displayName: String {
            switch self {
            case .income: return "Income"
            case .expense: return "Expense"
            }
        }
        
        var color: Color {
            switch self {
            case .income: return .green
            case .expense: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .income: return "arrow.up.circle.fill"
            case .expense: return "arrow.down.circle.fill"
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let viewContext: NSManagedObjectContext
    
    var filteredCategories: [Category] {
        categories.filter { $0.type == selectedType.rawValue }
    }
    
    var isFormValid: Bool {
        !amount.isEmpty &&
        Double(amount) != nil &&
        Double(amount)! > 0 &&
        selectedCategory != nil
    }
    
    init(viewContext: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.viewContext = viewContext
        setupBindings()
        loadCategories()
    }
    
    private func setupBindings() {
        $selectedType
            .sink { [weak self] _ in
                self?.selectedCategory = nil
            }
            .store(in: &cancellables)
    }
    
    func loadCategories() {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        
        do {
            let fetchedCategories = try viewContext.fetch(request)
            DispatchQueue.main.async {
                self.categories = fetchedCategories
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to load categories: \(error.localizedDescription)"
            }
        }
    }
    
    func saveTransaction(completion: @escaping (Bool) -> Void) {
        guard let amountValue = Double(amount),
              let category = selectedCategory else {
            errorMessage = "Please fill in all required fields"
            completion(false)
            return
        }
        
        guard amountValue > 0 else {
            errorMessage = "Amount must be greater than zero"
            completion(false)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let transaction = Transaction(context: viewContext)
        transaction.id = UUID()
        transaction.amount = NSDecimalNumber(value: amountValue).decimalValue
        transaction.type = selectedType.rawValue
        transaction.category = category
        transaction.notes = notes.isEmpty ? nil : notes
        transaction.date = date
        transaction.createdAt = Date()
        transaction.updatedAt = Date()
        
        do {
            try viewContext.save()
            DispatchQueue.main.async {
                self.isLoading = false
                self.resetForm()
                completion(true)
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Failed to save transaction: \(error.localizedDescription)"
                completion(false)
            }
        }
    }
    
    private func resetForm() {
        amount = ""
        selectedCategory = nil
        notes = ""
        date = Date()
    }
    
    func validateAmount(_ input: String) -> Bool {
        guard let value = Double(input) else { return false }
        return value > 0 && value <= 999999.99
    }
}

import SwiftUI

extension AddTransactionViewModel.TransactionType {
    var color: Color {
        switch self {
        case .income: return .green
        case .expense: return .red
        }
    }
}