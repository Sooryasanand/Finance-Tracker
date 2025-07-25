import SwiftUI
import CoreData

struct TransactionsView: View {
    @StateObject private var viewModel = TransactionsViewModel()
    @State private var showingAddTransaction = false
    @State private var showingFilters = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !viewModel.filteredTransactions.isEmpty {
                    TransactionSummaryCard(viewModel: viewModel)
                        .padding()
                }
                
                TransactionFiltersBar(viewModel: viewModel, showingFilters: $showingFilters)
                
                if viewModel.filteredTransactions.isEmpty {
                    EmptyTransactionsView(showingAddTransaction: $showingAddTransaction)
                } else {
                    TransactionsList(viewModel: viewModel)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transactions")
            .searchable(text: $viewModel.searchText, prompt: "Search transactions...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTransaction = true }) {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView()
            }
            .sheet(isPresented: $showingFilters) {
                TransactionFiltersView(viewModel: viewModel)
            }
            .refreshable {
                viewModel.refreshData()
            }
        }
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

struct TransactionSummaryCard: View {
    @ObservedObject var viewModel: TransactionsViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Period Summary")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(viewModel.transactionCount) transactions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Income")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.totalIncome.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.totalExpenses.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Net")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.netAmount.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(viewModel.netAmount >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct TransactionFiltersBar: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Binding var showingFilters: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Type filters
                ForEach(TransactionsViewModel.TransactionFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.displayName,
                        icon: filter.icon,
                        isSelected: viewModel.selectedFilter == filter,
                        color: Color(hex: filter.color)
                    ) {
                        viewModel.selectedFilter = filter
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                // Date range filter
                FilterChip(
                    title: viewModel.selectedDateRange.displayName,
                    icon: "calendar",
                    isSelected: false,
                    color: .blue
                ) {
                    showingFilters = true
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : color.opacity(0.1))
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EmptyTransactionsView: View {
    @Binding var showingAddTransaction: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Transactions")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start tracking your finances by adding your first transaction")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(action: { showingAddTransaction = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Transaction")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct TransactionsList: View {
    @ObservedObject var viewModel: TransactionsViewModel
    
    var body: some View {
        List {
            ForEach(viewModel.groupedTransactions(), id: \.0) { dateString, transactions in
                Section(dateString) {
                    ForEach(transactions, id: \.id) { transaction in
                        TransactionRowView(transaction: transaction)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteTransaction(transactions[index])
                        }
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .background(Color(.systemGroupedBackground))
    }
}

struct TransactionFiltersView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Date Range") {
                    ForEach(TransactionsViewModel.DateRange.allCases, id: \.self) { range in
                        HStack {
                            Text(range.displayName)
                            Spacer()
                            if viewModel.selectedDateRange == range {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedDateRange = range
                        }
                    }
                }
                
                Section("Transaction Type") {
                    ForEach(TransactionsViewModel.TransactionFilter.allCases, id: \.self) { filter in
                        HStack {
                            Image(systemName: filter.icon)
                                .foregroundColor(Color(hex: filter.color))
                                .frame(width: 24)
                            
                            Text(filter.displayName)
                            
                            Spacer()
                            
                            if viewModel.selectedFilter == filter {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedFilter = filter
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    TransactionsView()
        .environment(\.managedObjectContext, CoreDataStack.shared.context)
}