import CoreData
import Foundation

// MARK: - Transaction Extensions
extension Transaction {
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        
        let now = Date()
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.date = now
        self.syncStatus = "pending"
        
        if self.type == nil {
            self.type = "expense"
        }
    }
    
    override public func willSave() {
        super.willSave()
        
        if isUpdated && !isDeleted {
            self.updatedAt = Date()
            self.syncStatus = "pending"
        }
    }
    
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateTransactionData()
    }
    
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validateTransactionData()
    }
    
    private func validateTransactionData() throws {
        // Validate amount
        guard let amount = self.amount as Decimal?, amount > 0 else {
            throw ValidationError.invalidAmount("Amount must be greater than zero")
        }
        
        // Validate amount range (max 1 million)
        guard amount <= 1_000_000 else {
            throw ValidationError.invalidAmount("Amount cannot exceed $1,000,000")
        }
        
        // Validate type
        guard let type = self.type, ["income", "expense", "transfer"].contains(type) else {
            throw ValidationError.invalidType("Transaction type must be income, expense, or transfer")
        }
        
        // Validate date is not in future
        guard let date = self.date, date <= Date() else {
            throw ValidationError.invalidDate("Transaction date cannot be in the future")
        }
        
        // Validate notes length
        if let notes = self.notes, notes.count > 500 {
            throw ValidationError.invalidNotes("Notes cannot exceed 500 characters")
        }
        
        // Validate category exists
        guard self.category != nil else {
            throw ValidationError.missingCategory("Transaction must have a category")
        }
        
        // Validate user exists
        guard self.user != nil else {
            throw ValidationError.missingUser("Transaction must be associated with a user")
        }
    }
    
    var formattedAmount: String {
        return (amount as Decimal?)?.currencyFormatted ?? "$0.00"
    }
    
    var signedFormattedAmount: String {
        return (amount as Decimal?)?.signedCurrencyFormatted(type: type ?? "expense") ?? "$0.00"
    }
    
    var isExpense: Bool {
        return type == "expense"
    }
    
    var isIncome: Bool {
        return type == "income"
    }
    
    var isTransfer: Bool {
        return type == "transfer"
    }
}

// MARK: - Category Extensions
extension Category {
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        
        let now = Date()
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.isDefault = false
        self.sortOrder = 0
        
        if self.type == nil {
            self.type = "expense"
        }
        
        if self.color == nil {
            self.color = "#007AFF"
        }
        
        if self.icon == nil {
            self.icon = "folder"
        }
    }
    
    override public func willSave() {
        super.willSave()
        
        if isUpdated && !isDeleted {
            self.updatedAt = Date()
        }
    }
    
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateCategoryData()
    }
    
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validateCategoryData()
    }
    
    private func validateCategoryData() throws {
        // Validate name
        guard let name = self.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidName("Category name cannot be empty")
        }
        
        guard name.count <= 50 else {
            throw ValidationError.invalidName("Category name cannot exceed 50 characters")
        }
        
        // Validate type
        guard let type = self.type, ["income", "expense"].contains(type) else {
            throw ValidationError.invalidType("Category type must be income or expense")
        }
        
        // Validate color format
        guard let color = self.color, color.matches(regex: "^#[0-9A-Fa-f]{6}$") else {
            throw ValidationError.invalidColor("Color must be in hex format (#RRGGBB)")
        }
        
        // Validate icon
        guard let icon = self.icon, !icon.isEmpty, icon.count <= 50 else {
            throw ValidationError.invalidIcon("Icon name must be provided and cannot exceed 50 characters")
        }
    }
    
    var hexColor: String {
        return color ?? "#007AFF"
    }
    
    var systemIcon: String {
        return icon ?? "folder"
    }
    
    var displayName: String {
        return name ?? "Unknown Category"
    }
    
    var transactionCount: Int {
        return transactions?.count ?? 0
    }
    
    var totalAmount: Decimal {
        let transactionArray = transactions?.allObjects as? [Transaction] ?? []
        return transactionArray.reduce(Decimal(0)) { sum, transaction in
            sum + (transaction.amount as Decimal? ?? 0)
        }
    }
}

// MARK: - Budget Extensions
extension Budget {
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        
        let now = Date()
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        self.isActive = true
        self.startDate = now.startOfMonth
        
        if self.period == nil {
            self.period = "monthly"
        }
    }
    
    override public func willSave() {
        super.willSave()
        
        if isUpdated && !isDeleted {
            self.updatedAt = Date()
        }
        
        // Auto-calculate end date based on period
        if let startDate = self.startDate, let period = self.period {
            self.endDate = calculateEndDate(from: startDate, period: period)
        }
    }
    
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateBudgetData()
    }
    
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validateBudgetData()
    }
    
    private func validateBudgetData() throws {
        // Validate name
        guard let name = self.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidName("Budget name cannot be empty")
        }
        
        guard name.count <= 100 else {
            throw ValidationError.invalidName("Budget name cannot exceed 100 characters")
        }
        
        // Validate amount
        guard let amount = self.amount as Decimal?, amount > 0 else {
            throw ValidationError.invalidAmount("Budget amount must be greater than zero")
        }
        
        guard amount <= 10_000_000 else {
            throw ValidationError.invalidAmount("Budget amount cannot exceed $10,000,000")
        }
        
        // Validate period
        guard let period = self.period, ["daily", "weekly", "monthly", "quarterly", "yearly"].contains(period) else {
            throw ValidationError.invalidPeriod("Budget period must be daily, weekly, monthly, quarterly, or yearly")
        }
        
        // Validate dates
        guard let startDate = self.startDate else {
            throw ValidationError.invalidDate("Budget must have a start date")
        }
        
        if let endDate = self.endDate, endDate <= startDate {
            throw ValidationError.invalidDate("Budget end date must be after start date")
        }
        
        // Validate category exists
        guard self.category != nil else {
            throw ValidationError.missingCategory("Budget must have a category")
        }
        
        // Validate user exists
        guard self.user != nil else {
            throw ValidationError.missingUser("Budget must be associated with a user")
        }
    }
    
    private func calculateEndDate(from startDate: Date, period: String) -> Date? {
        let calendar = Calendar.current
        
        switch period {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: startDate)
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: startDate)
        case "monthly":
            return calendar.date(byAdding: .month, value: 1, to: startDate)
        case "quarterly":
            return calendar.date(byAdding: .month, value: 3, to: startDate)
        case "yearly":
            return calendar.date(byAdding: .year, value: 1, to: startDate)
        default:
            return nil
        }
    }
    
    var formattedAmount: String {
        return (amount as Decimal?)?.currencyFormatted ?? "$0.00"
    }
    
    var displayName: String {
        return name ?? "Unknown Budget"
    }
    
    var isCurrentlyActive: Bool {
        guard isActive else { return false }
        
        let now = Date()
        guard let startDate = self.startDate else { return false }
        
        if let endDate = self.endDate {
            return now >= startDate && now <= endDate
        }
        
        return now >= startDate
    }
    
    var spentAmount: Decimal {
        guard let category = self.category,
              let startDate = self.startDate else { return 0 }
        
        let endDate = self.endDate ?? Date()
        
        let predicate = NSPredicate(format: "category == %@ AND date >= %@ AND date <= %@ AND type == 'expense'",
                                   category, startDate as CVarArg, endDate as CVarArg)
        
        let transactions = category.transactions?.filtered(using: predicate) as? Set<Transaction> ?? []
        
        return transactions.reduce(Decimal(0)) { sum, transaction in
            sum + (transaction.amount as Decimal? ?? 0)
        }
    }
    
    var remainingAmount: Decimal {
        let budgetAmount = amount as Decimal? ?? 0
        return budgetAmount - spentAmount
    }
    
    var progressPercentage: Double {
        let budgetAmount = amount as Decimal? ?? 0
        guard budgetAmount > 0 else { return 0 }
        
        let spent = spentAmount
        return min(Double(truncating: spent as NSNumber) / Double(truncating: budgetAmount as NSNumber), 1.0)
    }
    
    var isOverBudget: Bool {
        return spentAmount > (amount as Decimal? ?? 0)
    }
}

// MARK: - User Extensions
extension User {
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        
        let now = Date()
        self.id = UUID()
        self.createdAt = now
        self.updatedAt = now
        
        if self.currency == nil {
            self.currency = "USD"
        }
    }
    
    override public func willSave() {
        super.willSave()
        
        if isUpdated && !isDeleted {
            self.updatedAt = Date()
        }
    }
    
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateUserData()
    }
    
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validateUserData()
    }
    
    private func validateUserData() throws {
        // Validate currency
        guard let currency = self.currency, currency.matches(regex: "^[A-Z]{3}$") else {
            throw ValidationError.invalidCurrency("Currency must be a valid 3-letter ISO code")
        }
        
        // Validate name if provided
        if let name = self.name, name.count > 100 {
            throw ValidationError.invalidName("User name cannot exceed 100 characters")
        }
    }
    
    var displayName: String {
        return name ?? "User"
    }
    
    var totalTransactions: Int {
        return transactions?.count ?? 0
    }
    
    var totalCategories: Int {
        return categories?.count ?? 0
    }
    
    var totalBudgets: Int {
        return budgets?.count ?? 0
    }
    
    var lastSyncString: String {
        guard let lastSyncDate = self.lastSyncDate else {
            return "Never synced"
        }
        return lastSyncDate.relativeFormatted
    }
}

// MARK: - Validation Errors
enum ValidationError: LocalizedError {
    case invalidAmount(String)
    case invalidType(String)
    case invalidDate(String)
    case invalidName(String)
    case invalidColor(String)
    case invalidIcon(String)
    case invalidCurrency(String)
    case invalidNotes(String)
    case invalidPeriod(String)
    case missingCategory(String)
    case missingUser(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAmount(let message),
             .invalidType(let message),
             .invalidDate(let message),
             .invalidName(let message),
             .invalidColor(let message),
             .invalidIcon(let message),
             .invalidCurrency(let message),
             .invalidNotes(let message),
             .invalidPeriod(let message),
             .missingCategory(let message),
             .missingUser(let message):
            return message
        }
    }
}

// MARK: - String Extensions for Validation
extension String {
    func matches(regex pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: self.utf16.count)
            return regex.firstMatch(in: self, options: [], range: range) != nil
        } catch {
            return false
        }
    }
}