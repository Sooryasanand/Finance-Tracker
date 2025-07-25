import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @StateObject private var biometricService = BiometricAuthenticationService()
    @StateObject private var syncManager = CloudKitSyncManager.shared
    @State private var showingDataExport = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            Form {
                // User Profile Section
                Section("Profile") {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Default User")
                                .font(.headline)
                            Text("finance-tracker@example.com")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Edit") {
                            // TODO: Implement profile editing
                        }
                        .font(.caption)
                    }
                }
                
                // Security Section
                Section("Security") {
                    HStack {
                        Image(systemName: biometricService.biometricType == .faceID ? "faceid" : "touchid")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading) {
                            Text("\(biometricService.biometricType.displayName)")
                                .font(.subheadline)
                            Text("Secure app access")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(biometricService.isBiometricAvailable ? "Available" : "Unavailable")
                            .font(.caption)
                            .foregroundColor(biometricService.isBiometricAvailable ? .green : .red)
                    }
                    
                    Button("Test Authentication") {
                        Task {
                            _ = await biometricService.authenticateWithBiometrics()
                        }
                    }
                }
                
                // Data & Sync Section
                Section("Data & Sync") {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("iCloud Sync")
                                .font(.subheadline)
                            Text("Sync across devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(syncStatusText)
                                .font(.caption)
                                .foregroundColor(syncStatusColor)
                            
                            if let lastSync = syncManager.lastSyncDate {
                                Text("Last: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Button("Sync Now") {
                        syncManager.startSync()
                    }
                    .disabled(syncManager.syncStatus.isActive)
                    
                    Button("Export Data") {
                        showingDataExport = true
                    }
                }
                
                // Preferences Section
                Section("Preferences") {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.green)
                        Text("Currency")
                        Spacer()
                        Text("USD")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.orange)
                        Text("First Day of Week")
                        Spacer()
                        Text("Monday")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "bell")
                            .foregroundColor(.red)
                        Text("Budget Notifications")
                        Spacer()
                        Text("Enabled")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Categories Section
                Section("Categories") {
                    NavigationLink(destination: CategoriesManagementView()) {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.purple)
                            Text("Manage Categories")
                        }
                    }
                }
                
                // About Section
                Section("About") {
                    Button(action: { showingAbout = true }) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("About Finance Tracker")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "star")
                            .foregroundColor(.yellow)
                        Text("Rate App")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.blue)
                        Text("Contact Support")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingDataExport) {
                DataExportView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
    
    private var syncStatusText: String {
        switch syncManager.syncStatus {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Up to date"
        case .failed:
            return "Failed"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
}

struct CategoriesManagementView: View {
    var body: some View {
        Text("Categories Management")
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("Export Your Data")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Choose a format to export your financial data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 12) {
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Export as CSV")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "doc.richtext")
                            Text("Export as PDF Report")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("Finance Tracker")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Features")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(icon: "dollarsign.circle", text: "Track income and expenses")
                        FeatureRow(icon: "chart.pie", text: "Budget management")
                        FeatureRow(icon: "chart.bar", text: "Analytics and insights")
                        FeatureRow(icon: "camera", text: "Receipt scanning with OCR")
                        FeatureRow(icon: "icloud", text: "iCloud sync across devices")
                        FeatureRow(icon: "faceid", text: "Biometric security")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Spacer()
                
                Text("Built with SwiftUI and Core Data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
}