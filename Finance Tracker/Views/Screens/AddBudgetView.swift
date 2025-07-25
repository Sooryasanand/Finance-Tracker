import SwiftUI

struct AddBudgetView: View {
    @StateObject private var viewModel = AddBudgetViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingCategoryPicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Budget Details") {
                    TextField("Budget Name", text: $viewModel.name)
                    
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
                
                Section("Category") {
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
                }
                
                Section("Period") {
                    Picker("Budget Period", selection: $viewModel.selectedPeriod) {
                        ForEach(AddBudgetViewModel.BudgetPeriod.allCases, id: \.self) { period in
                            HStack {
                                Image(systemName: period.icon)
                                Text(period.displayName)
                            }
                            .tag(period)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)
                    
                    if let endDate = viewModel.endDate {
                        HStack {
                            Text("End Date")
                            Spacer()
                            Text(endDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Toggle("Active", isOn: $viewModel.isActive)
                } footer: {
                    Text("Active budgets will track your spending and send notifications when limits are approached.")
                }
            }
            .navigationTitle("New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveBudget()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isFormValid)
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                BudgetCategoryPickerView(
                    categories: viewModel.expenseCategories,
                    selectedCategory: $viewModel.selectedCategory
                )
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
    
    private func saveBudget() {
        viewModel.saveBudget { success in
            if success {
                dismiss()
            }
        }
    }
}

struct BudgetCategoryPickerView: View {
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
    AddBudgetView()
        .environment(\.managedObjectContext, CoreDataStack.shared.context)
}