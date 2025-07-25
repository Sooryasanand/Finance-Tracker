//
//  SiriShortcutsService.swift
//  Finance Tracker
//
//  Created by Soorya Narayanan Sanand on 25/7/2025.
//

import Foundation
import Intents
import IntentsUI
import CoreData
import os.log

@MainActor
class SiriShortcutsService: ObservableObject {
    static let shared = SiriShortcutsService()
    
    // MARK: - Published Properties
    @Published var availableShortcuts: [INShortcut] = []
    @Published var isShortcutsEnabled = false
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "FinanceTracker", category: "SiriShortcutsService")
    private let coreDataStack = CoreDataStack.shared
    
    // MARK: - Shortcut Identifiers
    enum ShortcutType: String, CaseIterable {
        case addExpense = "addExpense"
        case addIncome = "addIncome"
        case checkBalance = "checkBalance"
        case viewRecentTransactions = "viewRecentTransactions"
        
        var title: String {
            switch self {
            case .addExpense:
                return "Add Expense"
            case .addIncome:
                return "Add Income"
            case .checkBalance:
                return "Check Balance"
            case .viewRecentTransactions:
                return "View Recent Transactions"
            }
        }
        
        var subtitle: String {
            switch self {
            case .addExpense:
                return "Quickly log an expense"
            case .addIncome:
                return "Quickly log income"
            case .checkBalance:
                return "Check your current balance"
            case .viewRecentTransactions:
                return "View your recent transactions"
            }
        }
        
        var icon: String {
            switch self {
            case .addExpense:
                return "minus.circle.fill"
            case .addIncome:
                return "plus.circle.fill"
            case .checkBalance:
                return "dollarsign.circle.fill"
            case .viewRecentTransactions:
                return "list.bullet"
            }
        }
    }
    
    // MARK: - Initialization
    private init() {
        setupShortcuts()
        checkShortcutsAvailability()
    }
    
    // MARK: - Public Methods
    
    func setupShortcuts() {
        guard #available(iOS 12.0, *) else {
            logger.warning("Siri Shortcuts not available on this iOS version")
            return
        }
        
        for shortcutType in ShortcutType.allCases {
            createShortcut(for: shortcutType)
        }
        
        logger.info("Siri Shortcuts setup completed")
    }
    
    func checkShortcutsAvailability() {
        guard #available(iOS 12.0, *) else {
            isShortcutsEnabled = false
            return
        }
        
        // Demo mode - always show as available for showcase
        DispatchQueue.main.async {
            self.isShortcutsEnabled = true
        }
        
        // Commented out for demo - would work with proper Siri entitlements
        /*
        INPreferences.requestSiriAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isShortcutsEnabled = status == .authorized
                self?.logger.info("Siri authorization status: \(status.rawValue)")
            }
        }
        */
    }
    
    func donateShortcut(for type: ShortcutType, with parameters: [String: Any] = [:]) {
        guard #available(iOS 12.0, *) else { return }
        
        let intent = createIntent(for: type, with: parameters)
        let shortcut = INShortcut(intent: intent)
        
        INInteraction(intent: intent, response: nil).donate { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to donate shortcut: \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully donated shortcut: \(type.rawValue)")
            }
        }
    }
    
    func handleShortcut(_ shortcut: INShortcut) -> Bool {
        guard #available(iOS 12.0, *) else { return false }
        
        // Handle different shortcut types
        if let intent = shortcut.intent {
            return handleIntent(intent)
        }
        
        return false
    }
    
    func getAvailableShortcuts() -> [INShortcut] {
        guard #available(iOS 12.0, *) else { return [] }
        
        var shortcuts: [INShortcut] = []
        
        for shortcutType in ShortcutType.allCases {
            let intent = createIntent(for: shortcutType)
            if let shortcut = INShortcut(intent: intent) {
                shortcuts.append(shortcut)
            }
        }
        
        return shortcuts
    }
    
    // MARK: - Private Methods
    
    @available(iOS 12.0, *)
    private func createShortcut(for type: ShortcutType) {
        let intent = createIntent(for: type)
        guard let shortcut = INShortcut(intent: intent) else { return }
        
        // Donate the shortcut to Siri
        INInteraction(intent: intent, response: nil).donate { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to create shortcut for \(type.rawValue): \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully created shortcut for \(type.rawValue)")
            }
        }
    }
    
    @available(iOS 12.0, *)
    private func createIntent(for type: ShortcutType, with parameters: [String: Any] = [:]) -> INIntent {
        switch type {
        case .addExpense:
            return createAddExpenseIntent(with: parameters)
        case .addIncome:
            return createAddIncomeIntent(with: parameters)
        case .checkBalance:
            return createCheckBalanceIntent()
        case .viewRecentTransactions:
            return createViewRecentTransactionsIntent()
        }
    }
    
    @available(iOS 12.0, *)
    private func createAddExpenseIntent(with parameters: [String: Any]) -> INIntent {
        // Create a custom intent for adding expenses
        let intent = INIntent()
        intent.suggestedInvocationPhrase = "Add expense"
        
        // Add parameters if available
        if let amount = parameters["amount"] as? Double {
            // Store amount for later use
        }
        
        if let category = parameters["category"] as? String {
            // Store category for later use
        }
        
        return intent
    }
    
    @available(iOS 12.0, *)
    private func createAddIncomeIntent(with parameters: [String: Any]) -> INIntent {
        let intent = INIntent()
        intent.suggestedInvocationPhrase = "Add income"
        return intent
    }
    
    @available(iOS 12.0, *)
    private func createCheckBalanceIntent() -> INIntent {
        let intent = INIntent()
        intent.suggestedInvocationPhrase = "Check my balance"
        return intent
    }
    
    @available(iOS 12.0, *)
    private func createViewRecentTransactionsIntent() -> INIntent {
        let intent = INIntent()
        intent.suggestedInvocationPhrase = "Show recent transactions"
        return intent
    }
    
    @available(iOS 12.0, *)
    private func handleIntent(_ intent: INIntent) -> Bool {
        // Handle the intent based on its type
        // This would typically involve navigating to the appropriate screen
        // or performing the requested action
        
        logger.info("Handling Siri intent: \(intent)")
        
        // For now, we'll just log the intent
        // In a real implementation, you would:
        // 1. Parse the intent parameters
        // 2. Navigate to the appropriate screen
        // 3. Pre-populate forms with intent data
        
        return true
    }
}

// MARK: - Extensions

extension SiriShortcutsService {
    func addQuickExpense(amount: Decimal, category: String, note: String? = nil) {
        let parameters: [String: Any] = [
            "amount": Double(truncating: amount as NSNumber),
            "category": category,
            "note": note ?? ""
        ]
        
        donateShortcut(for: .addExpense, with: parameters)
        
        // Also save the transaction
        saveQuickTransaction(amount: amount, category: category, note: note, type: "expense")
    }
    
    func addQuickIncome(amount: Decimal, category: String, note: String? = nil) {
        let parameters: [String: Any] = [
            "amount": Double(truncating: amount as NSNumber),
            "category": category,
            "note": note ?? ""
        ]
        
        donateShortcut(for: .addIncome, with: parameters)
        
        // Also save the transaction
        saveQuickTransaction(amount: amount, category: category, note: note, type: "income")
    }
    
    private func saveQuickTransaction(amount: Decimal, category: String, note: String?, type: String) {
        let context = coreDataStack.context
        
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.amount = amount as NSDecimalNumber
        transaction.type = type
        transaction.note = note
        transaction.date = Date()
        
        // Find or create category
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "name == %@", category)
        
        do {
            let existingCategories = try context.fetch(categoryRequest)
            if let existingCategory = existingCategories.first {
                transaction.category = existingCategory
            } else {
                // Create new category
                let newCategory = Category(context: context)
                newCategory.id = UUID()
                newCategory.name = category
                newCategory.color = "#007AFF"
                transaction.category = newCategory
            }
            
            try context.save()
            logger.info("Quick transaction saved: \(type) - \(amount)")
        } catch {
            logger.error("Failed to save quick transaction: \(error.localizedDescription)")
        }
    }
} 
