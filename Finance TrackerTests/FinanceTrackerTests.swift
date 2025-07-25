//
//  FinanceTrackerTests.swift
//  Finance Tracker
//
//  Created by Soorya Narayanan Sanand on 25/7/2025.
//

import XCTest
import CoreData
import Combine
@testable import Finance_Tracker

final class FinanceTrackerTests: XCTestCase {
    
    // MARK: - Properties
    var coreDataStack: CoreDataStack!
    var context: NSManagedObjectContext!
    var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create in-memory Core Data stack for testing
        coreDataStack = CoreDataStack.shared
        context = coreDataStack.context
        cancellables = Set<AnyCancellable>()
        
        // Clear any existing data
        try clearAllData()
    }
    
    override func tearDownWithError() throws {
        try clearAllData()
        cancellables = nil
        context = nil
        coreDataStack = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Helper Methods
    
    private func clearAllData() throws {
        let entities = coreDataStack.persistentContainer.managedObjectModel.entities
        
        for entity in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entity.name!)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try context.execute(deleteRequest)
        }
        
        try context.save()
    }
    
    private func createTestCategory(name: String = "Test Category", color: String = "#007AFF") -> Category {
        let category = Category(context: context)
        category.id = UUID()
        category.name = name
        category.color = color
        category.icon = "tag"
        return category
    }
    
    private func createTestTransaction(
        amount: Decimal = 100.0,
        type: String = "expense",
        category: Category? = nil,
        date: Date = Date(),
        note: String? = nil
    ) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.id = UUID()
        transaction.amount = amount as NSDecimalNumber
        transaction.type = type
        transaction.date = date
        transaction.note = note
        transaction.category = category
        return transaction
    }
    
    private func createTestBudget(
        name: String = "Test Budget",
        limit: Decimal = 500.0,
        category: Category? = nil
    ) -> Budget {
        let budget = Budget(context: context)
        budget.id = UUID()
        budget.name = name
        budget.amount = limit as NSDecimalNumber
        budget.spent = 0 as NSDecimalNumber
        budget.isActive = true
        budget.category = category
        return budget
    }
    
    // MARK: - Core Data Tests
    
    func testCreateTransaction() throws {
        // Given
        let category = createTestCategory()
        let amount: Decimal = 50.0
        let note = "Test transaction"
        
        // When
        let transaction = createTestTransaction(amount: amount, category: category, note: note)
        try context.save()
        
        // Then
        XCTAssertNotNil(transaction.id)
        XCTAssertEqual(transaction.amount as Decimal, amount)
        XCTAssertEqual(transaction.type, "expense")
        XCTAssertEqual(transaction.note, note)
        XCTAssertEqual(transaction.category, category)
    }
    
    func testFetchTransactions() throws {
        // Given
        let category = createTestCategory()
        let transaction1 = createTestTransaction(amount: 100, category: category)
        let transaction2 = createTestTransaction(amount: 200, category: category)
        try context.save()
        
        // When
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let transactions = try context.fetch(request)
        
        // Then
        XCTAssertEqual(transactions.count, 2)
        XCTAssertTrue(transactions.contains(transaction1))
        XCTAssertTrue(transactions.contains(transaction2))
    }
    
    func testDeleteTransaction() throws {
        // Given
        let transaction = createTestTransaction()
        try context.save()
        
        // When
        context.delete(transaction)
        try context.save()
        
        // Then
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let transactions = try context.fetch(request)
        XCTAssertEqual(transactions.count, 0)
    }
    
    // MARK: - Currency Formatting Tests
    
    func testCurrencyFormatting() throws {
        // Given
        let amounts: [Decimal] = [0, 1.50, 100.00, 1234.56, 999999.99]
        let expectedFormats = ["$0.00", "$1.50", "$100.00", "$1,234.56", "$999,999.99"]
        
        // When & Then
        for (index, amount) in amounts.enumerated() {
            let formatted = amount.currencyFormatted
            XCTAssertEqual(formatted, expectedFormats[index])
        }
    }
    
    // MARK: - Date Extension Tests
    
    func testDateExtensions() throws {
        // Given
        let date = Date()
        
        // When
        let isoString = date.ISO8601String()
        let timeAgo = date.timeAgoDisplay
        
        // Then
        XCTAssertFalse(isoString.isEmpty)
        XCTAssertFalse(timeAgo.isEmpty)
        XCTAssertTrue(isoString.contains("T"))
    }
    
    // MARK: - Performance Tests
    
    func testTransactionCreationPerformance() throws {
        // Given
        let category = createTestCategory()
        
        // When & Then
        measure {
            for i in 0..<100 {
                let transaction = createTestTransaction(amount: Decimal(i), category: category)
                transaction.note = "Transaction \(i)"
            }
            
            do {
                try context.save()
            } catch {
                XCTFail("Failed to save: \(error)")
            }
        }
    }
    
    func testTransactionFetchPerformance() throws {
        // Given
        let category = createTestCategory()
        
        // Create 1000 transactions
        for i in 0..<1000 {
            let transaction = createTestTransaction(amount: Decimal(i), category: category)
            transaction.note = "Transaction \(i)"
        }
        try context.save()
        
        // When & Then
        measure {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
            
            do {
                let transactions = try context.fetch(request)
                XCTAssertEqual(transactions.count, 1000)
            } catch {
                XCTFail("Failed to fetch: \(error)")
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteTransactionWorkflow() throws {
        // Given
        let category = createTestCategory(name: "Groceries")
        let budget = createTestBudget(name: "Food Budget", limit: 500, category: category)
        try context.save()
        
        // When - Add multiple transactions
        let transactions = [
            createTestTransaction(amount: 50, category: category, note: "Milk"),
            createTestTransaction(amount: 75, category: category, note: "Bread"),
            createTestTransaction(amount: 100, category: category, note: "Meat")
        ]
        try context.save()
        
        // Update budget spent amount
        let totalSpent = transactions.reduce(Decimal(0)) { sum, transaction in
            sum + (transaction.amount as Decimal? ?? 0)
        }
        budget.spent = totalSpent as NSDecimalNumber
        try context.save()
        
        // Then
        XCTAssertEqual(budget.spent as Decimal, 225)
        XCTAssertEqual(budget.amount as Decimal, 500)
    }
}

// MARK: - Test Extensions

extension XCTestCase {
    func waitForAsyncOperation(timeout: TimeInterval = 1.0) {
        let expectation = XCTestExpectation(description: "Async operation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
} 