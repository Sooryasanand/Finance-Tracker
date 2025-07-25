import SwiftUI

struct SyncStatusView: View {
    @EnvironmentObject private var syncManager: CloudKitSyncManager
    @EnvironmentObject private var offlineManager: OfflineManager
    
    var body: some View {
        HStack(spacing: 8) {
            // Network Status Indicator
            Circle()
                .fill(offlineManager.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Status Text
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Sync Progress
            if syncManager.syncStatus.isActive {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            // Error Indicator
            if case .failed = syncManager.syncStatus {
                Button(action: { syncManager.startSync() }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var statusText: String {
        if !offlineManager.isOnline {
            return "Offline • \(offlineManager.pendingSyncCount) pending"
        }
        
        switch syncManager.syncStatus {
        case .idle:
            return offlineManager.pendingSyncCount > 0 ? "Sync pending" : "Up to date"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Synced"
        case .failed(let error):
            return "Sync failed"
        }
    }
}

struct DetailedSyncStatusView: View {
    @EnvironmentObject private var syncManager: CloudKitSyncManager
    @EnvironmentObject private var offlineManager: OfflineManager
    @EnvironmentObject private var coreDataStack: CoreDataStack
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Sync Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Sync Now") {
                    syncManager.startSync()
                }
                .disabled(syncManager.syncStatus.isActive || !offlineManager.isOnline)
            }
            
            // Network Status
            SyncStatusRow(
                title: "Network",
                value: offlineManager.networkStatusDescription,
                icon: offlineManager.isOnline ? "wifi" : "wifi.slash",
                color: offlineManager.isOnline ? .green : .red
            )
            
            // CloudKit Sync Status
            SyncStatusRow(
                title: "CloudKit Sync",
                value: cloudKitStatusText,
                icon: cloudKitStatusIcon,
                color: cloudKitStatusColor
            )
            
            // Pending Items
            if offlineManager.pendingSyncCount > 0 {
                SyncStatusRow(
                    title: "Pending Sync",
                    value: "\(offlineManager.pendingSyncCount) items",
                    icon: "clock",
                    color: .orange
                )
            }
            
            // Last Success
            if let lastSyncDate = syncManager.lastSyncDate {
                SyncStatusRow(
                    title: "Last Sync",
                    value: lastSyncDate.relativeFormatted,
                    icon: "checkmark.circle",
                    color: .green
                )
            }
            
            // Migration Status
            if coreDataStack.isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    SyncStatusRow(
                        title: "Database Migration",
                        value: "In progress...",
                        icon: "gear",
                        color: .blue
                    )
                    
                    ProgressView(value: coreDataStack.migrationProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            
            // Error Details
            if let errorMessage = syncManager.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    SyncStatusRow(
                        title: "Error",
                        value: "See details below",
                        icon: "exclamationmark.triangle",
                        color: .red
                    )
                    
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading, 28)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Actions
            HStack(spacing: 12) {
                if case .failed = syncManager.syncStatus {
                    Button("Retry Sync") {
                        offlineManager.retryFailedSync()
                    }
                    .buttonStyle(.bordered)
                }
                
                if offlineManager.pendingSyncCount > 0 {
                    Button("Clear Cache") {
                        Task {
                            try? offlineManager.clearOfflineCache()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                if let errorMessage = coreDataStack.errorMessage {
                    Button("Recover") {
                        coreDataStack.recoverFromError()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var cloudKitStatusText: String {
        switch syncManager.syncStatus {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing data..."
        case .success:
            return "Completed successfully"
        case .failed:
            return "Failed"
        }
    }
    
    private var cloudKitStatusIcon: String {
        switch syncManager.syncStatus {
        case .idle:
            return "icloud"
        case .syncing:
            return "icloud.and.arrow.up"
        case .success:
            return "icloud.and.arrow.up"
        case .failed:
            return "icloud.slash"
        }
    }
    
    private var cloudKitStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return .blue
        case .syncing:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
}

struct SyncStatusRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SyncStatusView()
        
        DetailedSyncStatusView()
    }
    .padding()
    .environmentObject(CloudKitSyncManager.shared)
    .environmentObject(OfflineManager.shared)
    .environmentObject(CoreDataStack.shared)
}