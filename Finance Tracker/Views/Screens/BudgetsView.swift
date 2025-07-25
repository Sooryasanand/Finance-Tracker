import SwiftUI
import CoreData

struct BudgetsView: View {
    @StateObject private var viewModel = BudgetsViewModel()
    @State private var showingAddBudget = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.budgets.isEmpty {
                        EmptyBudgetsView(showingAddBudget: $showingAddBudget)
                    } else {
                        ForEach(viewModel.budgets, id: \.id) { budget in
                            BudgetCard(budget: budget, viewModel: viewModel)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddBudget = true }) {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingAddBudget) {
                AddBudgetView()
            }
            .refreshable {
                viewModel.loadBudgets()
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

struct EmptyBudgetsView: View {
    @Binding var showingAddBudget: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Budgets Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create your first budget to start tracking your spending goals")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(action: { showingAddBudget = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Budget")
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

struct BudgetCard: View {
    let budget: Budget
    let viewModel: BudgetsViewModel
    @State private var showingDeleteAlert = false
    
    var budgetProgress: BudgetProgress {
        viewModel.getBudgetProgress(for: budget)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let category = budget.category {
                            Image(systemName: category.icon ?? "folder")
                                .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                        }
                        
                        Text(budget.name ?? "Unknown Budget")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    Text("\(budget.period?.capitalized ?? "Monthly") Budget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Button(action: { viewModel.toggleBudgetStatus(budget) }) {
                        Label(budget.isActive ? "Pause Budget" : "Activate Budget", 
                              systemImage: budget.isActive ? "pause.circle" : "play.circle")
                    }
                    
                    Button(role: .destructive, action: { showingDeleteAlert = true }) {
                        Label("Delete Budget", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(budgetProgress.spent.currencyFormatted)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(budgetProgress.isOverBudget ? .red : .primary)
                    
                    Text("of \(budgetProgress.limit.currencyFormatted)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !budget.isActive {
                        Text("PAUSED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                            .cornerRadius(4)
                        
                        Rectangle()
                            .fill(Color(hex: budgetProgress.progressColor))
                            .frame(width: geometry.size.width * CGFloat(min(budgetProgress.progress, 1.0)), height: 8)
                            .cornerRadius(4)
                            .animation(.easeInOut(duration: 0.3), value: budgetProgress.progress)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text("\(Int(budgetProgress.progress * 100))% used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if budgetProgress.isOverBudget {
                        Text("\(abs(budgetProgress.remaining).currencyFormatted) over")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    } else {
                        Text("\(budgetProgress.remaining.currencyFormatted) left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Period Info
            if let startDate = budget.startDate, let endDate = budget.endDate {
                HStack {
                    Text("Period: \(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .opacity(budget.isActive ? 1.0 : 0.7)
        .alert("Delete Budget", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteBudget(budget)
            }
        } message: {
            Text("Are you sure you want to delete this budget? This action cannot be undone.")
        }
    }
}

#Preview {
    BudgetsView()
        .environment(\.managedObjectContext, CoreDataStack.shared.context)
}