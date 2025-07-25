import Network
import Foundation
import CoreData
import Combine

class OfflineManager: ObservableObject {
    static let shared = OfflineManager()
    
    @Published var isOnline: Bool = false
    @Published var pendingSyncCount: Int = 0
    @Published var offlineQueueStatus: OfflineQueueStatus = .empty
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private let coreDataStack = CoreDataStack.shared
    private let syncManager = CloudKitSyncManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    enum OfflineQueueStatus {
        case empty
        case pending(Int)
        case syncing
        case failed(Error)
    }
    
    private init() {
        setupNetworkMonitoring()
        setupOfflineQueue()
        loadPendingSyncCount()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                
                // If we just came back online, trigger sync
                if !wasOnline && self?.isOnline == true {
                    self?.handleConnectivityRestored()
                }
            }
        }
        
        monitor.start(queue: monitorQueue)
    }
    
    private func handleConnectivityRestored() {
        guard pendingSyncCount > 0 else { return }
        
        // Delay sync to ensure connection is stable
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.syncManager.startSync()
        }
    }
    
    // MARK: - Offline Queue Management
    
    private func setupOfflineQueue() {
        // Monitor Core Data changes to track pending sync items
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                self?.updatePendingSyncCount()
            }
            .store(in: &cancellables)
        
        // Monitor sync status changes
        syncManager.$syncStatus
            .sink { [weak self] status in
                self?.handleSyncStatusChange(status)
            }
            .store(in: &cancellables)
    }
    
    private func handleSyncStatusChange(_ status: CloudKitSyncManager.SyncStatus) {
        switch status {
        case .syncing:
            offlineQueueStatus = .syncing
        case .success:
            offlineQueueStatus = pendingSyncCount > 0 ? .pending(pendingSyncCount) : .empty
        case .failed(let error):
            offlineQueueStatus = .failed(error)
        case .idle:
            offlineQueueStatus = pendingSyncCount > 0 ? .pending(pendingSyncCount) : .empty
        }
    }
    
    private func loadPendingSyncCount() {
        updatePendingSyncCount()
    }
    
    private func updatePendingSyncCount() {
        let context = coreDataStack.context
        
        let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        transactionRequest.predicate = NSPredicate(format: "syncStatus != 'synced'")
        
        do {
            let pendingTransactions = try context.count(for: transactionRequest)
            
            DispatchQueue.main.async {
                self.pendingSyncCount = pendingTransactions
                self.offlineQueueStatus = pendingTransactions > 0 ? .pending(pendingTransactions) : .empty
            }
        } catch {
            print("Failed to count pending sync items: \(error)")
        }
    }
    
    // MARK: - Offline Data Operations
    
    func createTransactionOffline(
        amount: Decimal,
        type: String,
        categoryID: UUID,
        notes: String? = nil,
        date: Date = Date()
    ) -> Result<Transaction, Error> {
        let context = coreDataStack.context
        
        do {
            // Find category
            let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
            categoryRequest.predicate = NSPredicate(format: "id == %@", categoryID as CVarArg)
            
            guard let category = try context.fetch(categoryRequest).first else {
                return .failure(OfflineError.categoryNotFound)
            }
            
            // Find current user
            let userRequest: NSFetchRequest<User> = User.fetchRequest()
            guard let user = try context.fetch(userRequest).first else {
                return .failure(OfflineError.userNotFound)
            }
            
            // Create transaction
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.amount = NSDecimalNumber(decimal: amount)
            transaction.type = type
            transaction.category = category
            transaction.user = user
            transaction.notes = notes
            transaction.date = date
            transaction.createdAt = Date()
            transaction.updatedAt = Date()
            transaction.syncStatus = "pending"
            
            try context.save()
            
            return .success(transaction)
            
        } catch {
            return .failure(error)
        }
    }
    
    func updateTransactionOffline(
        transaction: Transaction,
        amount: Decimal? = nil,
        categoryID: UUID? = nil,
        notes: String? = nil,
        date: Date? = nil
    ) -> Result<Void, Error> {
        let context = coreDataStack.context
        
        do {
            if let amount = amount {
                transaction.amount = NSDecimalNumber(decimal: amount)
            }
            
            if let categoryID = categoryID {
                let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
                categoryRequest.predicate = NSPredicate(format: "id == %@", categoryID as CVarArg)
                
                guard let category = try context.fetch(categoryRequest).first else {
                    return .failure(OfflineError.categoryNotFound)
                }
                
                transaction.category = category
            }
            
            if let notes = notes {
                transaction.notes = notes
            }
            
            if let date = date {
                transaction.date = date
            }
            
            transaction.updatedAt = Date()
            transaction.syncStatus = "pending"
            
            try context.save()
            
            return .success(())
            
        } catch {
            return .failure(error)
        }
    }
    
    func deleteTransactionOffline(_ transaction: Transaction) -> Result<Void, Error> {
        let context = coreDataStack.context
        
        do {
            // Mark for deletion instead of actually deleting
            // This allows us to sync the deletion with CloudKit
            transaction.syncStatus = "deleted"
            transaction.updatedAt = Date()
            
            try context.save()
            
            return .success(())
            
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Data Consistency Checks
    
    func performDataConsistencyCheck() async throws {
        let context = coreDataStack.context
        
        try await context.perform {
            // Check for orphaned transactions (without category or user)
            let orphanedTransactionsRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            orphanedTransactionsRequest.predicate = NSPredicate(format: "category == nil OR user == nil")
            
            let orphanedTransactions = try context.fetch(orphanedTransactionsRequest)
            
            for transaction in orphanedTransactions {
                // Try to fix by assigning to default category and current user
                if transaction.category == nil {
                    let defaultCategoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
                    defaultCategoryRequest.predicate = NSPredicate(format: "isDefault == YES AND type == %@", transaction.type ?? "expense")
                    defaultCategoryRequest.fetchLimit = 1
                    
                    if let defaultCategory = try context.fetch(defaultCategoryRequest).first {
                        transaction.category = defaultCategory
                    }
                }
                
                if transaction.user == nil {
                    let userRequest: NSFetchRequest<User> = User.fetchRequest()
                    userRequest.fetchLimit = 1
                    
                    if let user = try context.fetch(userRequest).first {
                        transaction.user = user
                    }
                }
                
                transaction.syncStatus = "pending"
                transaction.updatedAt = Date()
            }
            
            // Check for invalid amounts
            let invalidAmountRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            invalidAmountRequest.predicate = NSPredicate(format: "amount <= 0")
            
            let invalidAmountTransactions = try context.fetch(invalidAmountRequest)
            
            for transaction in invalidAmountTransactions {
                // Set minimum amount or mark for manual review
                transaction.amount = NSDecimalNumber(value: 0.01)
                transaction.syncStatus = "pending"
                transaction.updatedAt = Date()
            }
            
            try context.save()
        }
    }
    
    // MARK: - Cache Management
    
    func clearOfflineCache() throws {
        let context = coreDataStack.context
        
        // Remove failed sync items older than 30 days
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let failedSyncRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        failedSyncRequest.predicate = NSPredicate(
            format: "syncStatus == 'failed' AND updatedAt < %@",
            cutoffDate as CVarArg
        )
        
        let failedTransactions = try context.fetch(failedSyncRequest)
        
        for transaction in failedTransactions {
            context.delete(transaction)
        }
        
        try context.save()
        updatePendingSyncCount()
    }
    
    // MARK: - Retry Logic
    
    func retryFailedSync() {
        guard isOnline else { return }
        
        let context = coreDataStack.context
        
        // Reset failed sync status to pending
        let failedSyncRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        failedSyncRequest.predicate = NSPredicate(format: "syncStatus == 'failed'")
        
        do {
            let failedTransactions = try context.fetch(failedSyncRequest)
            
            for transaction in failedTransactions {
                transaction.syncStatus = "pending"
                transaction.updatedAt = Date()
            }
            
            try context.save()
            
            // Trigger sync
            syncManager.startSync()
            
        } catch {
            print("Failed to retry sync: \(error)")
        }
    }
    
    // MARK: - Status Information
    
    var networkStatusDescription: String {
        return isOnline ? "Online" : "Offline"
    }
    
    var queueStatusDescription: String {
        switch offlineQueueStatus {
        case .empty:
            return "All data synced"
        case .pending(let count):
            return "\(count) items pending sync"
        case .syncing:
            return "Syncing..."
        case .failed(let error):
            return "Sync failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Offline Errors

enum OfflineError: LocalizedError {
    case categoryNotFound
    case userNotFound
    case networkUnavailable
    case dataCorruption
    
    var errorDescription: String? {
        switch self {
        case .categoryNotFound:
            return "Category not found"
        case .userNotFound:
            return "User not found"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .dataCorruption:
            return "Data corruption detected"
        }
    }
}