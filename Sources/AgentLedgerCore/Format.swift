import Foundation

public enum Format {
    public static func compactPercent(_ value: Double) -> String {
        if value <= 0 { return "0%" }
        if value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }

    public static func precisePercent(_ value: Double) -> String {
        if value <= 0 { return "0%" }
        if value < 10 {
            return String(format: "%.1f%%", value)
        }
        return "\(Int(value.rounded()))%"
    }

    public static func quantity(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        let whole = tenths.rounded()
        let digits = abs(tenths - whole) < 0.05 ? 0 : 1
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: tenths)) ?? String(tenths)
    }

    public static func tokens(_ value: Int64) -> String {
        let number = Double(value)
        let absolute = abs(number)
        switch absolute {
        case 1_000_000_000...:
            return String(format: "%.1fB", number / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", number / 1_000_000)
        case 10_000...:
            return String(format: "%.0fk", number / 1_000)
        case 1_000...:
            return String(format: "%.1fk", number / 1_000)
        default:
            return "\(value)"
        }
    }

    public static func dollars(cents: Double) -> String {
        (cents / 100).formatted(.currency(code: "USD"))
    }

    public static func resetLabel(date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Reset due" }
        if interval < 48 * 3600 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
            return "Resets in \(max(minutes, 1))m"
        }
        if interval < 7 * 86400 {
            let days = Int(interval / 86400)
            let hours = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
            return "Resets in \(days)d \(hours)h"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "Resets \(formatter.string(from: date))"
    }

    public static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    public static func windowTitle(seconds: Double) -> String {
        switch seconds {
        case 18_000: return "5-hour"
        case 86_400: return "Daily"
        case 604_800: return "Weekly"
        default:
            if seconds < 3_600 {
                return "\(max(Int((seconds / 60).rounded()), 1))-minute"
            }
            if seconds < 86_400 {
                let hours = seconds / 3_600
                if abs(hours - hours.rounded()) < 0.05 {
                    return "\(Int(hours.rounded()))-hour"
                }
                return String(format: "%.1f-hour", hours)
            }
            let days = seconds / 86_400
            return "\(max(Int(days.rounded()), 1))-day"
        }
    }

    public static func planName(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        if name.hasPrefix("INCLUDED_USAGE_PERIOD_") {
            name = String(name.dropFirst("INCLUDED_USAGE_PERIOD_".count))
        }
        return name
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }
}

public enum MenuBarText {
    public static func title(
        codex: CodexUsage?,
        cursor: CursorUsage?,
        codexProblem: Bool,
        cursorProblem: Bool,
        metric: MenuMetric
    ) -> String {
        var parts: [String] = []
        if let codex, let text = providerPercent(used: codex.menuUsedPercent, remaining: codex.tightestRemainingPercent, metric: metric) {
            parts.append("Cx \(text)")
        } else if codexProblem {
            parts.append("Cx !")
        }
        if let cursor, let text = providerPercent(used: cursor.totalUsedPercent, remaining: cursor.remainingPercent, metric: metric) {
            parts.append("Cu \(text)")
        } else if cursorProblem {
            parts.append("Cu !")
        }
        if parts.isEmpty { return "Ledger" }
        return parts.joined(separator: "  ")
    }

    private static func providerPercent(used: Double?, remaining: Double?, metric: MenuMetric) -> String? {
        switch metric {
        case .remaining:
            guard let remaining else { return nil }
            return Format.compactPercent(remaining)
        case .used:
            guard let used else { return nil }
            return Format.compactPercent(used)
        case .off:
            return nil
        }
    }
}

public struct PaceReport: Sendable, Equatable {
    public var text: String
    public var estimated: Bool
}

public enum Pace {
    /// Stay quiet until enough of the window has elapsed to make a burn rate meaningful.
    public static let minimumElapsed = 0.15

    public static func report(usedPercent: Double, elapsedFraction: Double, estimated: Bool) -> PaceReport? {
        guard elapsedFraction >= minimumElapsed, elapsedFraction <= 1 else { return nil }
        let projected = usedPercent / elapsedFraction
        let shown = Int(projected.rounded())
        let pace: String
        if projected < 85 {
            pace = "Under pace · about \(shown)% by reset"
        } else if projected <= 100 {
            pace = "On pace · about \(shown)% by reset"
        } else {
            pace = "Over pace · about \(shown)% by reset"
        }
        if estimated {
            return PaceReport(text: "\(pace). Assumes a monthly window.", estimated: true)
        }
        return PaceReport(text: pace, estimated: false)
    }

    public static func elapsed(now: Date, start: Date, end: Date) -> Double? {
        let span = end.timeIntervalSince(start)
        guard span > 60 else { return nil }
        return min(max(now.timeIntervalSince(start) / span, 0), 1.05)
    }
}

public enum CodexActivityMath {
    public static func summarize(
        samples: [CodexTurnSample],
        range: StatsRange,
        now: Date,
        calendar: Calendar = .current,
        logsFound: Bool
    ) -> CodexActivity {
        let start = range.start(now: now, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let included = samples.filter { $0.at >= start && $0.at < tomorrow }

        var input: Int64 = 0
        var output: Int64 = 0
        var cached: Int64 = 0
        var reasoning: Int64 = 0
        var sessions = Set<String>()
        var modelSessions: [String: Set<String>] = [:]
        var projectSessions: [String: Set<String>] = [:]
        var modelTotals: [String: TokenAccumulator] = [:]
        var projectTotals: [String: TokenAccumulator] = [:]
        var dayTotals: [Date: Int64] = [:]

        for sample in included {
            input += sample.input
            output += sample.output
            cached += sample.cached
            reasoning += sample.reasoning
            sessions.insert(sample.sessionID)
            modelSessions[sample.model, default: []].insert(sample.sessionID)
            projectSessions[sample.project, default: []].insert(sample.sessionID)
            var modelBucket = modelTotals[sample.model] ?? TokenAccumulator()
            modelBucket.add(sample)
            modelTotals[sample.model] = modelBucket
            var projectBucket = projectTotals[sample.project] ?? TokenAccumulator()
            projectBucket.add(sample)
            projectTotals[sample.project] = projectBucket
            let day = calendar.startOfDay(for: sample.at)
            dayTotals[day, default: 0] += sample.input + sample.output
        }

        var days: [DayTokens] = []
        var cursor = start
        while cursor < tomorrow {
            days.append(DayTokens(day: cursor, totalTokens: dayTotals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return CodexActivity(
            sessionCount: sessions.count,
            turnCount: included.count,
            input: input,
            output: output,
            cached: cached,
            reasoning: reasoning,
            models: ranked(modelTotals, sessions: modelSessions, limit: 8),
            projects: ranked(projectTotals, sessions: projectSessions, limit: 6),
            days: days,
            latestInRange: included.map(\.at).max(),
            logsFound: logsFound
        )
    }

    private static func ranked(
        _ totals: [String: TokenAccumulator],
        sessions: [String: Set<String>],
        limit: Int
    ) -> [NamedTokens] {
        totals
            .map { name, value in
                NamedTokens(
                    name: name,
                    input: value.input,
                    output: value.output,
                    cached: value.cached,
                    reasoning: value.reasoning,
                    sessions: sessions[name]?.count ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.total == rhs.total { return lhs.name < rhs.name }
                return lhs.total > rhs.total
            }
            .prefix(limit)
            .map { $0 }
    }
}

private struct TokenAccumulator {
    var input: Int64 = 0
    var output: Int64 = 0
    var cached: Int64 = 0
    var reasoning: Int64 = 0

    mutating func add(_ sample: CodexTurnSample) {
        input += sample.input
        output += sample.output
        cached += sample.cached
        reasoning += sample.reasoning
    }
}

public enum QuotaPace {
    public static func codex(_ usage: CodexUsage, now: Date = .now) -> PaceReport? {
        if let window = usage.windows.min(by: { $0.remainingPercent < $1.remainingPercent }),
           let duration = window.durationSeconds,
           let end = window.resetsAt {
            let start = end.addingTimeInterval(-duration)
            if let elapsed = Pace.elapsed(now: now, start: start, end: end),
               let report = Pace.report(usedPercent: window.usedPercent, elapsedFraction: elapsed, estimated: false) {
                return report
            }
        }
        guard let spend = usage.spend,
              let used = spend.resolvedUsedPercent,
              let end = spend.resetsAt else {
            return nil
        }
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .month, value: -1, to: end) ?? end.addingTimeInterval(-30 * 86_400)
        guard let elapsed = Pace.elapsed(now: now, start: start, end: end) else { return nil }
        return Pace.report(usedPercent: used, elapsedFraction: elapsed, estimated: true)
    }

    public static func cursor(_ usage: CursorUsage, now: Date = .now) -> PaceReport? {
        guard let used = usage.totalUsedPercent,
              let start = usage.windowStart,
              let end = usage.windowEnd,
              let elapsed = Pace.elapsed(now: now, start: start, end: end) else {
            return nil
        }
        return Pace.report(usedPercent: used, elapsedFraction: elapsed, estimated: false)
    }
}

public enum DumpText {
    public static func render(
        _ snapshot: LedgerSnapshot,
        range: StatsRange,
        now: Date = .now,
        includeCodex: Bool = true,
        includeCursor: Bool = true
    ) -> String {
        var lines: [String] = []
        lines.append("Agent Ledger")
        lines.append("Fetched \(Format.dayLabel(snapshot.fetchedAt))")
        if includeCodex {
            lines.append("")
            lines.append("Codex")
            lines.append(contentsOf: codexLines(snapshot.codex, now: now))
        }
        if includeCursor {
            lines.append("")
            lines.append("Cursor")
            lines.append(contentsOf: cursorLines(snapshot.cursor, now: now))
        }
        if includeCodex {
            lines.append("")
            let activity = CodexActivityMath.summarize(
                samples: snapshot.codexSamples,
                range: range,
                now: now,
                logsFound: snapshot.codexLogsFound
            )
            lines.append("Codex local logs · \(range.title)")
            if activity.turnCount == 0 {
                lines.append("No turns in this range.")
            } else {
                lines.append("\(activity.sessionCount) sessions · \(activity.turnCount) turns")
                lines.append("\(Format.tokens(activity.input)) in · \(Format.tokens(activity.cached)) cached · \(Format.tokens(activity.output)) out")
                for model in activity.models {
                    lines.append("\(model.name): \(Format.tokens(model.total)) tokens · \(model.sessions) sessions")
                }
                for project in activity.projects {
                    lines.append("\(project.name): \(Format.tokens(project.total)) tokens")
                }
            }
        }
        if includeCursor {
            lines.append("")
            lines.append("Cursor local edits · \(range.title)")
            if !snapshot.cursorActivity.databaseFound {
                lines.append("No local edit database.")
            } else if snapshot.cursorActivity.editCount == 0 {
                lines.append("No edits in this range.")
            } else {
                lines.append("\(snapshot.cursorActivity.editCount) edits")
                for row in snapshot.cursorActivity.editsByModel {
                    lines.append("\(row.name): \(row.count)")
                }
            }
        }
        if !includeCodex && !includeCursor {
            lines.append("")
            lines.append("No tools selected.")
        }
        return lines.joined(separator: "\n")
    }

    private static func codexLines(_ load: ProviderLoad<CodexUsage>, now: Date) -> [String] {
        switch load {
        case .loading: return ["Loading."]
        case .unavailable(let message), .signedOut(let message), .failed(let message):
            return [message]
        case .ready(let usage):
            var lines: [String] = []
            if let plan = Format.planName(usage.planType) { lines.append(plan) }
            if let spend = usage.spend, let remaining = spend.resolvedRemainingPercent {
                let unit = spend.unit == "credit" ? "credits" : spend.unit
                lines.append("\(Format.quantity(spend.resolvedRemaining)) \(unit) left of \(Format.quantity(spend.limit)) · \(Format.compactPercent(remaining)) remaining")
                if let reset = spend.resetsAt {
                    lines.append(Format.resetLabel(date: reset, now: now))
                }
            }
            for window in usage.windows {
                lines.append("\(window.title): \(Format.compactPercent(window.remainingPercent)) remaining")
            }
            if lines.isEmpty { lines.append("Signed in. No quota windows were returned.") }
            return lines
        }
    }

    private static func cursorLines(_ load: ProviderLoad<CursorUsage>, now: Date) -> [String] {
        switch load {
        case .loading: return ["Loading."]
        case .unavailable(let message), .signedOut(let message), .failed(let message):
            return [message]
        case .ready(let usage):
            var lines: [String] = []
            var title = Format.planName(usage.planName) ?? "Cursor"
            if let period = usage.periodLabel { title += " · \(period)" }
            lines.append(title)
            if let remaining = usage.remainingPercent {
                lines.append("\(Format.compactPercent(remaining)) remaining")
            }
            if let auto = usage.autoUsedPercent {
                lines.append("Auto \(Format.precisePercent(auto)) used")
            }
            if let api = usage.apiUsedPercent {
                lines.append("API \(Format.precisePercent(api)) used")
            }
            if let end = usage.windowEnd {
                lines.append(Format.resetLabel(date: end, now: now))
            }
            if let message = usage.displayMessage { lines.append(message) }
            return lines
        }
    }
}
