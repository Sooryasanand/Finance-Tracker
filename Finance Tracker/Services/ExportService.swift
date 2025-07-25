//
//  ExportService.swift
//  Finance Tracker
//
//  Created by Soorya Narayanan Sanand on 25/7/2025.
//

import Foundation
import CoreData
import PDFKit
import UIKit
import os.log

@MainActor
class ExportService: ObservableObject {
    static let shared = ExportService()
    
    // MARK: - Published Properties
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    @Published var exportError: String?
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "FinanceTracker", category: "ExportService")
    private let coreDataStack = CoreDataStack.shared
    
    // MARK: - Export Types
    enum ExportType {
        case pdf
        case csv
        
        var rawValue: String {
            switch self {
            case .pdf:
                return "PDF"
            case .csv:
                return "CSV"
            }
        }
        
        var fileExtension: String {
            switch self {
            case .pdf:
                return "pdf"
            case .csv:
                return "csv"
            }
        }
        
        var mimeType: String {
            switch self {
            case .pdf:
                return "application/pdf"
            case .csv:
                return "text/csv"
            }
        }
    }
    
    enum ExportScope: Hashable {
        case allTransactions
        case dateRange(start: Date, end: Date)
        case category(String)
        case monthly(month: Date)
        
        var title: String {
            switch self {
            case .allTransactions:
                return "All Transactions"
            case .dateRange(let start, let end):
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
            case .category(let name):
                return "Category: \(name)"
            case .monthly(let month):
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: month)
            }
        }
    }
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Public Methods
    
    func exportData(type: ExportType, scope: ExportScope) async throws -> URL {
        isExporting = true
        exportProgress = 0.0
        exportError = nil
        
        defer {
            isExporting = false
            exportProgress = 0.0
        }
        
        logger.info("Starting export: \(type.rawValue) for scope: \(scope.title)")
        
        do {
            let url = try await createExportFile(type: type, scope: scope)
            
            exportProgress = 1.0
            logger.info("Export completed successfully: \(url.lastPathComponent)")
            
            return url
        } catch {
            exportError = error.localizedDescription
            logger.error("Export failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func createExportFile(type: ExportType, scope: ExportScope) async throws -> URL {
        switch type {
        case .pdf:
            return try await exportToPDF(scope: scope)
        case .csv:
            return try await exportToCSV(scope: scope)
        }
    }
    
    private func exportToPDF(scope: ExportScope) async throws -> URL {
        let transactions = try await fetchTransactions(for: scope)
        let reportData = try await generateReportData(transactions: transactions, scope: scope)
        
        exportProgress = 0.3
        
        let pdfData = try generatePDFReport(data: reportData)
        
        exportProgress = 0.7
        
        let fileName = "Finance_Report_\(Date().ISO8601String()).pdf"
        let url = try saveFile(data: pdfData, fileName: fileName)
        
        exportProgress = 1.0
        return url
    }
    
    private func exportToCSV(scope: ExportScope) async throws -> URL {
        let transactions = try await fetchTransactions(for: scope)
        
        exportProgress = 0.3
        
        let csvData = generateCSVData(transactions: transactions)
        
        exportProgress = 0.7
        
        let fileName = "Finance_Data_\(Date().ISO8601String()).csv"
        let url = try saveFile(data: csvData, fileName: fileName)
        
        exportProgress = 1.0
        return url
    }
    
    private func fetchTransactions(for scope: ExportScope) async throws -> [Transaction] {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        
        switch scope {
        case .allTransactions:
            break // No predicate needed
            
        case .dateRange(let start, let end):
            request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)
            
        case .category(let categoryName):
            request.predicate = NSPredicate(format: "category.name == %@", categoryName)
            
        case .monthly(let month):
            let calendar = Calendar.current
            guard let startOfMonth = calendar.dateInterval(of: .month, for: month)?.start,
                  let endOfMonth = calendar.dateInterval(of: .month, for: month)?.end else {
                throw ExportError.invalidDateRange
            }
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfMonth as NSDate, endOfMonth as NSDate)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        
        return try coreDataStack.context.fetch(request)
    }
    
    private func generateReportData(transactions: [Transaction], scope: ExportScope) async throws -> ReportData {
        let totalIncome = transactions.filter { $0.type == "income" }.reduce(Decimal(0)) { sum, transaction in
            sum + (transaction.amount as Decimal? ?? 0)
        }
        
        let totalExpenses = transactions.filter { $0.type == "expense" }.reduce(Decimal(0)) { sum, transaction in
            sum + (transaction.amount as Decimal? ?? 0)
        }
        
        let balance = totalIncome - totalExpenses
        
        // Group by category
        let categoryGroups = Dictionary(grouping: transactions) { transaction in
            transaction.category?.name ?? "Uncategorized"
        }
        
        let categoryTotals = categoryGroups.mapValues { transactions in
            transactions.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.amount as Decimal? ?? 0)
            }
        }
        
        return ReportData(
            scope: scope,
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            balance: balance,
            transactionCount: transactions.count,
            categoryTotals: categoryTotals,
            transactions: transactions
        )
    }
    
    private func generatePDFReport(data: ReportData) throws -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "Finance Tracker",
            kCGPDFContextAuthor: "Finance Tracker App",
            kCGPDFContextTitle: "Financial Report - \(data.scope.title)"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let pdfData = renderer.pdfData { context in
            context.beginPage()
            
            let titleAttributes = [
                NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 24),
                NSAttributedString.Key.foregroundColor: UIColor.black
            ]
            
            let subtitleAttributes = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 16),
                NSAttributedString.Key.foregroundColor: UIColor.darkGray
            ]
            
            let bodyAttributes = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12),
                NSAttributedString.Key.foregroundColor: UIColor.black
            ]
            
            var yPosition: CGFloat = 50
            
            // Title
            let title = "Financial Report"
            title.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            // Subtitle
            let subtitle = data.scope.title
            subtitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: subtitleAttributes)
            yPosition += 30
            
            // Summary
            let summary = """
            Total Income: \(data.totalIncome.currencyFormatted)
            Total Expenses: \(data.totalExpenses.currencyFormatted)
            Balance: \(data.balance.currencyFormatted)
            Transaction Count: \(data.transactionCount)
            """
            
            summary.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 80
            
            // Category breakdown
            "Category Breakdown:".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 20
            
            for (category, amount) in data.categoryTotals.sorted(by: { $0.value > $1.value }) {
                let categoryText = "\(category): \(amount.currencyFormatted)"
                categoryText.draw(at: CGPoint(x: 70, y: yPosition), withAttributes: bodyAttributes)
                yPosition += 15
            }
            
            yPosition += 20
            
            // Recent transactions
            "Recent Transactions:".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 20
            
            let recentTransactions = Array(data.transactions.prefix(10))
            for transaction in recentTransactions {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                
                let transactionText = "\(dateFormatter.string(from: transaction.date ?? Date())) - \(transaction.note ?? "No note") - \((transaction.amount as Decimal?)?.currencyFormatted ?? "$0.00")"
                transactionText.draw(at: CGPoint(x: 70, y: yPosition), withAttributes: bodyAttributes)
                yPosition += 15
            }
        }
        
        return pdfData
    }
    
    private func generateCSVData(transactions: [Transaction]) -> Data {
        let csvHeader = "Date,Type,Category,Amount,Note\n"
        var csvContent = csvHeader
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        
        for transaction in transactions {
            let date = dateFormatter.string(from: transaction.date ?? Date())
            let type = transaction.type ?? "unknown"
            let category = transaction.category?.name ?? "Uncategorized"
            let amount = transaction.amount?.stringValue ?? "0"
            let note = transaction.note?.replacingOccurrences(of: ",", with: ";") ?? ""
            
            let row = "\(date),\(type),\(category),\(amount),\(note)\n"
            csvContent += row
        }
        
        return csvContent.data(using: .utf8) ?? Data()
    }
    
    private func saveFile(data: Data, fileName: String) throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        
        return fileURL
    }
}

// MARK: - Data Models

struct ReportData {
    let scope: ExportService.ExportScope
    let totalIncome: Decimal
    let totalExpenses: Decimal
    let balance: Decimal
    let transactionCount: Int
    let categoryTotals: [String: Decimal]
    let transactions: [Transaction]
}

// MARK: - Enums

enum ExportError: LocalizedError {
    case invalidDateRange
    case failedToGeneratePDF
    case failedToGenerateCSV
    case failedToSaveFile
    
    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Invalid date range for export"
        case .failedToGeneratePDF:
            return "Failed to generate PDF report"
        case .failedToGenerateCSV:
            return "Failed to generate CSV data"
        case .failedToSaveFile:
            return "Failed to save export file"
        }
    }
}

// MARK: - Extensions

extension Date {
    func ISO8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
} 