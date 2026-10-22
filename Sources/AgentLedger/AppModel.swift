import AgentLedgerCore
import AppKit
import Observation

@MainActor
@Observable
final class SettingsStore {
    var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: Keys.refresh) }
    }

    var metric: MenuMetric {
        didSet { UserDefaults.standard.set(metric.rawValue, forKey: Keys.metric) }
    }

    var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: Keys.alerts) }
    }

    var showCodex: Bool {
        didSet { UserDefaults.standard.set(showCodex, forKey: Keys.showCodex) }
    }

    var showCursor: Bool {
        didSet { UserDefaults.standard.set(showCursor, forKey: Keys.showCursor) }
    }

    /// Refresh when the Mac wakes. Off keeps the last quota until the normal interval.
    var refreshOnWake: Bool {
        didSet { UserDefaults.standard.set(refreshOnWake, forKey: Keys.refreshOnWake) }
    }

    var didCompleteSetup: Bool {
        didSet { UserDefaults.standard.set(didCompleteSetup, forKey: Keys.setupComplete) }
    }

    init() {
        let defaults = UserDefaults.standard
        let minutes = defaults.object(forKey: Keys.refresh) as? Int ?? 5
        refreshMinutes = [1, 5, 15, 30, 60].contains(minutes) ? minutes : 5
        metric = MenuMetric(rawValue: defaults.string(forKey: Keys.metric) ?? "") ?? .remaining
        alertsEnabled = defaults.object(forKey: Keys.alerts) == nil ? true : defaults.bool(forKey: Keys.alerts)
        showCodex = defaults.object(forKey: Keys.showCodex) == nil ? true : defaults.bool(forKey: Keys.showCodex)
        showCursor = defaults.object(forKey: Keys.showCursor) == nil ? true : defaults.bool(forKey: Keys.showCursor)
        refreshOnWake = defaults.object(forKey: Keys.refreshOnWake) == nil ? true : defaults.bool(forKey: Keys.refreshOnWake)
        didCompleteSetup = defaults.bool(forKey: Keys.setupComplete)
    }

    private enum Keys {
        static let refresh = "agentledger.refreshMinutes"
        static let metric = "agentledger.metric"
        static let alerts = "agentledger.alerts"
        static let showCodex = "agentledger.showCodex"
        static let showCursor = "agentledger.showCursor"
        static let refreshOnWake = "agentledger.refreshOnWake"
        static let statsRange = "agentledger.statsRange"
        static let setupComplete = "agentledger.didCompleteSetup"
    }

    static func savedRange() -> StatsRange {
        StatsRange(rawValue: UserDefaults.standard.string(forKey: Keys.statsRange) ?? "") ?? .week
    }

    static func saveRange(_ range: StatsRange) {
        UserDefaults.standard.set(range.rawValue, forKey: Keys.statsRange)
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings = SettingsStore()
    var codex: ProviderLoad<CodexUsage> = .loading
    var cursor: ProviderLoad<CursorUsage> = .loading
    var codexWarning: String?
    var cursorWarning: String?
    var codexSamples: [CodexTurnSample] = []
    var codexLogsFound = false
    var cursorActivity: CursorActivity = .empty
    var trend: [TrendPoint] = []
    var statsRange: StatsRange = SettingsStore.savedRange() {
        didSet {
            SettingsStore.saveRange(statsRange)
            guard oldValue != statsRange else { return }
            cursorActivity = CursorLocalStats.load(range: statsRange)
        }
    }
    var breakdown: Breakdown = .codex
    var lastUpdated: Date?
    var isRefreshing = false
    var copied = false
    /// Step shown by the first-run wizard. Shared so the window and the menu bar stay together.
    var setupStep = 0

    private var didStart = false
    private var inFlight: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?

    var menuTitle: String {
        if settings.metric == .off { return "Ledger" }
        if lastUpdated == nil {
            let codexPending = settings.showCodex && isLoading(codex)
            let cursorPending = settings.showCursor && isLoading(cursor)
            if (codexPending || cursorPending), ready(codex) == nil, ready(cursor) == nil {
                return "Ledger …"
            }
        }
        return MenuBarText.title(
            codex: settings.showCodex ? ready(codex) : nil,
            cursor: settings.showCursor ? ready(cursor) : nil,
            codexProblem: settings.showCodex && showsProblem(codex, warning: codexWarning),
            cursorProblem: settings.showCursor && showsProblem(cursor, warning: cursorWarning),
            metric: settings.metric
        )
    }

    var codexActivity: CodexActivity {
        CodexActivityMath.summarize(
            samples: codexSamples,
            range: statsRange,
            now: .now,
            logsFound: codexLogsFound
        )
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        trend = SnapshotStore.load()
        cursorActivity = CursorLocalStats.load(range: statsRange)
        loopTask = Task { await loop() }
        Task { await refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard AppModel.shared.settings.refreshOnWake else { return }
                await AppModel.shared.refresh()
            }
        }
    }

    func refreshIfStale(seconds: TimeInterval) async {
        guard let lastUpdated else {
            await refresh()
            return
        }
        if Date().timeIntervalSince(lastUpdated) >= seconds {
            await refresh()
        }
    }

    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            await self.load()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    func copySummary() {
        let snapshot = LedgerSnapshot(
            fetchedAt: lastUpdated ?? .now,
            codex: codex,
            cursor: cursor,
            codexSamples: codexSamples,
            codexLogsFound: codexLogsFound,
            cursorActivity: cursorActivity
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            DumpText.render(
                snapshot,
                range: statsRange,
                includeCodex: settings.showCodex,
                includeCursor: settings.showCursor
            ),
            forType: .string
        )
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func load() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let range = statsRange
        let snapshot = await LedgerService.refresh(range: range)
        apply(snapshot)
        await UsageAlerts.consider(
            codex: settings.showCodex ? ready(codex) : nil,
            cursor: settings.showCursor ? ready(cursor) : nil,
            enabled: settings.alertsEnabled
        )
    }

    private func apply(_ snapshot: LedgerSnapshot) {
        lastUpdated = snapshot.fetchedAt
        codexSamples = snapshot.codexSamples
        codexLogsFound = snapshot.codexLogsFound
        cursorActivity = snapshot.cursorActivity
        codex = merge(current: codex, incoming: snapshot.codex, warning: &codexWarning)
        cursor = merge(current: cursor, incoming: snapshot.cursor, warning: &cursorWarning)
        if case .ready(let usage) = snapshot.codex {
            trend = SnapshotStore.record(
                points: trend,
                provider: "codex",
                usedPercent: usage.menuUsedPercent,
                at: snapshot.fetchedAt
            )
        }
        if case .ready(let usage) = snapshot.cursor {
            trend = SnapshotStore.record(
                points: trend,
                provider: "cursor",
                usedPercent: usage.totalUsedPercent,
                at: snapshot.fetchedAt
            )
        }
    }

    private func merge<Value>(
        current: ProviderLoad<Value>,
        incoming: ProviderLoad<Value>,
        warning: inout String?
    ) -> ProviderLoad<Value> {
        switch incoming {
        case .ready:
            warning = nil
            return incoming
        case .failed(let message):
            if case .ready = current {
                warning = message
                return current
            }
            warning = nil
            return incoming
        default:
            warning = nil
            return incoming
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            let interval = TimeInterval(settings.refreshMinutes * 60)
            guard let lastUpdated else {
                await refresh()
                continue
            }
            if Date().timeIntervalSince(lastUpdated) >= interval {
                await refresh()
            }
        }
    }

    func keepBreakdownVisible() {
        switch breakdown {
        case .codex where !settings.showCodex:
            breakdown = settings.showCursor ? .cursor : .trend
        case .cursor where !settings.showCursor:
            breakdown = settings.showCodex ? .codex : .trend
        default:
            break
        }
    }

    private func isLoading<Value>(_ load: ProviderLoad<Value>) -> Bool {
        if case .loading = load { return true }
        return false
    }

    private func ready<Value>(_ load: ProviderLoad<Value>) -> Value? {
        if case .ready(let value) = load { return value }
        return nil
    }

    private func showsProblem<Value>(_ load: ProviderLoad<Value>, warning: String?) -> Bool {
        if warning != nil { return true }
        switch load {
        case .failed, .signedOut: return true
        default: return false
        }
    }
}

enum Breakdown: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case cursor = "Cursor"
    case trend = "Trend"
    var id: String { rawValue }
}
