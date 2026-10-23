import AgentLedgerCore
import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var model: AppModel
    @State private var tab: PanelTab = .summary
    @State private var showingSettings = false
    @State private var loginError: String?
    @State private var loginDetail = LaunchAtLogin.detail

    var body: some View {
        Group {
            if model.settings.didCompleteSetup {
                configured
            } else {
                FittingPanel(width: 400) {
                    SetupWizard(model: model)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .onAppear {
            model.keepBreakdownVisible()
            Task { await model.refreshIfStale(seconds: 60) }
        }
        .onChange(of: model.settings.showCodex) { _, _ in model.keepBreakdownVisible() }
        .onChange(of: model.settings.showCursor) { _, _ in model.keepBreakdownVisible() }
    }

    private var configured: some View {
        FittingPanel(width: 400) {
            VStack(alignment: .leading, spacing: 16) {
                header
                tabContent
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if showingSettings {
            settings
        } else {
            switch tab {
            case .summary:
                summary
            case .detail:
                detail
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                HStack(spacing: 8) {
                    Text("Agent Ledger")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    refreshButton
                    settingsButton
                }
                sectionPicker
            }
            Text(showingSettings ? "Settings" : updatedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            sectionButton(.summary)
            sectionButton(.detail)
        }
        .padding(2)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionButton(_ item: PanelTab) -> some View {
        let selected = !showingSettings && tab == item
        return Button {
            tab = item
            showingSettings = false
        } label: {
            Text(item.rawValue)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            if model.isRefreshing {
                ProgressView().controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh now")
        .disabled(model.isRefreshing)
    }

    private var settingsButton: some View {
        Button {
            showingSettings.toggle()
        } label: {
            Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(showingSettings ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .help(showingSettings ? "Close settings" : "Settings")
        .accessibilityAddTraits(showingSettings ? .isSelected : [])
    }

    private var updatedLabel: String {
        guard let lastUpdated = model.lastUpdated else { return "Checking Codex and Cursor" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: lastUpdated, relativeTo: .now))"
    }

    private func providerSection<Value, Content: View>(
        title: String,
        load: ProviderLoad<Value>,
        warning: String?,
        @ViewBuilder ready: (Value) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusLabel(load, warning: warning))
                    .font(.caption)
                    .foregroundStyle(warning == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
            switch load {
            case .loading:
                ProgressView().controlSize(.small)
            case .unavailable(let message), .signedOut(let message), .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ready(let value):
                ready(value)
                if let warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusLabel<Value>(_ load: ProviderLoad<Value>, warning: String?) -> String {
        if warning != nil { return "Saved" }
        switch load {
        case .loading: return "Checking"
        case .ready: return "Live"
        case .signedOut: return "Signed out"
        case .unavailable: return "Not installed"
        case .failed: return "Unavailable"
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.settings.showCodex {
                providerSection(title: "Codex", load: model.codex, warning: model.codexWarning) { usage in
                    CodexCard(usage: usage, style: .summary)
                }
            }
            if model.settings.showCursor {
                providerSection(title: "Cursor", load: model.cursor, warning: model.cursorWarning) { usage in
                    CursorCard(usage: usage, style: .summary)
                }
            }
            if !model.settings.showCodex && !model.settings.showCursor {
                Text("Both tools are hidden. Turn one on in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(model.copied ? "Copied" : "Copy summary") {
                    model.copySummary()
                }
                .controlSize(.small)
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.settings.showCodex, case .ready(let usage) = model.codex, CodexCard.showsDetail(usage) {
                providerSection(title: "Codex", load: model.codex, warning: model.codexWarning) { _ in
                    CodexCard(usage: usage, style: .detail)
                }
            }
            if model.settings.showCursor, case .ready(let usage) = model.cursor, CursorCard.showsDetail(usage) {
                providerSection(title: "Cursor", load: model.cursor, warning: model.cursorWarning) { _ in
                    CursorCard(usage: usage, style: .detail)
                }
            }
            breakdown
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Session logs and edit events saved on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Source", selection: $model.breakdown) {
                if model.settings.showCodex {
                    Text(Breakdown.codex.rawValue).tag(Breakdown.codex)
                }
                if model.settings.showCursor {
                    Text(Breakdown.cursor.rawValue).tag(Breakdown.cursor)
                }
                Text(Breakdown.trend.rawValue).tag(Breakdown.trend)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Picker("Range", selection: $model.statsRange) {
                ForEach(StatsRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch model.breakdown {
            case .codex where model.settings.showCodex:
                CodexBreakdown(activity: model.codexActivity, latestAnywhere: model.codexSamples.map(\.at).max())
            case .cursor where model.settings.showCursor:
                CursorBreakdown(activity: model.cursorActivity, rangeTitle: model.statsRange.title)
            default:
                TrendBreakdown(
                    points: model.trend,
                    range: model.statsRange,
                    showCodex: model.settings.showCodex,
                    showCursor: model.settings.showCursor
                )
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show Codex", isOn: Bindable(model.settings).showCodex)
            Toggle("Show Cursor", isOn: Bindable(model.settings).showCursor)
            if !model.settings.showCodex && !model.settings.showCursor {
                Text("Turn a tool on to show it in the menu bar, Summary, and alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Refresh", selection: Bindable(model.settings).refreshMinutes) {
                Text("1 min").tag(1)
                Text("5 min").tag(5)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
            }
            Picker("Menu bar", selection: Bindable(model.settings).metric) {
                Text("Remaining").tag(MenuMetric.remaining)
                Text("Used").tag(MenuMetric.used)
                Text("Off").tag(MenuMetric.off)
            }
            Toggle("Notify at 20% and 5% left", isOn: Bindable(model.settings).alertsEnabled)
            Toggle("Refresh after sleep", isOn: Bindable(model.settings).refreshOnWake)
            Toggle("Launch at login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { enabled in
                    do {
                        try LaunchAtLogin.setEnabled(enabled)
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                    loginDetail = LaunchAtLogin.detail
                }
            ))
            .disabled(!LaunchAtLogin.isBundledApp)
            Text(loginError ?? loginDetail)
                .font(.caption)
                .foregroundStyle(loginError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)
            Text("Tokens stay in memory and are sent only to Codex or Cursor to read your own quota. Nothing is logged or uploaded elsewhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Install updates automatically", isOn: Binding(
                get: { UpdateController.shared.automaticallyDownloadsUpdates },
                set: { UpdateController.shared.automaticallyDownloadsUpdates = $0 }
            ))
            Text("Agent Ledger checks GitHub about once a day. Automatic install downloads the new build and relaunches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Check for Updates…") {
                UpdateController.shared.checkForUpdates()
            }
            .controlSize(.small)
            Button("Quit Agent Ledger") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
    }
}

private enum PanelTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case detail = "Detail"

    var id: String { rawValue }
}

private enum QuotaStyle {
    case summary
    case detail
}

private struct CodexCard: View {
    var usage: CodexUsage
    var style: QuotaStyle

    static func showsDetail(_ usage: CodexUsage) -> Bool {
        usage.pools.count > 1
            || QuotaPace.codex(usage) != nil
            || usage.credits?.unlimited == true
            || usage.credits?.balance != nil
            || !usage.unavailableModels.isEmpty
            || usage.email != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch style {
            case .summary:
                summary
            case .detail:
                detail
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if !planLine.isEmpty {
            Text(planLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if let lead = usage.pools.first {
            Text(lead.remainingText)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(UsageTone.color(usedPercent: lead.used))
            Text(lead.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Meter(usedPercent: lead.used)
        } else {
            Text("Signed in. This account did not return a quota window.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if usage.includedUsageBlocked {
            Text("Included usage is blocked on this account.")
                .font(.caption)
                .foregroundStyle(.red)
        }
        if usage.spendReached {
            Text("Spend control limit reached.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let email = usage.email {
            Text(email)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        ForEach(Array(usage.pools.dropFirst())) { pool in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(pool.title)
                    Spacer()
                    Text("\(pool.remainingText) left")
                }
                .font(.caption)
                Meter(usedPercent: pool.used)
                if let reset = pool.reset {
                    Text(Format.resetLabel(date: reset, now: .now))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let pace = QuotaPace.codex(usage) {
            Text(pace.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let credits = usage.credits {
            if credits.unlimited {
                Text("Credit balance is unlimited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let balance = credits.balance {
                Text("Credit balance \(Format.quantity(balance))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if !usage.unavailableModels.isEmpty {
            Text("Unavailable right now: \(usage.unavailableModels.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planLine: String {
        Format.planName(usage.planType) ?? ""
    }
}

private extension CodexUsage {
    var pools: [QuotaPool] {
        var rows: [QuotaPool] = []
        if let spend, let percent = spend.resolvedRemainingPercent, let used = spend.resolvedUsedPercent {
            let unit = spend.unit == "credit" ? "credits" : spend.unit
            var detail = "\(unit) left of \(Format.quantity(spend.limit)) · \(Format.compactPercent(percent)) remaining"
            if let reset = spend.resetsAt {
                detail += " · \(Format.resetLabel(date: reset, now: .now))"
            }
            rows.append(QuotaPool(
                id: "spend",
                title: unit.capitalized,
                remainingText: Format.quantity(spend.resolvedRemaining),
                detail: detail,
                used: used,
                reset: spend.resetsAt
            ))
        }
        for window in windows {
            var detail = "\(Format.precisePercent(window.usedPercent)) of the \(window.title.lowercased()) window used"
            if let reset = window.resetsAt {
                detail += " · \(Format.resetLabel(date: reset, now: .now))"
            }
            rows.append(QuotaPool(
                id: window.id,
                title: window.title,
                remainingText: Format.compactPercent(window.remainingPercent),
                detail: detail,
                used: window.usedPercent,
                reset: window.resetsAt
            ))
        }
        return rows.sorted { $0.used > $1.used }
    }
}

private struct QuotaPool: Identifiable {
    var id: String
    var title: String
    var remainingText: String
    var detail: String
    var used: Double
    var reset: Date?
}

private struct CursorCard: View {
    var usage: CursorUsage
    var style: QuotaStyle

    static func showsDetail(_ usage: CursorUsage) -> Bool {
        usage.autoUsedPercent != nil
            || usage.apiUsedPercent != nil
            || usage.remainingCents != nil
            || usage.displayMessage != nil
            || QuotaPace.cursor(usage) != nil
            || usage.onDemand != nil
            || !usage.autoModels.isEmpty
            || usage.email != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch style {
            case .summary:
                summary
            case .detail:
                detail
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if !planLine.isEmpty {
            Text(planLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if let remaining = usage.remainingPercent {
            Text(Format.compactPercent(remaining))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(UsageTone.color(usedPercent: usage.totalUsedPercent ?? 0))
            Text("of this \(usage.periodLabel?.lowercased() ?? "billing") window left")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let used = usage.totalUsedPercent {
            Meter(usedPercent: used)
        }
        if let end = usage.windowEnd {
            Text(Format.resetLabel(date: end, now: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let email = usage.email {
            Text(email)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if let remaining = usage.remainingCents, let limit = usage.limitCents, limit > 0 {
            Text("\(Format.dollars(cents: remaining)) left of \(Format.dollars(cents: limit)) included")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let auto = usage.autoUsedPercent {
            splitRow("Auto", used: auto)
        }
        if let api = usage.apiUsedPercent {
            splitRow("API", used: api)
        }
        if let message = usage.displayMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let pace = QuotaPace.cursor(usage) {
            Text(pace.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let onDemand = usage.onDemand {
            Text(onDemand.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !usage.autoModels.isEmpty {
            Text(autoPool)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planLine: String {
        [Format.planName(usage.planName), usage.periodLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var autoPool: String {
        let shown = usage.autoModels.prefix(4).joined(separator: ", ")
        let extra = usage.autoModels.count - min(usage.autoModels.count, 4)
        if extra > 0 { return "Auto pool: \(shown), +\(extra)" }
        return "Auto pool: \(shown)"
    }

    private func splitRow(_ title: String, used: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Format.precisePercent(used)) used · \(Format.compactPercent(max(0, 100 - used))) left")
            }
            .font(.caption)
            Meter(usedPercent: used)
        }
    }
}

private struct CodexBreakdown: View {
    var activity: CodexActivity
    var latestAnywhere: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if activity.turnCount == 0 {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(activity.sessionCount) sessions · \(activity.turnCount) turns")
                    .font(.callout)
                Text("\(Format.tokens(activity.input)) in · \(Format.tokens(activity.cached)) cached · \(Format.tokens(activity.output)) out · \(Format.tokens(activity.reasoning)) reasoning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DayBars(days: activity.days)
                tokenTable(activity.models, empty: "No model data")
                tokenTable(activity.projects, empty: "No project data")
            }
        }
    }

    private var emptyMessage: String {
        if !activity.logsFound {
            return "Codex has not written session logs on this Mac yet."
        }
        if let latestAnywhere {
            return "No sessions in this range. The latest local session was \(Format.dayLabel(latestAnywhere))."
        }
        return "No Codex sessions in this range."
    }

    private func tokenTable(_ rows: [NamedTokens], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if rows.isEmpty {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack {
                        Text(row.name).lineLimit(1)
                        Spacer()
                        Text("\(Format.tokens(row.total)) · \(row.sessions)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct CursorBreakdown: View {
    var activity: CursorActivity
    var rangeTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local edit events from Cursor, not the billing ledger.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !activity.databaseFound {
                Text("Cursor has not recorded local edit history yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if activity.editCount == 0 && activity.commitCount == 0 {
                Text("No local Cursor activity in the last \(rangeTitle).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if activity.editCount > 0 {
                    Text("\(activity.editCount) edits")
                        .font(.callout)
                    countList(activity.editsByModel)
                    countList(activity.editsByExtension)
                }
                if activity.commitCount > 0 {
                    Text("\(activity.commitCount) scored commits")
                        .font(.callout)
                    if let average = activity.averageAIPercent {
                        Text("Average AI share \(Format.precisePercent(normalized(average)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Format.tokens(activity.composerLines)) composer lines · \(Format.tokens(activity.humanLines)) human lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func normalized(_ value: Double) -> Double {
        value <= 1.5 ? value * 100 : value
    }

    private func countList(_ rows: [CountStat]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                HStack {
                    Text(row.name).lineLimit(1)
                    Spacer()
                    Text("\(row.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

private struct TrendBreakdown: View {
    var points: [TrendPoint]
    var range: StatsRange
    var showCodex: Bool
    var showCursor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Percent of each live window that was used. The line drops when a window resets. Samples are saved only on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showCodex {
                trend("Codex", provider: "codex")
            }
            if showCursor {
                trend("Cursor", provider: "cursor")
            }
            if !showCodex && !showCursor {
                Text("Turn a tool on in Settings to see its trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trend(_ title: String, provider: String) -> some View {
        let start = range.start(now: .now)
        let series = points.filter { $0.provider == provider && $0.at >= start }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if let last = series.last {
                    Text(Format.precisePercent(last.usedPercent) + " used")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            if series.count < 2 {
                Text(series.isEmpty ? "No samples in this range yet." : "One sample so far. The line appears after the next change.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                TrendChart(points: series)
            }
        }
    }
}

private struct Meter: View {
    var usedPercent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(UsageTone.color(usedPercent: usedPercent))
                    .frame(width: geo.size.width * min(max(usedPercent, 0) / 100, 1))
            }
        }
        .frame(height: 7)
        .accessibilityLabel("\(Format.precisePercent(usedPercent)) used")
    }
}

private struct DayBars: View {
    var days: [DayTokens]

    var body: some View {
        let peak = max(days.map(\.totalTokens).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.totalTokens == 0 ? Color.secondary.opacity(0.25) : Color.accentColor)
                        .frame(height: max(3, 36 * CGFloat(day.totalTokens) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(Format.dayLabel(day.day)), \(Format.tokens(day.totalTokens)) tokens")
                }
            }
            .frame(height: 36)
            Text("Each bar is a day, oldest on the left.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct TrendChart: View {
    var points: [TrendPoint]

    var body: some View {
        GeometryReader { geo in
            let start = points[0].at
            let end = max(points[points.count - 1].at, start.addingTimeInterval(1))
            let span = end.timeIntervalSince(start)
            Path { path in
                for (index, point) in points.enumerated() {
                    let x = span == 0 ? 0 : geo.size.width * point.at.timeIntervalSince(start) / span
                    let y = geo.size.height * (1 - min(max(point.usedPercent, 0), 100) / 100)
                    let point = CGPoint(x: x, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(height: 44)
        .accessibilityLabel("Usage trend")
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Sizes the menu-bar panel to the active tab. The menu-bar window does not follow
/// SwiftUI's ideal height when it shrinks, so the AppKit frame is updated as well.
private struct FittingPanel<Content: View>: View {
    var width: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var idealHeight: CGFloat = 0

    private var maxHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        return max(360, visible - 8)
    }

    private var displayHeight: CGFloat? {
        guard idealHeight > 80 else { return nil }
        return min(idealHeight, maxHeight)
    }

    var body: some View {
        Group {
            if let displayHeight, idealHeight > maxHeight {
                ScrollView(.vertical) {
                    fittedContent
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .frame(width: width, height: displayHeight, alignment: .top)
            } else {
                fittedContent
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: width, alignment: .top)
            }
        }
        .onPreferenceChange(PanelHeightKey.self) { newValue in
            guard newValue > 80 else { return }
            idealHeight = newValue
            PanelWindow.schedule(width: width, height: min(newValue, maxHeight))
        }
        .onAppear {
            guard let displayHeight else { return }
            PanelWindow.schedule(width: width, height: displayHeight)
        }
    }

    private var fittedContent: some View {
        content()
            .frame(width: width, alignment: .topLeading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                }
            }
    }
}

@MainActor
private enum PanelWindow {
    /// The menu-bar window is placed before its real height is known, which leaves a
    /// gap under the menu bar. Later resizes correct it. Repeat the correction until
    /// the window is on screen and its top edge sits on the menu bar.
    static func schedule(width: CGFloat, height: CGFloat) {
        Task { @MainActor in
            for _ in 0..<8 {
                if apply(width: width, height: height) { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private static func apply(width: CGFloat, height: CGFloat) -> Bool {
        guard let window = menuBarWindow(width: width),
              let screen = window.screen ?? NSScreen.main else { return false }
        let top = screen.visibleFrame.maxY
        var next = window.frame
        next.size = NSSize(width: width, height: height)
        next.origin.y = top - height
        let placed = abs(window.frame.height - height) < 0.5 && abs(window.frame.maxY - top) < 0.5
        if placed { return true }
        window.setFrame(next, display: true, animate: false)
        return false
    }

    private static func menuBarWindow(width: CGFloat) -> NSWindow? {
        NSApp.windows.first { window in
            guard window.isVisible, let screen = window.screen ?? NSScreen.main else { return false }
            let frame = window.frame
            return abs(frame.width - width) < 40 && frame.maxY > screen.visibleFrame.midY
        }
    }
}

private enum UsageTone {
    static func color(usedPercent: Double) -> Color {
        switch usedPercent {
        case ..<70: .green
        case ..<90: .orange
        default: .red
        }
    }
}
