import CoreData
import Foundation
import os.log

class CoreDataMigrationManager {
    static let shared = CoreDataMigrationManager()
    
    private let logger = Logger(subsystem: "FinanceTracker", category: "CoreDataMigration")
    
    private init() {}
    
    // MARK: - Migration Versions
    
    enum ModelVersion: String, CaseIterable {
        case version1 = "DataModel"
        case version2 = "DataModel_v2"
        case version3 = "DataModel_v3"
        
        var name: String {
            return rawValue
        }
        
        var modelBundle: Bundle {
            return Bundle.main
        }
        
        var modelURL: URL {
            guard let url = modelBundle.url(forResource: name, withExtension: "momd") else {
                fatalError("Unable to find model file for version \(name)")
            }
            return url
        }
        
        var managedObjectModel: NSManagedObjectModel {
            guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
                fatalError("Unable to load model at \(modelURL)")
            }
            return model
        }
        
        static var current: ModelVersion {
            return .version1 // Update this when adding new versions
        }
        
        func nextVersion() -> ModelVersion? {
            switch self {
            case .version1:
                return .version2
            case .version2:
                return .version3
            case .version3:
                return nil
            }
        }
    }
    
    // MARK: - Migration Detection
    
    func requiresMigration(at storeURL: URL) -> Bool {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        ) else {
            return false
        }
        
        let currentModel = ModelVersion.current.managedObjectModel
        return !currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }
    
    func currentVersion(for storeURL: URL) -> ModelVersion? {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        ) else {
            return nil
        }
        
        for version in ModelVersion.allCases {
            if version.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                return version
            }
        }
        
        return nil
    }
    
    // MARK: - Migration Execution
    
    func migrateStore(at storeURL: URL) throws {
        logger.info("Starting Core Data migration for store at: \(storeURL.path)")
        
        guard requiresMigration(at: storeURL) else {
            logger.info("No migration required")
            return
        }
        
        guard let currentVersion = currentVersion(for: storeURL) else {
            throw MigrationError.unknownStoreVersion
        }
        
        logger.info("Current store version: \(currentVersion.name)")
        
        try forceWALCheckpointingForStore(at: storeURL)
        
        var nextVersion = currentVersion.nextVersion()
        var currentStoreURL = storeURL
        
        while let targetVersion = nextVersion {
            logger.info("Migrating from \(currentVersion.name) to \(targetVersion.name)")
            
            let tempURL = storeURL.appendingPathExtension("migration-\(targetVersion.name)")
            
            try migrateStore(
                from: currentStoreURL,
                sourceVersion: currentVersion,
                to: tempURL,
                targetVersion: targetVersion
            )
            
            // Clean up previous temporary file if it exists
            if currentStoreURL != storeURL {
                try? FileManager.default.removeItem(at: currentStoreURL)
            }
            
            currentStoreURL = tempURL
            nextVersion = targetVersion.nextVersion()
        }
        
        // Replace original store with migrated version
        if currentStoreURL != storeURL {
            try replaceStore(at: storeURL, with: currentStoreURL)
        }
        
        logger.info("Migration completed successfully")
    }
    
    private func migrateStore(
        from sourceURL: URL,
        sourceVersion: ModelVersion,
        to targetURL: URL,
        targetVersion: ModelVersion
    ) throws {
        let mappingModel = try mappingModel(
            from: sourceVersion,
            to: targetVersion
        )
        
        let migrationManager = NSMigrationManager(
            sourceModel: sourceVersion.managedObjectModel,
            destinationModel: targetVersion.managedObjectModel
        )
        
        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: false,
            NSInferMappingModelAutomaticallyOption: false
        ]
        
        try migrationManager.migrateStore(
            from: sourceURL,
            sourceType: NSSQLiteStoreType,
            options: options,
            to: targetURL,
            destinationType: NSSQLiteStoreType,
            destinationOptions: options,
            with: mappingModel
        )
    }
    
    private func mappingModel(from sourceVersion: ModelVersion, to targetVersion: ModelVersion) throws -> NSMappingModel {
        let mappingName = "\(sourceVersion.name)_to_\(targetVersion.name)"
        
        // Try to find custom mapping model first
        if let mappingURL = Bundle.main.url(forResource: mappingName, withExtension: "cdm"),
           let mappingModel = NSMappingModel(contentsOf: mappingURL) {
            return mappingModel
        }
        
        // Fall back to inferred mapping
        guard let inferredMapping = try? NSMappingModel.inferredMappingModel(
            forSourceModel: sourceVersion.managedObjectModel,
            destinationModel: targetVersion.managedObjectModel
        ) else {
            throw MigrationError.mappingModelNotFound(from: sourceVersion.name, to: targetVersion.name)
        }
        
        return inferredMapping
    }
    
    // MARK: - File Management
    
    private func forceWALCheckpointingForStore(at storeURL: URL) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        
        let options: [String: Any] = [
            NSSQLitePragmasOption: ["journal_mode": "DELETE"]
        ]
        
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )
        
        try coordinator.remove(store)
    }
    
    private func replaceStore(at targetURL: URL, with sourceURL: URL) throws {
        let fileManager = FileManager.default
        
        // Remove target store files
        let targetExtensions = ["", "-shm", "-wal"]
        for ext in targetExtensions {
            let url = targetURL.appendingPathExtension(ext)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        
        // Move source files to target location
        let sourceExtensions = ["", "-shm", "-wal"]
        for ext in sourceExtensions {
            let sourceFileURL = sourceURL.appendingPathExtension(ext)
            let targetFileURL = targetURL.appendingPathExtension(ext)
            
            if fileManager.fileExists(atPath: sourceFileURL.path) {
                try fileManager.moveItem(at: sourceFileURL, to: targetFileURL)
            }
        }
    }
    
    // MARK: - Migration Progress
    
    func migrationProgress(for storeURL: URL) -> MigrationProgress {
        guard requiresMigration(at: storeURL) else {
            return MigrationProgress(isRequired: false, currentVersion: ModelVersion.current.name)
        }
        
        guard let currentVersion = currentVersion(for: storeURL) else {
            return MigrationProgress(
                isRequired: true,
                currentVersion: "Unknown",
                error: MigrationError.unknownStoreVersion
            )
        }
        
        var stepsRequired = 0
        var nextVersion = currentVersion.nextVersion()
        
        while nextVersion != nil {
            stepsRequired += 1
            nextVersion = nextVersion?.nextVersion()
        }
        
        return MigrationProgress(
            isRequired: true,
            currentVersion: currentVersion.name,
            targetVersion: ModelVersion.current.name,
            stepsRequired: stepsRequired
        )
    }
    
    // MARK: - Backup and Recovery
    
    func createBackup(of storeURL: URL) throws -> URL {
        let backupURL = storeURL.appendingPathExtension("backup-\(Date().timeIntervalSince1970)")
        let fileManager = FileManager.default
        
        // Copy all store files
        let extensions = ["", "-shm", "-wal"]
        for ext in extensions {
            let sourceURL = storeURL.appendingPathExtension(ext)
            let backupFileURL = backupURL.appendingPathExtension(ext)
            
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: backupFileURL)
            }
        }
        
        logger.info("Created backup at: \(backupURL.path)")
        return backupURL
    }
    
    func restoreBackup(from backupURL: URL, to targetURL: URL) throws {
        let fileManager = FileManager.default
        
        // Remove existing target files
        let extensions = ["", "-shm", "-wal"]
        for ext in extensions {
            let targetFileURL = targetURL.appendingPathExtension(ext)
            if fileManager.fileExists(atPath: targetFileURL.path) {
                try fileManager.removeItem(at: targetFileURL)
            }
        }
        
        // Copy backup files to target
        for ext in extensions {
            let backupFileURL = backupURL.appendingPathExtension(ext)
            let targetFileURL = targetURL.appendingPathExtension(ext)
            
            if fileManager.fileExists(atPath: backupFileURL.path) {
                try fileManager.copyItem(at: backupFileURL, to: targetFileURL)
            }
        }
        
        logger.info("Restored backup from: \(backupURL.path)")
    }
}

// MARK: - Migration Types

struct MigrationProgress {
    let isRequired: Bool
    let currentVersion: String
    let targetVersion: String?
    let stepsRequired: Int
    let error: Error?
    
    init(isRequired: Bool, currentVersion: String, targetVersion: String? = nil, stepsRequired: Int = 0, error: Error? = nil) {
        self.isRequired = isRequired
        self.currentVersion = currentVersion
        self.targetVersion = targetVersion
        self.stepsRequired = stepsRequired
        self.error = error
    }
}

enum MigrationError: LocalizedError {
    case unknownStoreVersion
    case mappingModelNotFound(from: String, to: String)
    case migrationFailed(Error)
    case backupFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .unknownStoreVersion:
            return "Unable to determine store version"
        case .mappingModelNotFound(let from, let to):
            return "Mapping model not found for migration from \(from) to \(to)"
        case .migrationFailed(let error):
            return "Migration failed: \(error.localizedDescription)"
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        }
    }
}