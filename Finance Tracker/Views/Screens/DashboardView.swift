import SwiftUI
import CoreData

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject private var appStateManager: AppStateManager
    @State private var showingAddTransaction = false
    @State private var showingReceiptScanner = false
    
    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading {
                    LoadingView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            // Balance Card
                            BalanceCardView(
                                balance: viewModel.totalBalance,
                                income: viewModel.totalIncome,
                                expenses: viewModel.totalExpenses
                            )
                            
                            // Quick Actions
                            QuickActionsView(
                                showingAddTransaction: $showingAddTransaction,
                                showingReceiptScanner: $showingReceiptScanner
                            )
                            
                            // Recent Transactions
                            if !viewModel.recentTransactions.isEmpty {
                                RecentTransactionsView(transactions: viewModel.recentTransactions)
                            }
                            
                            // Budget Overview
                            if !viewModel.budgetOverviews.isEmpty {
                                BudgetOverviewView(budgets: viewModel.budgetOverviews)
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.refreshData()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.primary)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView()
            }
            .sheet(isPresented: $showingReceiptScanner) {
                ReceiptScannerView(
                    isPresented: $showingReceiptScanner,
                    onReceiptScanned: { receiptData in
                        // Handle scanned receipt data
                        print("Receipt scanned: \(receiptData)")
                    }
                )
            }
            .onAppear {
                viewModel.loadData()
            }
            .refreshable {
                viewModel.refreshData()
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
}

// MARK: - Balance Card View

struct BalanceCardView: View {
    let balance: Decimal
    let income: Decimal
    let expenses: Decimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Total Balance")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "eye")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            Text(balance.currencyFormatted)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(balance >= 0 ? .primary : .red)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Income")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(income.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("Expenses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    Text(expenses.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Quick Actions View

struct QuickActionsView: View {
    @Binding var showingAddTransaction: Bool
    @Binding var showingReceiptScanner: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Add Transaction",
                    icon: "plus.circle.fill",
                    color: .blue
                ) {
                    showingAddTransaction = true
                }
                
                QuickActionButton(
                    title: "Scan Receipt",
                    icon: "camera.fill",
                    color: .green
                ) {
                    showingReceiptScanner = true
                }
                
                QuickActionButton(
                    title: "Add Budget",
                    icon: "chart.pie.fill",
                    color: .orange
                ) {
                    // Navigate to add budget
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recent Transactions View

struct RecentTransactionsView: View {
    let transactions: [Transaction]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                NavigationLink("See All") {
                    TransactionsView()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            LazyVStack(spacing: 8) {
                ForEach(transactions.prefix(5), id: \.id) { transaction in
                    TransactionRowView(transaction: transaction)
                }
            }
        }
    }
}

// MARK: - Budget Overview View

struct BudgetOverviewView: View {
    let budgets: [DashboardViewModel.BudgetOverview]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Budget Overview")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                NavigationLink("See All") {
                    BudgetsView()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(budgets.prefix(3)) { budget in
                    BudgetProgressCard(budget: budget)
                }
            }
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading dashboard...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .environmentObject(AppStateManager.shared)
}