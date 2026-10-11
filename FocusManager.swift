import SwiftUI
import UserNotifications
#if BLOCKING
import FamilyControls
import ManagedSettings
import DeviceActivity
#endif

/// يدير الجلسة. في النسخة الكاملة (BLOCKING) يضيف حجب التطبيقات عبر Screen Time.
@MainActor
final class FocusManager: ObservableObject {

    private enum Keys {
        static let selection = "focus_selection"
        static let end = "focus_end_date"
    }

    @Published private(set) var endDate: Date?
    @Published var authError: String?

    #if BLOCKING
    @Published var selection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }
    @Published private(set) var authorized = false
    private let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()
    private let activity = DeviceActivityName("focus_session")
    #endif

    init() {
        #if BLOCKING
        loadSelection()
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        #endif
        if let t = UserDefaults.standard.object(forKey: Keys.end) as? Date {
            if t > Date() {
                endDate = t
                UIApplication.shared.isIdleTimerDisabled = true
            } else {
                stop()
            }
        }
    }

    var isActive: Bool {
        guard let e = endDate else { return false }
        return e > Date()
    }

    var canStart: Bool {
        #if BLOCKING
        return authorized && hasSelection
        #else
        return true
        #endif
    }

    // MARK: - الجلسة
    func start(duration: TimeInterval) {
        guard canStart else { return }
        let end = Date().addingTimeInterval(duration)

        #if BLOCKING
        store.shield.applications =
            selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains =
            selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        // رفع الحجب تلقائيًا عبر الـ extension (الحد الأدنى 15 دقيقة)
        let cal = Calendar.current
        let comps: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents(comps, from: Date()),
            intervalEnd: cal.dateComponents(comps, from: end),
            repeats: false
        )
        center.stopMonitoring([activity])
        try? center.startMonitoring(activity, during: schedule)
        #endif

        scheduleEndNotification(at: end)
        UserDefaults.standard.set(end, forKey: Keys.end)
        endDate = end
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        #if BLOCKING
        store.clearAllSettings()
        center.stopMonitoring([activity])
        #endif
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["focus_end"])
        UserDefaults.standard.removeObject(forKey: Keys.end)
        endDate = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - إشعار انتهاء الوقت
    private func scheduleEndNotification(at end: Date) {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "انتهى وقت التركيز"
        content.body = "أحسنت! تقدر ترتاح دلوقتي."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        c.removePendingNotificationRequests(withIdentifiers: ["focus_end"])
        c.add(UNNotificationRequest(identifier: "focus_end", content: content, trigger: trigger))
    }

    #if BLOCKING
    // MARK: - الإذن واختيار التطبيقات
    var hasSelection: Bool {
        !(selection.applicationTokens.isEmpty
          && selection.categoryTokens.isEmpty
          && selection.webDomainTokens.isEmpty)
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authError = nil
        } catch {
            authError = "تعذر الحصول على الإذن: \(error.localizedDescription)"
        }
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: Keys.selection)
        }
    }

    private func loadSelection() {
        guard let data = UserDefaults.standard.data(forKey: Keys.selection),
              let s = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        selection = s
    }
    #endif
}
