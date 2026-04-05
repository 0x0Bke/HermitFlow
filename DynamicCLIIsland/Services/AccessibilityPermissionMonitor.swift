import ApplicationServices

struct AccessibilityPermissionMonitor {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
