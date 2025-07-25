//
//  Finance_TrackerApp.swift
//  Finance Tracker
//
//  Created by Soorya Narayanan Sanand on 25/7/2025.
//

import SwiftUI

@main
struct Finance_TrackerApp: App {
    let coreDataStack = CoreDataStack.shared
    
    var body: some Scene {
        WindowGroup {
            AuthenticatedAppView()
                .environment(\.managedObjectContext, coreDataStack.context)
                .environmentObject(coreDataStack)
                .environmentObject(CloudKitSyncManager.shared)
                .environmentObject(OfflineManager.shared)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupApp() {
        Task {
            await coreDataStack.setupUserAndDefaultData()
        }
    }
}
