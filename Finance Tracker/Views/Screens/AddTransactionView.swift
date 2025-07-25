import SwiftUI
import CoreData

struct AddTransactionView: View {
    @StateObject private var viewModel = AddTransactionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingCategoryPicker = false
    @State private var showingReceiptScanner = false
    
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    // Transaction Type Picker
                    Picker("Type", selection: $viewModel.selectedType) {
                        ForEach(AddTransactionViewModel.TransactionType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(type.color)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Amount Input
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("0.00", text: $viewModel.amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    // Category Selection
                    Button(action: { showingCategoryPicker = true }) {
                        HStack {
                            Text("Category")
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if let category = viewModel.selectedCategory {
                                HStack(spacing: 8) {
                                    Image(systemName: category.icon ?? "folder")
                                        .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                                    
                                    Text(category.name ?? "Unknown")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Select Category")
                                    .foregroundColor(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Date Picker
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Receipt") {
                    Button(action: { showingReceiptScanner = true }) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.blue)
                            
                            Text("Scan Receipt")
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("Scan a receipt to automatically extract transaction details")
                }
                
                Section("Notes") {
                    TextField("Add a note (optional)", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isFormValid)
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerView(
                    categories: viewModel.filteredCategories,
                    selectedCategory: $viewModel.selectedCategory
                )
            }
            .sheet(isPresented: $showingReceiptScanner) {
                ReceiptScannerView(isPresented: $showingReceiptScanner) { receiptData in
                    handleScannedReceipt(receiptData)
                }
            }
            .overlay(
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.1))
                    }
                }
            )
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private func saveTransaction() {
        viewModel.saveTransaction { success in
            if success {
                dismiss()
            }
        }
    }
    
    private func handleScannedReceipt(_ receiptData: ReceiptScanningService.ReceiptData) {
        // Auto-fill form with scanned data
        if let amount = receiptData.amount {
            viewModel.amount = String(describing: amount)
        }
        
        if let date = receiptData.date {
            viewModel.date = date
        }
        
        // Try to match merchant name to existing categories or set as notes
        if let merchantName = receiptData.merchantName {
            // Try to find a matching category
            let matchingCategory = viewModel.filteredCategories.first { category in
                guard let categoryName = category.name else { return false }
                return merchantName.localizedCaseInsensitiveContains(categoryName) ||
                       categoryName.localizedCaseInsensitiveContains(merchantName)
            }
            
            if let category = matchingCategory {
                viewModel.selectedCategory = category
            }
            
            // Add merchant name to notes if not already there
            if viewModel.notes.isEmpty {
                viewModel.notes = merchantName
            } else if !viewModel.notes.contains(merchantName) {
                viewModel.notes += " - " + merchantName
            }
        }
        
        // Set transaction type to expense (most receipts are expenses)
        viewModel.selectedType = .expense
    }
}

struct CategoryPickerView: View {
    let categories: [Category]
    @Binding var selectedCategory: Category?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(categories, id: \.id) { category in
                    Button(action: {
                        selectedCategory = category
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon ?? "folder")
                                .font(.title2)
                                .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                                .frame(width: 32, height: 32)
                            
                            Text(category.name ?? "Unknown")
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedCategory?.id == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Select Category")
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

#Preview {
    AddTransactionView()
        .environment(\.managedObjectContext, CoreDataStack.shared.context)
}