import DeviceActivity
import ManagedSettings

/// يعمل في الخلفية بواسطة النظام: عند انتهاء مدة الجلسة يرفع الحجب
/// حتى لو كان التطبيق مغلقًا.
class FocusMonitor: DeviceActivityMonitor {
    let store = ManagedSettingsStore()

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        store.clearAllSettings()
    }
}
