import CloudKit
import CoreData
import Combine
import os.log

class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var syncProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let container: CKContainer
    private let database: CKDatabase
    private let coreDataStack: CoreDataStack
    private let logger = Logger(subsystem: "FinanceTracker", category: "CloudKitSync")
    private var cancellables = Set<AnyCancellable>()
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case failed(Error)
        
        var isActive: Bool {
            switch self {
            case .syncing:
                return true
            default:
                return false
            }
        }
    }
    
    enum SyncError: LocalizedError {
        case networkUnavailable
        case accountNotAvailable
        case quotaExceeded
        case rateLimited
        case conflictResolutionFailed
        case dataCorruption
        case unknownError(Error)
        
        var errorDescription: String? {
            switch self {
            case .networkUnavailable:
                return "Network connection is unavailable"
            case .accountNotAvailable:
                return "iCloud account is not available"
            case .quotaExceeded:
                return "iCloud storage quota exceeded"
            case .rateLimited:
                return "Too many requests. Please try again later"
            case .conflictResolutionFailed:
                return "Failed to resolve data conflicts"
            case .dataCorruption:
                return "Data corruption detected"
            case .unknownError(let error):
                return "Sync failed: \(error.localizedDescription)"
            }
        }
    }
    
    private init() {
        self.container = CKContainer.default()
        self.database = container.privateCloudDatabase
        self.coreDataStack = CoreDataStack.shared
        
        setupSubscriptions()
        checkAccountStatus()
    }
    
    // MARK: - Setup and Configuration
    
    private func setupSubscriptions() {
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSync()
            }
            .store(in: &cancellables)
        
        // Listen for CloudKit notifications
        NotificationCenter.default.publisher(for: CKAccountChanged)
            .sink { [weak self] _ in
                self?.checkAccountStatus()
            }
            .store(in: &cancellables)
    }
    
    private func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.logger.info("iCloud account is available")
                case .noAccount:
                    self?.handleSyncError(.accountNotAvailable)
                case .restricted:
                    self?.handleSyncError(.accountNotAvailable)
                case .couldNotDetermine:
                    self?.logger.warning("Could not determine iCloud account status")
                case .temporarilyUnavailable:
                    self?.handleSyncError(.accountNotAvailable)
                @unknown default:
                    self?.logger.error("Unknown iCloud account status")
                }
            }
        }
    }
    
    // MARK: - Sync Operations
    
    func startSync() {
        guard !syncStatus.isActive else { return }
        
        logger.info("Starting CloudKit sync")
        syncStatus = .syncing
        syncProgress = 0.0
        errorMessage = nil
        
        Task {
            do {
                try await performFullSync()
                await MainActor.run {
                    self.syncStatus = .success
                    self.lastSyncDate = Date()
                    self.updateUserLastSyncDate()
                }
            } catch {
                await MainActor.run {
                    self.handleSyncError(error)
                }
            }
        }
    }
    
    private func scheduleSync() {
        // Only auto-sync if not already syncing and network is available
        guard !syncStatus.isActive else { return }
        
        // Debounce automatic syncs
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.startSync()
        }
    }
    
    private func performFullSync() async throws {
        // Step 1: Sync Users (0-20%)
        syncProgress = 0.1
        try await syncUsers()
        
        // Step 2: Sync Categories (20-40%)
        syncProgress = 0.3
        try await syncCategories()
        
        // Step 3: Sync Transactions (40-80%)
        syncProgress = 0.6
        try await syncTransactions()
        
        // Step 4: Sync Budgets (80-100%)
        syncProgress = 0.9
        try await syncBudgets()
        
        syncProgress = 1.0
        logger.info("CloudKit sync completed successfully")
    }
    
    // MARK: - Entity-Specific Sync Methods
    
    private func syncUsers() async throws {
        let context = coreDataStack.context
        
        // Fetch local users that need syncing
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "iCloudRecordID == nil OR lastSyncDate == nil")
        
        let localUsers = try context.fetch(fetchRequest)
        
        for user in localUsers {
            try await syncUser(user)
        }
    }
    
    private func syncUser(_ user: User) async throws {
        let recordID: CKRecord.ID
        
        if let existingRecordID = user.iCloudRecordID {
            recordID = CKRecord.ID(recordName: existingRecordID)
        } else {
            recordID = CKRecord.ID(recordName: user.id?.uuidString ?? UUID().uuidString)
            user.iCloudRecordID = recordID.recordName
        }
        
        let record = CKRecord(recordType: "User", recordID: recordID)
        record["name"] = user.name
        record["currency"] = user.currency
        record["createdAt"] = user.createdAt
        record["updatedAt"] = user.updatedAt
        
        // Handle preferences as a secure data blob
        if let preferences = user.preferences as? Data {
            record["preferences"] = preferences
        }
        
        do {
            _ = try await database.save(record)
            user.lastSyncDate = Date()
            coreDataStack.save()
        } catch let error as CKError {
            try await handleCloudKitError(error, for: record, entity: user)
        }
    }
    
    private func syncCategories() async throws {
        let context = coreDataStack.context
        
        // Fetch categories that need syncing
        let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
        let localCategories = try context.fetch(fetchRequest)
        
        for category in localCategories {
            try await syncCategory(category)
        }
    }
    
    private func syncCategory(_ category: Category) async throws {
        guard let categoryID = category.id else { return }
        
        let recordID = CKRecord.ID(recordName: categoryID.uuidString)
        let record = CKRecord(recordType: "Category", recordID: recordID)
        
        record["name"] = category.name
        record["color"] = category.color
        record["icon"] = category.icon
        record["type"] = category.type
        record["isDefault"] = category.isDefault ? 1 : 0
        record["sortOrder"] = category.sortOrder
        record["createdAt"] = category.createdAt
        record["updatedAt"] = category.updatedAt
        
        // Create reference to user
        if let user = category.user, let userRecordName = user.iCloudRecordID {
            let userReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: userRecordName),
                action: .deleteSelf
            )
            record["user"] = userReference
        }
        
        do {
            _ = try await database.save(record)
        } catch let error as CKError {
            try await handleCloudKitError(error, for: record, entity: category)
        }
    }
    
    private func syncTransactions() async throws {
        let context = coreDataStack.context
        
        // Fetch transactions that need syncing
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "syncStatus != 'synced'")
        
        let localTransactions = try context.fetch(fetchRequest)
        
        for transaction in localTransactions {
            try await syncTransaction(transaction)
        }
    }
    
    private func syncTransaction(_ transaction: Transaction) async throws {
        guard let transactionID = transaction.id else { return }
        
        let recordID = CKRecord.ID(recordName: transactionID.uuidString)
        let record = CKRecord(recordType: "Transaction", recordID: recordID)
        
        record["amount"] = transaction.amount
        record["type"] = transaction.type
        record["notes"] = transaction.notes
        record["date"] = transaction.date
        record["createdAt"] = transaction.createdAt
        record["updatedAt"] = transaction.updatedAt
        
        // Handle receipt image
        if let imageData = transaction.receiptImageData {
            let asset = CKAsset(data: imageData)
            record["receiptImage"] = asset
        }
        
        // Create references
        if let category = transaction.category, let categoryID = category.id {
            let categoryReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: categoryID.uuidString),
                action: .nullify
            )
            record["category"] = categoryReference
        }
        
        if let user = transaction.user, let userRecordName = user.iCloudRecordID {
            let userReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: userRecordName),
                action: .deleteSelf
            )
            record["user"] = userReference
        }
        
        do {
            _ = try await database.save(record)
            transaction.syncStatus = "synced"
            coreDataStack.save()
        } catch let error as CKError {
            transaction.syncStatus = "failed"
            try await handleCloudKitError(error, for: record, entity: transaction)
        }
    }
    
    private func syncBudgets() async throws {
        let context = coreDataStack.context
        
        let fetchRequest: NSFetchRequest<Budget> = Budget.fetchRequest()
        let localBudgets = try context.fetch(fetchRequest)
        
        for budget in localBudgets {
            try await syncBudget(budget)
        }
    }
    
    private func syncBudget(_ budget: Budget) async throws {
        guard let budgetID = budget.id else { return }
        
        let recordID = CKRecord.ID(recordName: budgetID.uuidString)
        let record = CKRecord(recordType: "Budget", recordID: recordID)
        
        record["name"] = budget.name
        record["amount"] = budget.amount
        record["period"] = budget.period
        record["startDate"] = budget.startDate
        record["endDate"] = budget.endDate
        record["isActive"] = budget.isActive ? 1 : 0
        record["createdAt"] = budget.createdAt
        record["updatedAt"] = budget.updatedAt
        
        // Create references
        if let category = budget.category, let categoryID = category.id {
            let categoryReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: categoryID.uuidString),
                action: .nullify
            )
            record["category"] = categoryReference
        }
        
        if let user = budget.user, let userRecordName = user.iCloudRecordID {
            let userReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: userRecordName),
                action: .deleteSelf
            )
            record["user"] = userReference
        }
        
        do {
            _ = try await database.save(record)
        } catch let error as CKError {
            try await handleCloudKitError(error, for: record, entity: budget)
        }
    }
    
    // MARK: - Conflict Resolution
    
    private func handleCloudKitError(_ error: CKError, for record: CKRecord, entity: NSManagedObject) async throws {
        logger.error("CloudKit error: \(error.localizedDescription)")
        
        switch error.code {
        case .networkUnavailable, .networkFailure:
            throw SyncError.networkUnavailable
            
        case .quotaExceeded:
            throw SyncError.quotaExceeded
            
        case .requestRateLimited:
            throw SyncError.rateLimited
            
        case .serverRecordChanged:
            // Handle conflict resolution
            try await resolveConflict(error: error, localRecord: record, entity: entity)
            
        case .unknownItem:
            // Record doesn't exist on server, try to create it
            try await createNewRecord(record, for: entity)
            
        default:
            throw SyncError.unknownError(error)
        }
    }
    
    private func resolveConflict(error: CKError, localRecord: CKRecord, entity: NSManagedObject) async throws {
        guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
            throw SyncError.conflictResolutionFailed
        }
        
        logger.info("Resolving conflict for record: \(localRecord.recordID.recordName)")
        
        // Implement Last-Writer-Wins strategy with modification date comparison
        let localModificationDate = localRecord["updatedAt"] as? Date ?? Date.distantPast
        let serverModificationDate = serverRecord.modificationDate ?? Date.distantPast
        
        if localModificationDate > serverModificationDate {
            // Local version is newer, update server
            try await forceUpdateServerRecord(localRecord, serverRecord: serverRecord, entity: entity)
        } else {
            // Server version is newer, update local
            try await updateLocalEntity(from: serverRecord, entity: entity)
        }
    }
    
    private func forceUpdateServerRecord(_ localRecord: CKRecord, serverRecord: CKRecord, entity: NSManagedObject) async throws {
        // Use the server record as base and apply local changes
        let updatedRecord = serverRecord
        
        // Copy all fields from local record except system fields
        for key in localRecord.allKeys() {
            if !["recordName", "recordID", "recordType", "creationDate", "modificationDate"].contains(key) {
                updatedRecord[key] = localRecord[key]
            }
        }
        
        do {
            _ = try await database.save(updatedRecord)
            logger.info("Successfully resolved conflict with server update")
        } catch {
            throw SyncError.conflictResolutionFailed
        }
    }
    
    private func updateLocalEntity(from serverRecord: CKRecord, entity: NSManagedObject) async throws {
        await MainActor.run {
            // Update local entity with server data
            switch entity {
            case let transaction as Transaction:
                self.updateTransactionFromRecord(transaction, record: serverRecord)
            case let category as Category:
                self.updateCategoryFromRecord(category, record: serverRecord)
            case let budget as Budget:
                self.updateBudgetFromRecord(budget, record: serverRecord)
            case let user as User:
                self.updateUserFromRecord(user, record: serverRecord)
            default:
                break
            }
            
            self.coreDataStack.save()
        }
        
        logger.info("Successfully resolved conflict with local update")
    }
    
    private func createNewRecord(_ record: CKRecord, for entity: NSManagedObject) async throws {
        // Remove system fields that might cause issues
        let cleanRecord = CKRecord(recordType: record.recordType, recordID: record.recordID)
        
        for key in record.allKeys() {
            if !["recordName", "recordID", "recordType"].contains(key) {
                cleanRecord[key] = record[key]
            }
        }
        
        do {
            _ = try await database.save(cleanRecord)
            logger.info("Successfully created new record on server")
        } catch {
            throw SyncError.unknownError(error)
        }
    }
    
    // MARK: - Local Entity Updates from CloudKit
    
    private func updateTransactionFromRecord(_ transaction: Transaction, record: CKRecord) {
        transaction.amount = record["amount"] as? NSDecimalNumber
        transaction.type = record["type"] as? String
        transaction.notes = record["notes"] as? String
        transaction.date = record["date"] as? Date
        transaction.updatedAt = record["updatedAt"] as? Date ?? Date()
        transaction.syncStatus = "synced"
        
        // Handle receipt image asset
        if let asset = record["receiptImage"] as? CKAsset,
           let fileURL = asset.fileURL,
           let imageData = try? Data(contentsOf: fileURL) {
            transaction.receiptImageData = imageData
        }
    }
    
    private func updateCategoryFromRecord(_ category: Category, record: CKRecord) {
        category.name = record["name"] as? String
        category.color = record["color"] as? String
        category.icon = record["icon"] as? String
        category.type = record["type"] as? String
        category.isDefault = (record["isDefault"] as? Int) == 1
        category.sortOrder = record["sortOrder"] as? Int16 ?? 0
        category.updatedAt = record["updatedAt"] as? Date ?? Date()
    }
    
    private func updateBudgetFromRecord(_ budget: Budget, record: CKRecord) {
        budget.name = record["name"] as? String
        budget.amount = record["amount"] as? NSDecimalNumber
        budget.period = record["period"] as? String
        budget.startDate = record["startDate"] as? Date
        budget.endDate = record["endDate"] as? Date
        budget.isActive = (record["isActive"] as? Int) == 1
        budget.updatedAt = record["updatedAt"] as? Date ?? Date()
    }
    
    private func updateUserFromRecord(_ user: User, record: CKRecord) {
        user.name = record["name"] as? String
        user.currency = record["currency"] as? String
        user.updatedAt = record["updatedAt"] as? Date ?? Date()
        user.lastSyncDate = Date()
        
        if let preferencesData = record["preferences"] as? Data {
            user.preferences = preferencesData
        }
    }
    
    // MARK: - Utility Methods
    
    private func updateUserLastSyncDate() {
        let context = coreDataStack.context
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        
        do {
            let users = try context.fetch(fetchRequest)
            for user in users {
                user.lastSyncDate = Date()
            }
            coreDataStack.save()
        } catch {
            logger.error("Failed to update user sync date: \(error)")
        }
    }
    
    private func handleSyncError(_ error: Error) {
        logger.error("Sync error: \(error.localizedDescription)")
        
        let syncError: SyncError
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                syncError = .networkUnavailable
            case .quotaExceeded:
                syncError = .quotaExceeded
            case .requestRateLimited:
                syncError = .rateLimited
            default:
                syncError = .unknownError(ckError)
            }
        } else if let validationError = error as? SyncError {
            syncError = validationError
        } else {
            syncError = .unknownError(error)
        }
        
        syncStatus = .failed(syncError)
        errorMessage = syncError.localizedDescription
    }
}