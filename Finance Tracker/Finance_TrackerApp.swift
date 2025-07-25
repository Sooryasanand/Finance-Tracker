//
//  Finance_TrackerApp.swift
//  Finance Tracker
//
//  Created by Soorya Narayanan Sanand on 25/7/2025.
//

import SwiftUI
import os.log

@main
struct Finance_TrackerApp: App {
    @StateObject private var coreDataStack = CoreDataStack.shared
    @StateObject private var cloudKitSyncManager = CloudKitSyncManager.shared
    @StateObject private var offlineManager = OfflineManager.shared
    @StateObject private var appStateManager = AppStateManager.shared
    
    private let logger = Logger(subsystem: "FinanceTracker", category: "App")
    
    var body: some Scene {
        WindowGroup {
            AuthenticatedAppView()
                .environment(\.managedObjectContext, coreDataStack.context)
                .environmentObject(coreDataStack)
                                            .environmentObject(cloudKitSyncManager)
                .environmentObject(offlineManager)
                .environmentObject(appStateManager)
                .onAppear {
                    setupApp()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    handleAppDidBecomeActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    handleAppWillResignActive()
                }
        }
    }
    
    private func setupApp() {
        logger.info("Setting up Finance Tracker app")
        
        // Configure app appearance
        configureAppAppearance()
        
        // Setup Core Data and default data
        Task {
            await setupCoreDataAndDefaultData()
        }
        
        // Setup CloudKit sync
        setupCloudKitSync()
        
        // Setup offline manager
        setupOfflineManager()
        
        logger.info("App setup completed")
    }
    
    private func configureAppAppearance() {
        // Configure navigation bar appearance
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithOpaqueBackground()
        navigationBarAppearance.backgroundColor = UIColor.systemBackground
        navigationBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        navigationBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        
        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.systemBackground
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
    
    private func setupCoreDataAndDefaultData() async {
        do {
            try await coreDataStack.setupUserAndDefaultData()
            logger.info("Core Data setup completed successfully")
        } catch {
            logger.error("Failed to setup Core Data: \(error.localizedDescription)")
            await MainActor.run {
                appStateManager.showError("Failed to initialize app data: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupCloudKitSync() {
        cloudKitSyncManager.startSync()
        logger.info("CloudKit sync manager started")
    }
    
    private func setupOfflineManager() {
        offlineManager.startMonitoring()
        logger.info("Offline manager started")
    }
    
    private func handleAppDidBecomeActive() {
        logger.info("App became active")
        appStateManager.appDidBecomeActive()
        
        // Refresh data when app becomes active
        Task {
            await refreshData()
        }
    }
    
    private func handleAppWillResignActive() {
        logger.info("App will resign active")
        appStateManager.appWillResignActive()
        
        // Save any pending changes
        coreDataStack.saveContext()
    }
    
    private func refreshData() async {
        await coreDataStack.refreshData()
        cloudKitSyncManager.syncNow()
    }
}
