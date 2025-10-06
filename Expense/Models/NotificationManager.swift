import Foundation
import UserNotifications
import SwiftUI

// MARK: - Notification Manager
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isNotificationsEnabled = false
    @Published var reminderTime = Calendar.current.date(from: DateComponents(hour: 20)) ?? Date()
    @Published var billRemindersEnabled = true
    @Published var budgetAlertsEnabled = true
    @Published var weeklyReportsEnabled = true
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private init() {
        checkNotificationPermission()
        loadSettings()
    }
    
    // MARK: - Permission Management
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            DispatchQueue.main.async { [weak self] in
                self?.isNotificationsEnabled = granted
            }
            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }
    
    private func checkNotificationPermission() {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async { [weak self] in
                self?.isNotificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Bill Reminders
    func scheduleBillReminder(for recurringTransaction: RecurringTransaction) {
        guard billRemindersEnabled && isNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Bill Reminder"
        content.body = "\(recurringTransaction.title) - $\(String(format: "%.2f", recurringTransaction.amount)) is due soon"
        content.sound = .default
        content.categoryIdentifier = "BILL_REMINDER"
        
        // Schedule reminder 2 days before due date
        let reminderDate = Calendar.current.date(byAdding: .day, value: -2, to: recurringTransaction.nextDueDate) ?? Date()
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "bill_reminder_\(recurringTransaction.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling bill reminder: \(error)")
            }
        }
    }
    
    func cancelBillReminder(for recurringTransaction: RecurringTransaction) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["bill_reminder_\(recurringTransaction.id.uuidString)"])
    }
    
    // MARK: - Budget Alerts
    func scheduleBudgetAlert(for budget: BudgetAlert, currentSpending: Double) {
        guard budgetAlertsEnabled && isNotificationsEnabled else { return }
        
        let percentage = (currentSpending / budget.amount) * 100
        
        if percentage >= 80 {
            let content = UNMutableNotificationContent()
            content.title = "Budget Alert"
            content.body = "You've used \(Int(percentage))% of your \(budget.category) budget"
            content.sound = .default
            content.categoryIdentifier = "BUDGET_ALERT"
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            
            let request = UNNotificationRequest(
                identifier: "budget_alert_\(budget.id.uuidString)",
                content: content,
                trigger: trigger
            )
            
            notificationCenter.add(request) { error in
                if let error = error {
                    print("Error scheduling budget alert: \(error)")
                }
            }
        }
    }
    
    // MARK: - Weekly Reports
    func scheduleWeeklyReport() {
        guard weeklyReportsEnabled && isNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Weekly Financial Report"
        content.body = "Check your spending summary for this week"
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_REPORT"
        
        // Schedule for every Sunday at 9 AM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "weekly_report",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling weekly report: \(error)")
            }
        }
    }
    
    // MARK: - Custom Reminders
    func scheduleCustomReminder(title: String, body: String, date: Date, identifier: String) {
        guard isNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "CUSTOM_REMINDER"
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling custom reminder: \(error)")
            }
        }
    }
    
    // MARK: - Notification Actions
    func setupNotificationActions() {
        let billReminderAction = UNNotificationAction(
            identifier: "PAY_BILL",
            title: "Pay Now",
            options: [.foreground]
        )
        
        let budgetAlertAction = UNNotificationAction(
            identifier: "VIEW_BUDGET",
            title: "View Budget",
            options: [.foreground]
        )
        
        let weeklyReportAction = UNNotificationAction(
            identifier: "VIEW_REPORT",
            title: "View Report",
            options: [.foreground]
        )
        
        let billReminderCategory = UNNotificationCategory(
            identifier: "BILL_REMINDER",
            actions: [billReminderAction],
            intentIdentifiers: [],
            options: []
        )
        
        let budgetAlertCategory = UNNotificationCategory(
            identifier: "BUDGET_ALERT",
            actions: [budgetAlertAction],
            intentIdentifiers: [],
            options: []
        )
        
        let weeklyReportCategory = UNNotificationCategory(
            identifier: "WEEKLY_REPORT",
            actions: [weeklyReportAction],
            intentIdentifiers: [],
            options: []
        )
        
        let customReminderCategory = UNNotificationCategory(
            identifier: "CUSTOM_REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            billReminderCategory,
            budgetAlertCategory,
            weeklyReportCategory,
            customReminderCategory
        ])
    }
    
    // MARK: - Settings Management
    private func loadSettings() {
        let defaults = UserDefaults.standard
        billRemindersEnabled = defaults.bool(forKey: "billRemindersEnabled")
        budgetAlertsEnabled = defaults.bool(forKey: "budgetAlertsEnabled")
        weeklyReportsEnabled = defaults.bool(forKey: "weeklyReportsEnabled")
        
        if let savedTime = defaults.object(forKey: "reminderTime") as? Date {
            reminderTime = savedTime
        }
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(billRemindersEnabled, forKey: "billRemindersEnabled")
        defaults.set(budgetAlertsEnabled, forKey: "budgetAlertsEnabled")
        defaults.set(weeklyReportsEnabled, forKey: "weeklyReportsEnabled")
        defaults.set(reminderTime, forKey: "reminderTime")
    }
    
    // MARK: - Utility Methods
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }
}

// MARK: - Budget Alert Model
struct BudgetAlert: Identifiable, Codable {
    let id: UUID
    var category: String
    var amount: Double
    var period: BudgetPeriod
    var startDate: Date
    var isActive: Bool
    
    init(category: String, amount: Double, period: BudgetPeriod, startDate: Date = Date()) {
        self.id = UUID()
        self.category = category
        self.amount = amount
        self.period = period
        self.startDate = startDate
        self.isActive = true
    }
}

enum BudgetPeriod: String, CaseIterable, Codable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    
    var displayName: String {
        return rawValue
    }
}

// MARK: - Notification Extensions
extension NotificationManager {
    func handleNotificationAction(_ actionIdentifier: String, userInfo: [AnyHashable: Any]) {
        switch actionIdentifier {
        case "PAY_BILL":
            // Navigate to bill payment screen
            NotificationCenter.default.post(name: .navigateToBillPayment, object: nil)
        case "VIEW_BUDGET":
            // Navigate to budget screen
            NotificationCenter.default.post(name: .navigateToBudget, object: nil)
        case "VIEW_REPORT":
            // Navigate to reports screen
            NotificationCenter.default.post(name: .navigateToReports, object: nil)
        default:
            break
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let navigateToBillPayment = Notification.Name("navigateToBillPayment")
    static let navigateToBudget = Notification.Name("navigateToBudget")
    static let navigateToReports = Notification.Name("navigateToReports")
} 