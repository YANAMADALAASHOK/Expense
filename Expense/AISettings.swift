import SwiftUI

// Global settings that can be accessed throughout the app
class AISettings: ObservableObject {
    // Singleton instance for app-wide access
    static let shared = AISettings()
    
    // MARK: - UI Settings
    @Published var minimumTouchTargetSize: CGFloat = 44 // Minimum size for touch targets per Apple guidelines
    @Published var minimumTextSize: CGFloat = 11 // Minimum text size for legibility
    
    // MARK: - App Settings
    @Published var defaultCurrency: String = "USD"
    @Published var showCents: Bool = true
    @Published var darkModeEnabled: Bool = false
    
    // MARK: - Data Settings
    @Published var syncEnabled: Bool = true
    @Published var backupFrequency: BackupFrequency = .daily
    
    // MARK: - Notification Settings
    @Published var notificationsEnabled: Bool = true
    @Published var reminderTime: Date = Calendar.current.date(from: DateComponents(hour: 20)) ?? Date()
    
    private init() {} // Prevent multiple instances
}

// MARK: - Supporting Types
enum BackupFrequency: String, CaseIterable {
    case hourly = "Hourly"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
} 