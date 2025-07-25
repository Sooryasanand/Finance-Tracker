//
//  AppStateManager.swift
//  Finance Tracker
//
//  Created by Soorya Narayanan Sanand on 25/7/2025.
//

import Foundation
import SwiftUI
import Combine
import os.log

@MainActor
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isOnline = true
    @Published var syncStatus: SyncStatus = .idle
    @Published var appVersion: String = ""
    @Published var buildNumber: String = ""
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "FinanceTracker", category: "AppStateManager")
    private var cancellables = Set<AnyCancellable>()
    private var errorTimer: Timer?
    private var successTimer: Timer?
    
    // MARK: - Enums
    enum SyncStatus: Hashable {
        case idle
        case syncing
        case completed
        case failed(String)
        
        var description: String {
            switch self {
            case .idle:
                return "Ready"
            case .syncing:
                return "Syncing..."
            case .completed:
                return "Synced"
            case .failed(let error):
                return "Sync failed: \(error)"
            }
        }
        
        var icon: String {
            switch self {
            case .idle:
                return "checkmark.circle"
            case .syncing:
                return "arrow.clockwise"
            case .completed:
                return "checkmark.circle.fill"
            case .failed:
                return "exclamationmark.triangle"
            }
        }
        
        var color: Color {
            switch self {
            case .idle, .completed:
                return .green
            case .syncing:
                return .blue
            case .failed:
                return .red
            }
        }
    }
    
    // MARK: - Initialization
    private init() {
        setupAppInfo()
        setupNetworkMonitoring()
        setupNotifications()
    }
    
    // MARK: - Public Methods
    
    func showError(_ message: String, duration: TimeInterval = 5.0) {
        logger.error("Showing error: \(message)")
        errorMessage = message
        scheduleErrorDismissal(after: duration)
    }
    
    func showSuccess(_ message: String, duration: TimeInterval = 3.0) {
        logger.info("Showing success: \(message)")
        successMessage = message
        scheduleSuccessDismissal(after: duration)
    }
    
    func clearError() {
        errorMessage = nil
        errorTimer?.invalidate()
        errorTimer = nil
    }
    
    func clearSuccess() {
        successMessage = nil
        successTimer?.invalidate()
        successTimer = nil
    }
    
    func setLoading(_ loading: Bool) {
        isLoading = loading
    }
    
    func updateSyncStatus(_ status: SyncStatus) {
        syncStatus = status
        logger.info("Sync status updated: \(status.description)")
    }
    
    func appDidBecomeActive() {
        // Handle app becoming active
        logger.info("App became active")
    }
    
    func appWillResignActive() {
        // Handle app resigning active
        logger.info("App will resign active")
        clearError()
        clearSuccess()
    }
    
    // MARK: - Private Methods
    
    private func setupAppInfo() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        }
        
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            buildNumber = build
        }
    }
    
    private func setupNetworkMonitoring() {
        // Monitor network connectivity
        NotificationCenter.default.publisher(for: NSNotification.Name("NSURLErrorDomain"))
            .sink { [weak self] _ in
                self?.handleNetworkError()
            }
            .store(in: &cancellables)
    }
    
    private func setupNotifications() {
        // Listen for Core Data save notifications
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                self?.handleDataSaved()
            }
            .store(in: &cancellables)
        
        // Listen for CloudKit account changes
        NotificationCenter.default.publisher(for: Notification.Name.CKAccountChanged)
            .sink { [weak self] _ in
                self?.handleCloudKitAccountChange()
            }
            .store(in: &cancellables)
    }
    
    private func scheduleErrorDismissal(after duration: TimeInterval) {
        errorTimer?.invalidate()
        errorTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.clearError()
            }
        }
    }
    
    private func scheduleSuccessDismissal(after duration: TimeInterval) {
        successTimer?.invalidate()
        successTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.clearSuccess()
            }
        }
    }
    
    private func handleNetworkError() {
        isOnline = false
        showError("Network connection lost. Some features may be unavailable.", duration: 10.0)
    }
    
    private func handleDataSaved() {
        logger.debug("Data saved successfully")
    }
    
    private func handleCloudKitAccountChange() {
        logger.info("CloudKit account changed")
        showError("iCloud account changed. Please sign in again.", duration: 8.0)
    }
}

// MARK: - Extensions

extension AppStateManager {
    var isErrorVisible: Bool {
        errorMessage != nil
    }
    
    var isSuccessVisible: Bool {
        successMessage != nil
    }
    
    var shouldShowLoadingIndicator: Bool {
        isLoading || syncStatus == .syncing
    }
} 