import SwiftUI
import LocalAuthentication
import IntentsUI

struct SettingsView: View {
    @StateObject private var biometricService = BiometricAuthenticationService()
    @StateObject private var syncManager = CloudKitSyncManager.shared
    @StateObject private var siriShortcutsService = SiriShortcutsService.shared
    @StateObject private var exportService = ExportService.shared
    @EnvironmentObject private var appStateManager: AppStateManager
    @State private var showingDataExport = false
    @State private var showingAbout = false
    @State private var showingSiriShortcuts = false
    @State private var showingExportOptions = false
    @State private var selectedExportType: ExportService.ExportType = .pdf
    @State private var selectedExportScope: ExportService.ExportScope = .allTransactions
    
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
                        showingExportOptions = true
                    }
                }
                
                // Siri Shortcuts Section
                Section("Siri Shortcuts") {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.purple)
                        
                        VStack(alignment: .leading) {
                            Text("Voice Commands")
                                .font(.subheadline)
                            Text("Quick actions with Siri")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Demo Mode")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Button("Manage Shortcuts") {
                        showingSiriShortcuts = true
                    }
                    
                    Button("Test Quick Expense") {
                        appStateManager.showSuccess("Demo: Added $25 expense via Siri Shortcuts")
                    }
                }
                
                // Widgets Section
                Section("Widgets") {
                    HStack {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text("Home Screen Widgets")
                                .font(.subheadline)
                            Text("Track spending on home screen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Add Widget") {
                            // This would typically open the widget gallery
                            appStateManager.showSuccess("Long press home screen to add widgets")
                        }
                        .font(.caption)
                    }
                }
                
                // App Information Section
                Section("App Information") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appStateManager.appVersion) (\(appStateManager.buildNumber))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build Date")
                        Spacer()
                        Text(Date().formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(.secondary)
                    }
                    
                    Button("About") {
                        showingAbout = true
                    }
                }
                
                // Support Section
                Section("Support") {
                    Button("Send Feedback") {
                        // TODO: Implement feedback mechanism
                        appStateManager.showSuccess("Feedback feature coming soon")
                    }
                    
                    Button("Privacy Policy") {
                        // TODO: Open privacy policy
                    }
                    
                    Button("Terms of Service") {
                        // TODO: Open terms of service
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingSiriShortcuts) {
                SiriShortcutsView()
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsView(
                    selectedType: $selectedExportType,
                    selectedScope: $selectedExportScope,
                    onExport: performExport
                )
            }
            .alert("Export Error", isPresented: .constant(exportService.exportError != nil)) {
                Button("OK") {
                    exportService.exportError = nil
                }
            } message: {
                if let error = exportService.exportError {
                    Text(error)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var syncStatusText: String {
        switch syncManager.syncStatus {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Synced"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle, .success:
            return .green
        case .syncing:
            return .blue
        case .failed:
            return .red
        }
    }
    
    // MARK: - Private Methods
    
    private func performExport() {
        Task {
            do {
                let url = try await exportService.exportData(type: selectedExportType, scope: selectedExportScope)
                await MainActor.run {
                    appStateManager.showSuccess("Export completed: \(url.lastPathComponent)")
                }
            } catch {
                await MainActor.run {
                    appStateManager.showError("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App Icon
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    // App Name and Version
                    VStack(spacing: 8) {
                        Text("Finance Tracker")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Version \(AppStateManager.shared.appVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About")
                            .font(.headline)
                        
                        Text("Finance Tracker is a comprehensive personal finance management app designed to help you track your income, expenses, and budgets with ease. Built with modern iOS development practices and a focus on security and privacy.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("Features")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "plus.circle.fill", text: "Track income and expenses")
                            FeatureRow(icon: "chart.pie.fill", text: "Set and monitor budgets")
                            FeatureRow(icon: "icloud.fill", text: "iCloud sync across devices")
                            FeatureRow(icon: "faceid", text: "Biometric authentication")
                            FeatureRow(icon: "camera.fill", text: "Receipt scanning with OCR")
                            FeatureRow(icon: "mic.fill", text: "Siri Shortcuts integration")
                            FeatureRow(icon: "rectangle.stack.fill", text: "Home screen widgets")
                            FeatureRow(icon: "square.and.arrow.up", text: "Export to PDF and CSV")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    Spacer()
                }
                .padding()
            }
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
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

// MARK: - Siri Shortcuts View

struct SiriShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var siriShortcutsService = SiriShortcutsService.shared
    
    var body: some View {
        NavigationView {
            List {
                Section("Available Shortcuts (Demo)") {
                    ForEach(SiriShortcutsService.ShortcutType.allCases, id: \.self) { shortcutType in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: shortcutType.icon)
                                    .foregroundColor(.purple)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading) {
                                    Text(shortcutType.title)
                                        .font(.headline)
                                    Text(shortcutType.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            
                            Text("Demo: \"Hey Siri, \(shortcutType.title.lowercased())\"")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.leading, 32)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Quick Actions (Demo)") {
                    Button("Add Quick Expense ($25)") {
                        siriShortcutsService.addQuickExpense(amount: 25.00, category: "Food", note: "Quick expense")
                    }
                    
                    Button("Add Quick Income ($100)") {
                        siriShortcutsService.addQuickIncome(amount: 100.00, category: "Salary", note: "Quick income")
                    }
                }
            }
            .navigationTitle("Siri Shortcuts (Demo)")
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

// MARK: - Export Options View

struct ExportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedType: ExportService.ExportType
    @Binding var selectedScope: ExportService.ExportScope
    let onExport: () -> Void
    
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedCategory = "All Categories"
    @State private var selectedMonth = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Export Format") {
                    Picker("Format", selection: $selectedType) {
                        Text("PDF Report").tag(ExportService.ExportType.pdf)
                        Text("CSV Data").tag(ExportService.ExportType.csv)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Export Scope") {
                    Picker("Scope", selection: $selectedScope) {
                        Text("All Transactions").tag(ExportService.ExportScope.allTransactions)
                        Text("Date Range").tag(ExportService.ExportScope.dateRange(start: startDate, end: endDate))
                        Text("Category").tag(ExportService.ExportScope.category(selectedCategory))
                        Text("Monthly").tag(ExportService.ExportScope.monthly(month: selectedMonth))
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    // Additional options based on scope
                    if case .dateRange = selectedScope {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                    
                    if case .monthly = selectedScope {
                        DatePicker("Month", selection: $selectedMonth, displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        onExport()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppStateManager.shared)
}
