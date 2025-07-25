import SwiftUI
import CoreData

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showingAddTransaction = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Balance Card
                    BalanceCardView(
                        balance: viewModel.totalBalance,
                        income: viewModel.totalIncome,
                        expenses: viewModel.totalExpenses
                    )
                    
                    // Quick Actions
                    QuickActionsView(showingAddTransaction: $showingAddTransaction)
                    
                    // Recent Transactions
                    RecentTransactionsView(transactions: viewModel.recentTransactions)
                    
                    // Budget Overview
                    BudgetOverviewView(budgets: viewModel.budgetOverviews)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView()
            }
            .onAppear {
                viewModel.loadData()
            }
            .refreshable {
                viewModel.refreshData()
            }
        }
    }
}

struct BalanceCardView: View {
    let balance: Decimal
    let income: Decimal
    let expenses: Decimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total Balance")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "eye")
                    .foregroundColor(.secondary)
            }
            
            Text(balance.currencyFormatted)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Income")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(income.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(expenses.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct QuickActionsView: View {
    @Binding var showingAddTransaction: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            HStack(spacing: 15) {
                QuickActionButton(
                    title: "Add Income",
                    icon: "plus.circle.fill",
                    color: .green
                ) {
                    showingAddTransaction = true
                }
                
                QuickActionButton(
                    title: "Add Expense",
                    icon: "minus.circle.fill",
                    color: .red
                ) {
                    showingAddTransaction = true
                }
                
                QuickActionButton(
                    title: "Scan Receipt",
                    icon: "camera.fill",
                    color: .blue
                ) {
                    // TODO: Implement receipt scanning
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
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RecentTransactionsView: View {
    let transactions: [Transaction]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Transactions")
                    .font(.headline)
                Spacer()
                NavigationLink("See All", destination: TransactionsView())
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            
            if transactions.isEmpty {
                Text("No transactions today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(transactions, id: \.id) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
        }
    }
}

struct BudgetOverviewView: View {
    let budgets: [DashboardViewModel.BudgetOverview]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Budget Overview")
                    .font(.headline)
                Spacer()
                NavigationLink("Manage", destination: BudgetsView())
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            
            if budgets.isEmpty {
                Text("No active budgets")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(budgets, id: \.id) { budget in
                        BudgetProgressCard(budget: budget)
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, CoreDataStack.shared.context)
}