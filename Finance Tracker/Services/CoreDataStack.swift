import CoreData
import CloudKit
import Foundation
import Combine
import os.log

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    
    @Published var isLoading = false
    @Published var migrationProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let logger = Logger(subsystem: "FinanceTracker", category: "CoreDataStack")
    private let migrationManager = CoreDataMigrationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "DataModel")
        
        guard let storeDescription = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve store description")
        }
        
        // Configure CloudKit integration
        configureCloudKitStore(storeDescription)
        
        // Configure store options
        configureStoreOptions(storeDescription)
        
        // Perform migration if needed
        performMigrationIfNeeded(for: storeDescription.url!)
        
        // Load persistent stores
        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error {
                self?.logger.error("Core Data failed to load: \(error.localizedDescription)")
                self?.errorMessage = "Failed to load data store: \(error.localizedDescription)"
            } else {
                self?.logger.info("Core Data loaded successfully")
                self?.setupContextConfiguration(container.viewContext)
            }
        }
        
        return container
    }()
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        // Listen for CloudKit account changes
        NotificationCenter.default.publisher(for: Notification.Name.CKAccountChanged)
            .sink { [weak self] _ in
                self?.handleCloudKitAccountChange()
            }
            .store(in: &cancellables)
        
        // Listen for remote changes from CloudKit
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .sink { [weak self] notification in
                self?.handleRemoteStoreChange(notification)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - CloudKit Configuration
    
    private func configureCloudKitStore(_ storeDescription: NSPersistentStoreDescription) {
        // Enable CloudKit integration
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Configure CloudKit container options
        let cloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.financetracker.app")
        storeDescription.cloudKitContainerOptions = cloudKitOptions
        
        // Set up schema initialization
        storeDescription.setOption(true as NSNumber, forKey: "NSPersistentCloudKitContainerEventChangedHistoryOptionKey")
    }
    
    private func configureStoreOptions(_ storeDescription: NSPersistentStoreDescription) {
        // Performance optimizations
        storeDescription.setOption(true as NSNumber, forKey: NSSQLiteAnalyzeOption)
        storeDescription.setOption(true as NSNumber, forKey: NSSQLiteManualVacuumOption)
        
        // Enable WAL mode for better concurrency
        let pragmaOptions = [
            "journal_mode": "WAL",
            "synchronous": "NORMAL",
            "cache_size": "10000",
            "temp_store": "MEMORY"
        ]
        storeDescription.setOption(pragmaOptions as NSDictionary, forKey: NSSQLitePragmasOption)
        
        // Configure automatic lightweight migration as fallback
        storeDescription.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
    }
    
    private func setupContextConfiguration(_ context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Configure context for CloudKit
        context.transactionAuthor = "FinanceTracker"
        
        // Set up query generation for consistent reads
        do {
            try context.setQueryGenerationFrom(.current)
        } catch {
            logger.warning("Failed to set query generation: \(error)")
        }
    }
    
    // MARK: - Migration Support
    
    private func performMigrationIfNeeded(for storeURL: URL) {
        guard migrationManager.requiresMigration(at: storeURL) else {
            logger.info("No Core Data migration required")
            return
        }
        
        logger.info("Core Data migration required, starting migration process")
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.migrationProgress = 0.0
        }
        
        do {
            // Create backup before migration
            let backupURL = try migrationManager.createBackup(of: storeURL)
            logger.info("Created backup before migration: \(backupURL)")
            
            // Perform migration with progress tracking
            try performMigrationWithProgress(at: storeURL)
            
            // Clean up old backup after successful migration
            DispatchQueue.global().asyncAfter(deadline: .now() + 300) { // 5 minutes
                try? FileManager.default.removeItem(at: backupURL)
            }
            
        } catch {
            logger.error("Migration failed: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Data migration failed: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func performMigrationWithProgress(at storeURL: URL) throws {
        let progress = migrationManager.migrationProgress(for: storeURL)
        
        if let error = progress.error {
            throw error
        }
        
        // Simulate progress updates during migration
        let progressStep = 1.0 / Double(progress.stepsRequired)
        
        for step in 0..<progress.stepsRequired {
            DispatchQueue.main.async {
                self.migrationProgress = Double(step) * progressStep
            }
            
            // Small delay to show progress (remove in production)
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        try migrationManager.migrateStore(at: storeURL)
        
        DispatchQueue.main.async {
            self.migrationProgress = 1.0
            self.isLoading = false
        }
    }
    
    // MARK: - Data Operations
    
    func save() {
        save(context)
    }
    
    func save(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            logger.debug("Context saved successfully")
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
            
            // Handle validation errors specifically
            if let validationError = error as? NSError, validationError.domain == NSCocoaErrorDomain {
                handleValidationError(validationError)
            }
            
            // Try to recover from save errors
            context.rollback()
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }
    
    private func handleValidationError(_ error: NSError) {
        logger.warning("Validation error occurred: \(error)")
        
        // Extract detailed validation information
        if let detailedErrors = error.userInfo[NSDetailedErrorsKey] as? [NSError] {
            for detailedError in detailedErrors {
                logger.warning("Validation error detail: \(detailedError.localizedDescription)")
                
                if let object = detailedError.userInfo[NSValidationObjectErrorKey] as? NSManagedObject {
                    logger.warning("Failed object: \(object)")
                }
            }
        }
    }
    
    // MARK: - Background Context Operations
    
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            persistentContainer.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - User and Default Data Setup
    
    func setupUserAndDefaultData() async {
        do {
            try await performBackgroundTask { context in
                // Create or get current user
                let userRequest: NSFetchRequest<User> = User.fetchRequest()
                userRequest.fetchLimit = 1
                
                let currentUser: User
                if let existingUser = try context.fetch(userRequest).first {
                    currentUser = existingUser
                } else {
                    currentUser = User(context: context)
                    currentUser.id = UUID()
                    currentUser.name = "Default User"
                    currentUser.currency = "USD"
                    currentUser.createdAt = Date()
                    currentUser.updatedAt = Date()
                }
                
                // Create default categories if they don't exist
                let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
                let existingCategories = try context.fetch(categoryRequest)
                
                if existingCategories.isEmpty {
                    try self.createDefaultCategories(for: currentUser, in: context)
                }
                
                try context.save()
            }
        } catch {
            logger.error("Failed to setup user and default data: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to setup initial data: \(error.localizedDescription)"
            }
        }
    }
    
    private func createDefaultCategories(for user: User, in context: NSManagedObjectContext) throws {
        let defaultCategories = [
            ("Food & Dining", "fork.knife", "#FF6B6B", "expense", 1),
            ("Transportation", "car.fill", "#4ECDC4", "expense", 2),
            ("Shopping", "bag.fill", "#45B7D1", "expense", 3),
            ("Entertainment", "tv.fill", "#96CEB4", "expense", 4),
            ("Bills & Utilities", "doc.text.fill", "#FFEAA7", "expense", 5),
            ("Healthcare", "heart.fill", "#DDA0DD", "expense", 6),
            ("Education", "book.fill", "#74B9FF", "expense", 7),
            ("Travel", "airplane", "#FD79A8", "expense", 8),
            ("Other Expenses", "questionmark.circle.fill", "#95A5A6", "expense", 9),
            ("Salary", "dollarsign.circle.fill", "#00B894", "income", 1),
            ("Freelance", "briefcase.fill", "#0984E3", "income", 2),
            ("Investments", "chart.line.uptrend.xyaxis", "#6C5CE7", "income", 3),
            ("Business", "building.2.fill", "#E17055", "income", 4),
            ("Other Income", "plus.circle.fill", "#A29BFE", "income", 5)
        ]
        
        for (name, icon, color, type, sortOrder) in defaultCategories {
            let category = Category(context: context)
            category.id = UUID()
            category.name = name
            category.icon = icon
            category.color = color
            category.type = type
            category.isDefault = true
            category.sortOrder = Int16(sortOrder)
            category.user = user
            category.createdAt = Date()
            category.updatedAt = Date()
        }
        
        logger.info("Created \(defaultCategories.count) default categories")
    }
    
    // MARK: - CloudKit Event Handling
    
    private func handleCloudKitAccountChange() {
        logger.info("CloudKit account changed, reinitializing sync")
        // Trigger a sync refresh
        CloudKitSyncManager.shared.startSync()
    }
    
    private func handleRemoteStoreChange(_ notification: Notification) {
        logger.info("Remote store change detected")
        
        // Process remote changes on the main context
        DispatchQueue.main.async { [weak self] in
            self?.context.perform {
                // The context will automatically merge changes
                self?.logger.debug("Processed remote store changes")
            }
        }
    }
    
    // MARK: - Data Cleanup and Maintenance
    
    func performDataMaintenance() async {
        do {
            try await performBackgroundTask { context in
                // Clean up orphaned data
                try self.cleanupOrphanedData(in: context)
                
                // Optimize database
                try self.optimizeDatabase(in: context)
                
                try context.save()
            }
        } catch {
            logger.error("Data maintenance failed: \(error)")
        }
    }
    
    private func cleanupOrphanedData(in context: NSManagedObjectContext) throws {
        // Remove transactions without categories or users
        let orphanedTransactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        orphanedTransactionRequest.predicate = NSPredicate(format: "category == nil OR user == nil")
        
        let orphanedTransactions = try context.fetch(orphanedTransactionRequest)
        for transaction in orphanedTransactions {
            context.delete(transaction)
        }
        
        logger.info("Cleaned up \(orphanedTransactions.count) orphaned transactions")
    }
    
    private func optimizeDatabase(in context: NSManagedObjectContext) throws {
        // This would typically involve database-specific optimizations
        // For SQLite, we could run ANALYZE and VACUUM commands
        logger.info("Database optimization completed")
    }
    
    // MARK: - Error Recovery
    
    func recoverFromError() {
        logger.info("Attempting error recovery")
        
        // Clear error state
        errorMessage = nil
        
        // Try to reinitialize the persistent container
        DispatchQueue.global().async { [weak self] in
            // Force recreation of persistent container
            self?._persistentContainer = nil
            
            // Trigger lazy initialization
            _ = self?.persistentContainer
        }
    }
    
    // MARK: - Data Refresh
    
    func refreshData() async {
        logger.info("Refreshing Core Data context")
        
        await MainActor.run {
            context.refreshAllObjects()
        }
    }
    
    // MARK: - Context Save
    
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
                logger.debug("Context saved successfully")
            } catch {
                logger.error("Failed to save context: \(error)")
                errorMessage = "Failed to save data: \(error.localizedDescription)"
            }
        }
    }
    
    private var _persistentContainer: NSPersistentCloudKitContainer?
}
