import Foundation
import Vision
import VisionKit
import UIKit
import SwiftUI

// MARK: - Receipt Scanner Manager
class ReceiptScannerManager: ObservableObject {
    static let shared = ReceiptScannerManager()
    
    @Published var isScanning = false
    @Published var scannedReceipts: [ScannedReceipt] = []
    @Published var lastScannedReceipt: ScannedReceipt?
    
    private let aiCategorizationManager = AICategorizationManager.shared
    
    private init() {
        loadScannedReceipts()
    }
    
    // MARK: - Receipt Scanning
    func scanReceipt(from image: UIImage) async throws -> ScannedReceipt {
        isScanning = true
        defer { isScanning = false }
        
        guard let cgImage = image.cgImage else {
            throw ReceiptScannerError.invalidImage
        }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            if let error = error {
                print("Text recognition error: \(error)")
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            Task { @MainActor in
                let receipt = self?.parseReceiptData(from: recognizedStrings, image: image)
                if let receipt = receipt {
                    self?.lastScannedReceipt = receipt
                    self?.scannedReceipts.append(receipt)
                    self?.saveScannedReceipts()
                }
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        // Wait for processing to complete
        while lastScannedReceipt == nil {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        return lastScannedReceipt!
    }
    
    // MARK: - Receipt Parsing
    private func parseReceiptData(from textLines: [String], image: UIImage) -> ScannedReceipt {
        var receipt = ScannedReceipt(
            id: UUID(),
            image: image,
            rawText: textLines.joined(separator: "\n"),
            date: Date(),
            total: 0.0,
            items: [],
            merchant: "",
            category: "Other"
        )
        
        // Extract merchant name (usually first few lines)
        if let merchant = extractMerchant(from: textLines) {
            receipt.merchant = merchant
        }
        
        // Extract date
        if let date = extractDate(from: textLines) {
            receipt.date = date
        }
        
        // Extract total amount
        if let total = extractTotal(from: textLines) {
            receipt.total = total
        }
        
        // Extract individual items
        receipt.items = extractItems(from: textLines)
        
        // Auto-categorize based on merchant and items
        receipt.category = aiCategorizationManager.categorizeTransaction(
            title: receipt.merchant,
            amount: receipt.total,
            notes: receipt.items.map { $0.name }.joined(separator: ", ")
        )
        
        return receipt
    }
    
    // MARK: - Data Extraction Methods
    private func extractMerchant(from lines: [String]) -> String? {
        // Look for merchant name in first few lines
        for i in 0..<min(5, lines.count) {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and common receipt headers
            if line.isEmpty || line.lowercased().contains("receipt") || line.lowercased().contains("thank you") {
                continue
            }
            
            // Check if line looks like a merchant name (not a number, not too long)
            if line.count > 3 && line.count < 50 && !line.contains("$") && !line.contains("total") {
                return line
            }
        }
        
        return nil
    }
    
    private func extractDate(from lines: [String]) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try different date formats
            if let date = dateFormatter.date(from: cleanLine) {
                return date
            }
            
            // Try other common formats
            dateFormatter.dateFormat = "MM-dd-yyyy"
            if let date = dateFormatter.date(from: cleanLine) {
                return date
            }
            
            dateFormatter.dateFormat = "MM/dd/yy"
            if let date = dateFormatter.date(from: cleanLine) {
                return date
            }
        }
        
        return nil
    }
    
    private func extractTotal(from lines: [String]) -> Double? {
        // Look for total amount (usually at the end, contains "TOTAL" or "TOTAL:")
        for line in lines.reversed() {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            if cleanLine.contains("total") {
                // Extract amount from the line
                return extractAmount(from: line)
            }
        }
        
        // If no total found, look for the largest amount
        var largestAmount: Double = 0.0
        for line in lines {
            if let amount = extractAmount(from: line), amount > largestAmount {
                largestAmount = amount
            }
        }
        
        return largestAmount > 0 ? largestAmount : nil
    }
    
    private func extractAmount(from line: String) -> Double? {
        // Remove currency symbols and extract number
        let cleanLine = line.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for decimal numbers
        let pattern = #"(\d+\.\d{2})"#
        let regex = try? NSRegularExpression(pattern: pattern)
        
        if let match = regex?.firstMatch(in: cleanLine, range: NSRange(cleanLine.startIndex..., in: cleanLine)) {
            let amountString = String(cleanLine[Range(match.range(at: 1), in: cleanLine)!])
            return Double(amountString)
        }
        
        return nil
    }
    
    private func extractItems(from lines: [String]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []
        
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip lines that are likely not items
            if cleanLine.isEmpty || 
               cleanLine.lowercased().contains("total") ||
               cleanLine.lowercased().contains("tax") ||
               cleanLine.lowercased().contains("subtotal") ||
               cleanLine.lowercased().contains("receipt") {
                continue
            }
            
            // Try to extract item and price
            if let item = extractItem(from: cleanLine) {
                items.append(item)
            }
        }
        
        return items
    }
    
    private func extractItem(from line: String) -> ReceiptItem? {
        // Look for pattern: item name followed by price
        let pattern = #"(.+?)\s+(\d+\.\d{2})"#
        let regex = try? NSRegularExpression(pattern: pattern)
        
        if let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            let nameRange = Range(match.range(at: 1), in: line)!
            let priceRange = Range(match.range(at: 2), in: line)!
            
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let priceString = String(line[priceRange])
            
            if let price = Double(priceString), !name.isEmpty {
                return ReceiptItem(name: name, price: price)
            }
        }
        
        return nil
    }
    
    // MARK: - Receipt Management
    func saveReceipt(_ receipt: ScannedReceipt) {
        scannedReceipts.append(receipt)
        saveScannedReceipts()
    }
    
    func deleteReceipt(_ receipt: ScannedReceipt) {
        scannedReceipts.removeAll { $0.id == receipt.id }
        saveScannedReceipts()
    }
    
    private func loadScannedReceipts() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "ScannedReceipts"),
           let receipts = try? JSONDecoder().decode([ScannedReceiptData].self, from: data) {
            scannedReceipts = receipts.compactMap { receiptData in
                guard let image = UIImage(data: receiptData.imageData) else { return nil }
                return ScannedReceipt(
                    id: receiptData.id,
                    image: image,
                    rawText: receiptData.rawText,
                    date: receiptData.date,
                    total: receiptData.total,
                    items: receiptData.items,
                    merchant: receiptData.merchant,
                    category: receiptData.category,
                    notes: receiptData.notes
                )
            }
        }
    }
    
    private func saveScannedReceipts() {
        // Convert to codable format for storage
        let receiptData = scannedReceipts.map { receipt in
            ScannedReceiptData(
                id: receipt.id,
                imageData: receipt.imageData,
                rawText: receipt.rawText,
                date: receipt.date,
                total: receipt.total,
                items: receipt.items,
                merchant: receipt.merchant,
                category: receipt.category,
                notes: receipt.notes
            )
        }
        
        if let data = try? JSONEncoder().encode(receiptData) {
            UserDefaults.standard.set(data, forKey: "ScannedReceipts")
        }
    }
}

// MARK: - Receipt Models
struct ScannedReceipt: Identifiable {
    let id: UUID
    let imageData: Data
    let rawText: String
    var date: Date
    var total: Double
    var items: [ReceiptItem]
    var merchant: String
    var category: String
    var notes: String?
    
    init(id: UUID, image: UIImage, rawText: String, date: Date, total: Double, items: [ReceiptItem], merchant: String, category: String, notes: String? = nil) {
        self.id = id
        self.imageData = image.jpegData(compressionQuality: 0.8) ?? Data()
        self.rawText = rawText
        self.date = date
        self.total = total
        self.items = items
        self.merchant = merchant
        self.category = category
        self.notes = notes
    }
    
    var image: UIImage? {
        UIImage(data: imageData)
    }
}

struct ReceiptItem: Identifiable, Codable {
    let id = UUID()
    let name: String
    let price: Double
    
    init(name: String, price: Double) {
        self.name = name
        self.price = price
    }
}

// MARK: - Storage Helper
struct ScannedReceiptData: Codable {
    let id: UUID
    let imageData: Data
    let rawText: String
    let date: Date
    let total: Double
    let items: [ReceiptItem]
    let merchant: String
    let category: String
    let notes: String?
}

// MARK: - Receipt Scanner Error
enum ReceiptScannerError: Error, LocalizedError {
    case invalidImage
    case scanningFailed
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image provided"
        case .scanningFailed:
            return "Failed to scan receipt"
        case .parsingFailed:
            return "Failed to parse receipt data"
        }
    }
}

// MARK: - Receipt Scanner View
struct ReceiptScannerView: View {
    @StateObject private var scannerManager = ReceiptScannerManager.shared
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var selectedImage: UIImage?
    @State private var showingScannedReceipt = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text("Receipt Scanner")
                        .font(DesignSystem.Typography.headlineMedium)
                        .foregroundColor(DesignSystem.Colors.onSurface)
                    
                    Text("Scan receipts to automatically extract transaction details")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DesignSystem.Spacing.xl)
                
                // Scan Options
                VStack(spacing: DesignSystem.Spacing.md) {
                    Button(action: { showingCamera = true }) {
                        HStack {
                            Image(systemName: "camera")
                            Text("Take Photo")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .primaryButtonStyle()
                    }
                    
                    Button(action: { showingImagePicker = true }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Library")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .secondaryButtonStyle()
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                
                // Recent Scans
                if !scannerManager.scannedReceipts.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Recent Scans")
                            .font(DesignSystem.Typography.titleMedium)
                            .foregroundColor(DesignSystem.Colors.onSurface)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DesignSystem.Spacing.md) {
                                ForEach(scannerManager.scannedReceipts.prefix(5)) { receipt in
                                    ReceiptThumbnailView(receipt: receipt)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                        }
                    }
                }
                
                Spacer()
            }
            .background(DesignSystem.Colors.background)
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
            }
            .sheet(isPresented: $showingScannedReceipt) {
                if let receipt = scannerManager.lastScannedReceipt {
                    ScannedReceiptDetailView(receipt: receipt)
                }
            }
            .onChange(of: selectedImage) { image in
                if let image = image {
                    Task {
                        do {
                            let receipt = try await scannerManager.scanReceipt(from: image)
                            showingScannedReceipt = true
                        } catch {
                            print("Error scanning receipt: \(error)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views
struct ReceiptThumbnailView: View {
    let receipt: ScannedReceipt
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if let image = receipt.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 100)
                    .clipped()
                    .cornerRadius(DesignSystem.CornerRadius.sm)
            }
            
            Text(receipt.merchant)
                .font(DesignSystem.Typography.labelSmall)
                .foregroundColor(DesignSystem.Colors.onSurface)
                .lineLimit(1)
            
            Text(receipt.total, format: .currency(code: "USD"))
                .font(DesignSystem.Typography.labelMedium)
                .foregroundColor(DesignSystem.Colors.primary)
                .fontWeight(.semibold)
        }
        .frame(width: 80)
    }
}

struct ScannedReceiptDetailView: View {
    let receipt: ScannedReceipt
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ExpenseViewModel
    
    init(receipt: ScannedReceipt) {
        self.receipt = receipt
        self._viewModel = StateObject(wrappedValue: ExpenseViewModel(context: PersistenceController.shared.container.viewContext))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Receipt Image
                    if let image = receipt.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    // Receipt Details
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        DetailRow(title: "Merchant", value: receipt.merchant)
                        DetailRow(title: "Date", value: receipt.date.formatted(date: .abbreviated, time: .omitted))
                        DetailRow(title: "Total", value: receipt.total.formatted(.currency(code: "USD")))
                        DetailRow(title: "Category", value: receipt.category)
                        
                        if !receipt.items.isEmpty {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                Text("Items")
                                    .font(DesignSystem.Typography.titleSmall)
                                    .foregroundColor(DesignSystem.Colors.onSurface)
                                
                                ForEach(receipt.items) { item in
                                    HStack {
                                        Text(item.name)
                                            .font(DesignSystem.Typography.bodyMedium)
                                        Spacer()
                                        Text(item.price.formatted(.currency(code: "USD")))
                                            .font(DesignSystem.Typography.bodyMedium)
                                            .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Action Buttons
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Button("Create Transaction") {
                            createTransactionFromReceipt()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .primaryButtonStyle()
                        
                        Button("Save Receipt") {
                            // Save receipt for later
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .secondaryButtonStyle()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
            }
            .navigationTitle("Receipt Details")
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
    
    private func createTransactionFromReceipt() {
        // Create transaction from receipt data
        let notes = receipt.items.map { $0.name }.joined(separator: ", ")
        viewModel.createTransactionFromReceipt(
            merchant: receipt.merchant,
            amount: receipt.total,
            date: receipt.date,
            notes: notes
        )
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.onSurfaceVariant)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.onSurface)
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
} 