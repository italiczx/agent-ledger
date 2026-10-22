import Foundation

public enum StatsRange: String, CaseIterable, Sendable, Codable {
    case week
    case month
    case quarter

    public var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    public var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        }
    }

    public func start(now: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: day) ?? day
    }
}

public enum MenuMetric: String, CaseIterable, Sendable, Codable {
    case remaining
    case used
    case off
}

public enum ProviderLoad<Value: Sendable>: Sendable {
    case loading
    case unavailable(String)
    case signedOut(String)
    case failed(String)
    case ready(Value)
}

public struct UsageWindow: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var durationSeconds: Double?

    public var remainingPercent: Double { max(0, 100 - usedPercent) }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?, durationSeconds: Double?) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.durationSeconds = durationSeconds
    }
}

public struct SpendLimit: Sendable, Equatable {
    public var unit: String
    public var limit: Double
    public var used: Double
    public var remaining: Double?
    public var usedPercent: Double?
    public var remainingPercent: Double?
    public var resetsAt: Date?

    public var resolvedRemainingPercent: Double? {
        if let remainingPercent { return max(0, remainingPercent) }
        if let usedPercent { return max(0, 100 - usedPercent) }
        guard limit > 0 else { return nil }
        return max(0, 100 - (used / limit * 100))
    }

    public var resolvedUsedPercent: Double? {
        if let usedPercent { return usedPercent }
        guard let remaining = resolvedRemainingPercent else { return nil }
        return max(0, 100 - remaining)
    }

    public var resolvedRemaining: Double {
        if let remaining { return remaining }
        return max(0, limit - used)
    }
}

public struct CreditBalance: Sendable, Equatable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: Double?
}

public struct CodexUsage: Sendable, Equatable {
    public var planType: String?
    public var email: String?
    public var windows: [UsageWindow]
    public var credits: CreditBalance?
    public var spend: SpendLimit?
    public var spendReached: Bool
    public var unavailableModels: [String]
    public var includedUsageBlocked: Bool

    public var tightestRemainingPercent: Double? {
        var values: [Double] = []
        if let spendRemaining = spend?.resolvedRemainingPercent {
            values.append(spendRemaining)
        }
        values.append(contentsOf: windows.map(\.remainingPercent))
        return values.min()
    }

    public var menuUsedPercent: Double? {
        guard let remaining = tightestRemainingPercent else { return nil }
        return max(0, 100 - remaining)
    }
}

public struct OnDemandStatus: Sendable, Equatable {
    public var label: String
}

public struct CursorUsage: Sendable, Equatable {
    public var planName: String?
    public var email: String?
    public var periodLabel: String?
    public var windowStart: Date?
    public var windowEnd: Date?
    public var totalUsedPercent: Double?
    public var autoUsedPercent: Double?
    public var apiUsedPercent: Double?
    public var remainingCents: Double?
    public var limitCents: Double?
    public var usedCents: Double?
    public var displayMessage: String?
    public var autoModels: [String]
    public var onDemand: OnDemandStatus?

    public var remainingPercent: Double? {
        guard let totalUsedPercent else { return nil }
        return max(0, 100 - totalUsedPercent)
    }
}

public struct NamedTokens: Sendable, Equatable, Identifiable {
    public var name: String
    public var input: Int64
    public var output: Int64
    public var cached: Int64
    public var reasoning: Int64
    public var sessions: Int
    public var id: String { name }
    public var total: Int64 { input + output }
}

public struct DayTokens: Sendable, Equatable, Identifiable {
    public var day: Date
    public var totalTokens: Int64
    public var id: TimeInterval { day.timeIntervalSinceReferenceDate }
}

public struct CodexTurnSample: Sendable, Equatable {
    public var at: Date
    public var model: String
    public var project: String
    public var sessionID: String
    public var input: Int64
    public var output: Int64
    public var cached: Int64
    public var reasoning: Int64
}

public struct CodexActivity: Sendable, Equatable {
    public var sessionCount: Int
    public var turnCount: Int
    public var input: Int64
    public var output: Int64
    public var cached: Int64
    public var reasoning: Int64
    public var models: [NamedTokens]
    public var projects: [NamedTokens]
    public var days: [DayTokens]
    public var latestInRange: Date?
    public var logsFound: Bool

    public static let empty = CodexActivity(
        sessionCount: 0,
        turnCount: 0,
        input: 0,
        output: 0,
        cached: 0,
        reasoning: 0,
        models: [],
        projects: [],
        days: [],
        latestInRange: nil,
        logsFound: false
    )
}

public struct CountStat: Sendable, Equatable, Identifiable {
    public var name: String
    public var count: Int
    public var id: String { name }
}

public struct CursorActivity: Sendable, Equatable {
    public var databaseFound: Bool
    public var editCount: Int
    public var editsByModel: [CountStat]
    public var editsByExtension: [CountStat]
    public var commitCount: Int
    public var averageAIPercent: Double?
    public var composerLines: Int64
    public var humanLines: Int64

    public static let empty = CursorActivity(
        databaseFound: false,
        editCount: 0,
        editsByModel: [],
        editsByExtension: [],
        commitCount: 0,
        averageAIPercent: nil,
        composerLines: 0,
        humanLines: 0
    )
}

public struct TrendPoint: Codable, Sendable, Equatable, Identifiable {
    public var at: Date
    public var provider: String
    public var usedPercent: Double
    public var id: String { "\(provider)-\(at.timeIntervalSinceReferenceDate)" }

    public init(at: Date, provider: String, usedPercent: Double) {
        self.at = at
        self.provider = provider
        self.usedPercent = usedPercent
    }
}

public struct LedgerSnapshot: Sendable {
    public var fetchedAt: Date
    public var codex: ProviderLoad<CodexUsage>
    public var cursor: ProviderLoad<CursorUsage>
    public var codexSamples: [CodexTurnSample]
    public var codexLogsFound: Bool
    public var cursorActivity: CursorActivity

    public init(
        fetchedAt: Date,
        codex: ProviderLoad<CodexUsage>,
        cursor: ProviderLoad<CursorUsage>,
        codexSamples: [CodexTurnSample],
        codexLogsFound: Bool,
        cursorActivity: CursorActivity
    ) {
        self.fetchedAt = fetchedAt
        self.codex = codex
        self.cursor = cursor
        self.codexSamples = codexSamples
        self.codexLogsFound = codexLogsFound
        self.cursorActivity = cursorActivity
    }
}
