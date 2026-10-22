import AgentLedgerCore
import ServiceManagement
import UserNotifications

enum UsageAlerts {
    static func consider(codex: CodexUsage?, cursor: CursorUsage?, enabled: Bool) async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
        case .authorized, .provisional:
            break
        default:
            return
        }
        if let codex, let remaining = codex.tightestRemainingPercent {
            await notify(
                center,
                provider: "Codex",
                key: "codex",
                remaining: remaining,
                reset: codex.spend?.resetsAt ?? codex.windows.compactMap(\.resetsAt).min()
            )
        }
        if let cursor, let remaining = cursor.remainingPercent {
            await notify(center, provider: "Cursor", key: "cursor", remaining: remaining, reset: cursor.windowEnd)
        }
    }

    private static func notify(
        _ center: UNUserNotificationCenter,
        provider: String,
        key: String,
        remaining: Double,
        reset: Date?
    ) async {
        let threshold: Int
        if remaining <= 5 {
            threshold = 5
        } else if remaining <= 20 {
            threshold = 20
        } else {
            return
        }
        let bucket = reset.map { String(Int($0.timeIntervalSince1970)) } ?? "open"
        let id = "agentledger.\(key).\(threshold).\(bucket)"
        let defaultsKey = "agentledger.alerted.\(id)"
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(provider) usage is low"
        content.body = "\(Format.compactPercent(remaining)) of this window is left."
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await center.add(request)
            UserDefaults.standard.set(true, forKey: defaultsKey)
        } catch {
            return
        }
    }
}

enum LaunchAtLogin {
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isBundledApp else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static var detail: String {
        guard isBundledApp else {
            return "Open the AgentLedger app to enable this. swift run keeps a Dock icon and cannot register a login item."
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Opens when you log in."
        case .requiresApproval:
            return "Approve Agent Ledger in System Settings → General → Login Items."
        case .notRegistered:
            return "Agent Ledger stays closed until you open it."
        case .notFound:
            return "macOS could not find the app bundle."
        default:
            return ""
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
