import Foundation
import PDFKit
import UIKit
import SwiftUI
import CoreData

// MARK: - Export Manager
class ExportManager: ObservableObject {
    static let shared = ExportManager()
    
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    
    private init() {}
    
    // MARK: - CSV Export
    func exportToCSV(transactions: [CDTransaction], accounts: [CDAccount]) -> String {
        var csvString = "Date,Title,Amount,Category,Account,Type,Notes\n"
        
        for transaction in transactions {
            let dateString = transaction.date?.formatted(date: .numeric, time: .omitted) ?? ""
            let category = transaction.category ?? ""
            let amountString = String(transaction.amount)
            let accountName = transaction.account?.wrappedAccountName ?? ""
            let typeString = transaction.isCredit ? "Income" : "Expense"
            let notes = transaction.notes ?? ""
            
            let rowData = [dateString, category, amountString, category, accountName, typeString, notes]
            let escapedRow = rowData.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            let row = escapedRow.joined(separator: ",")
            
            csvString += row + "\n"
        }
        
        return csvString
    }
    
    // MARK: - JSON Backup
    func createJSONBackup(transactions: [CDTransaction], accounts: [CDAccount]) -> Data {
        let backup = BackupData(
            transactions: transactions.map { TransactionBackup(from: $0) },
            accounts: accounts.map { AccountBackup(from: $0) },
            exportDate: Date(),
            version: "1.0"
        )
        
        return try! JSONEncoder().encode(backup)
    }
    
    // MARK: - File Management
    func saveToDocuments(data: Data, filename: String) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    func shareFile(url: URL) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
}

// MARK: - Supporting Models
struct DateRange: Hashable {
    let startDate: Date
    let endDate: Date
    
    init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(startDate)
        hasher.combine(endDate)
    }
    
    static func == (lhs: DateRange, rhs: DateRange) -> Bool {
        return lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate
    }
    
    static func lastMonth() -> DateRange {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end ?? now
        
        return DateRange(startDate: startOfMonth, endDate: endOfMonth)
    }
    
    static func lastYear() -> DateRange {
        let calendar = Calendar.current
        let now = Date()
        let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let endOfYear = calendar.dateInterval(of: .year, for: now)?.end ?? now
        
        return DateRange(startDate: startOfYear, endDate: endOfYear)
    }
}

struct BackupData: Codable {
    let transactions: [TransactionBackup]
    let accounts: [AccountBackup]
    let exportDate: Date
    let version: String
}

struct TransactionBackup: Codable {
    let id: UUID
    let title: String
    let amount: Double
    let category: String
    let date: Date
    let type: String
    let notes: String?
    let accountId: UUID?
    
    init(from transaction: CDTransaction) {
        self.id = transaction.id ?? UUID()
        self.title = transaction.category ?? ""
        self.amount = transaction.amount
        self.category = transaction.category ?? ""
        self.date = transaction.date ?? Date()
        self.type = transaction.isCredit ? "Income" : "Expense"
        self.notes = transaction.notes
        self.accountId = transaction.account?.id
    }
}

struct AccountBackup: Codable {
    let id: UUID
    let name: String
    let balance: Double
    let accountType: String
    let metadata: [String: String]?
    
    init(from account: CDAccount) {
        self.id = account.id ?? UUID()
        self.name = account.wrappedAccountName
        self.balance = account.balance
        self.accountType = account.accountType ?? ""
        self.metadata = account.metadataDictionary
    }
}

// MARK: - Export View
struct ExportView: View {
    @StateObject private var exportManager = ExportManager.shared
    @StateObject private var viewModel: ExpenseViewModel
    @State private var selectedExportType: ExportType = .csv
    @State private var selectedDateRange: DateRange = .lastMonth()
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: ExpenseViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 60))
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text("Export Data")
                        .font(DesignSystem.Typography.headlineMedium)
                        .foregroundColor(DesignSystem.Colors.onSurface)
                    
                    Text("Export your financial data in various formats")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DesignSystem.Spacing.xl)
                
                // Export Options
                VStack(spacing: DesignSystem.Spacing.md) {
                    // Export Type Selection
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Export Format")
                            .font(DesignSystem.Typography.titleSmall)
                            .foregroundColor(DesignSystem.Colors.onSurface)
                        
                        Picker("Export Type", selection: $selectedExportType) {
                            ForEach(ExportType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Date Range Selection
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Date Range")
                            .font(DesignSystem.Typography.titleSmall)
                            .foregroundColor(DesignSystem.Colors.onSurface)
                        
                        Picker("Date Range", selection: $selectedDateRange) {
                            Text("Last Month").tag(DateRange.lastMonth())
                            Text("Last Year").tag(DateRange.lastYear())
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Export Button
                    Button(action: exportData) {
                        HStack {
                            if exportManager.isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.onPrimary))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(exportManager.isExporting ? "Exporting..." : "Export Data")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .primaryButtonStyle()
                        .disabled(exportManager.isExporting)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Progress Bar
                    if exportManager.isExporting {
                        ProgressView(value: exportManager.exportProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                }
                
                Spacer()
            }
            .background(DesignSystem.Colors.background)
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
    
    private func exportData() {
        Task {
            do {
                let transactions = viewModel.recentTransactions
                let accounts = viewModel.accounts
                
                switch selectedExportType {
                case .csv:
                    let csvString = exportManager.exportToCSV(transactions: transactions, accounts: accounts)
                    let csvData = csvString.data(using: .utf8)!
                    let filename = "transactions_\(Date().formatted(date: .numeric, time: .omitted)).csv"
                    exportedFileURL = try exportManager.saveToDocuments(data: csvData, filename: filename)
                    
                case .json:
                    let jsonData = exportManager.createJSONBackup(transactions: transactions, accounts: accounts)
                    let filename = "backup_\(Date().formatted(date: .numeric, time: .omitted)).json"
                    exportedFileURL = try exportManager.saveToDocuments(data: jsonData, filename: filename)
                }
                
                await MainActor.run {
                    showingShareSheet = true
                }
            } catch {
                print("Export error: \(error)")
            }
        }
    }
}

// MARK: - Supporting Types
enum ExportType: CaseIterable {
    case csv
    case json
    
    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .json: return "JSON"
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 