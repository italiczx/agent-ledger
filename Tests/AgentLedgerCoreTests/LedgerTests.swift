import Foundation
import Testing
@testable import AgentLedgerCore

@Test func codexHTTPSpendLimit() throws {
    let usage = try #require(CodexParser.parse(data: Data(codexHTTP.utf8)))
    #expect(usage.planType == "business")
    #expect(usage.windows.isEmpty)
    let spend = try #require(usage.spend)
    #expect(spend.limit == 5000)
    #expect(spend.resolvedRemaining == 3595.592407464981)
    #expect(spend.resolvedRemainingPercent == 72)
    #expect(usage.tightestRemainingPercent == 72)
    #expect(usage.credits?.hasCredits == true)
    #expect(usage.credits?.balance == nil)
    #expect(usage.unavailableModels.isEmpty)
}

@Test func codexRateWindowsAndAppServerShape() throws {
    let http = try #require(CodexParser.parse(data: Data(codexWindows.utf8)))
    #expect(http.windows.map(\.title) == ["5-hour", "Weekly"])
    #expect(http.windows[0].remainingPercent == 58)
    #expect(http.windows[1].usedPercent == 5)

    let rpc = try #require(CodexParser.parse(data: Data(codexAppServer.utf8)))
    #expect(rpc.planType == "plus")
    #expect(rpc.windows.count == 2)
    #expect(rpc.windows.contains { $0.title == "5-hour" && $0.usedPercent == 42 })
    #expect(rpc.spend?.resolvedRemainingPercent == 68)
    #expect(rpc.tightestRemainingPercent == 58)
}

@Test func cursorPeriodPrefersLivePercent() throws {
    let usage = try #require(CursorParser.parse(period: Data(cursorPeriod.utf8), plan: Data(cursorPlan.utf8), hardLimit: Data(cursorHardLimit.utf8)))
    #expect(usage.planName == "Premium")
    #expect(usage.periodLabel == "Weekly")
    #expect(usage.totalUsedPercent == 6.9555796316359695)
    #expect(usage.remainingPercent! > 93 && usage.remainingPercent! < 94)
    #expect(usage.apiUsedPercent == 0)
    #expect(usage.windowStart != nil)
    #expect(usage.windowEnd != nil)
    #expect(usage.onDemand?.label == "No on-demand cap")
    #expect(usage.autoModels.first == "default")
}

@Test func cursorPercentFallsBackToDisplayMessage() throws {
    let json = #"{"displayMessage":"You've used 64% of your included usage"}"#
    let usage = try #require(CursorParser.parse(period: Data(json.utf8), plan: nil, hardLimit: nil))
    #expect(usage.totalUsedPercent == 64)
    #expect(usage.remainingPercent == 36)
}

@Test func paceStaysQuietEarlyAndFlagsOverrun() {
    #expect(Pace.report(usedPercent: 10, elapsedFraction: 0.05, estimated: false) == nil)
    let under = Pace.report(usedPercent: 28, elapsedFraction: 0.69, estimated: true)
    #expect(under?.text.contains("Under pace") == true)
    #expect(under?.text.contains("monthly") == true)
    let over = Pace.report(usedPercent: 80, elapsedFraction: 0.4, estimated: false)
    #expect(over?.text.contains("Over pace") == true)
    #expect(over?.estimated == false)
}

@Test func sessionTokensDedupedAndGrouped() throws {
    var model = ""
    var project = ""
    var session = ""
    var seen = Set<String>()
    var samples: [CodexTurnSample] = []
    let parsed = CodexSessionScanner.parseText(
        sessionLog,
        earliest: Date(timeIntervalSince1970: 0),
        fallbackSession: "file",
        model: &model,
        project: &project,
        sessionID: &session,
        seen: &seen,
        samples: &samples
    )
    #expect(parsed.count == 1)
    #expect(parsed[0].model == "gpt-override")
    #expect(parsed[0].project == "demo")
    #expect(parsed[0].input == 100)
    #expect(parsed[0].cached == 40)
    #expect(parsed[0].output == 20)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try #require(JSONValue.isoDate("2026-10-22T12:00:00Z"))
    let activity = CodexActivityMath.summarize(
        samples: parsed,
        range: .week,
        now: now,
        calendar: calendar,
        logsFound: true
    )
    #expect(activity.sessionCount == 1)
    #expect(activity.turnCount == 1)
    #expect(activity.models.first?.name == "gpt-override")
    #expect(activity.projects.first?.name == "demo")
    #expect(activity.days.count == 7)
    #expect(activity.input == 100)
}

@Test func oldSessionFallsOutOfRange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try #require(JSONValue.isoDate("2026-10-22T12:00:00Z"))
    let sample = CodexTurnSample(
        at: try #require(JSONValue.isoDate("2026-01-01T00:00:00Z")),
        model: "old",
        project: "old",
        sessionID: "s",
        input: 5,
        output: 5,
        cached: 0,
        reasoning: 0
    )
    let activity = CodexActivityMath.summarize(samples: [sample], range: .week, now: now, calendar: calendar, logsFound: true)
    #expect(activity.turnCount == 0)
    #expect(activity.days.count == 7)
}

@Test func menuBarShowsTightestRemaining() {
    let codex = CodexParser.parse(data: Data(codexHTTP.utf8))
    let cursor = CursorParser.parse(period: Data(cursorPeriod.utf8), plan: Data(cursorPlan.utf8), hardLimit: nil)
    let title = MenuBarText.title(codex: codex, cursor: cursor, codexProblem: false, cursorProblem: false, metric: .remaining)
    #expect(title == "Cx 72%  Cu 93%")
    let used = MenuBarText.title(codex: codex, cursor: nil, codexProblem: false, cursorProblem: true, metric: .used)
    #expect(used == "Cx 28%  Cu !")
    #expect(MenuBarText.title(codex: nil, cursor: nil, codexProblem: false, cursorProblem: false, metric: .remaining) == "Ledger")
}

@Test func resetLabelUsesHoursThenDays() throws {
    let now = try #require(JSONValue.isoDate("2026-10-22T12:00:00Z"))
    #expect(Format.resetLabel(date: now.addingTimeInterval(3 * 3600 + 12 * 60), now: now) == "Resets in 3h 12m")
    #expect(Format.resetLabel(date: now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now) == "Resets in 3d 4h")
}

@Test func trendStoreThrottlesUnchangedSamples() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = directory.appendingPathComponent("trend.json")
    let first = Date(timeIntervalSince1970: 1_700_000_000)
    var points = SnapshotStore.record(points: [], provider: "codex", usedPercent: 10, at: first, url: url)
    points = SnapshotStore.record(points: points, provider: "codex", usedPercent: 10.1, at: first.addingTimeInterval(30), url: url)
    #expect(points.count == 1)
    points = SnapshotStore.record(points: points, provider: "codex", usedPercent: 12, at: first.addingTimeInterval(120), url: url)
    #expect(points.count == 2)
    let loaded = SnapshotStore.load(from: url)
    #expect(loaded.count == 2)
}

private let codexHTTP = """
{
  "plan_type": "business",
  "rate_limit": null,
  "credits": {"has_credits": true, "unlimited": false, "balance": null},
  "spend_control": {
    "reached": false,
    "individual_limit": {
      "unit": "credit",
      "limit": "5000",
      "used": "1404.407592535019",
      "remaining": "3595.592407464981",
      "used_percent": 28,
      "remaining_percent": 72,
      "reset_at": 1793491200
    }
  }
}
"""

private let codexWindows = """
{
  "plan_type": "plus",
  "rate_limit": {
    "primary_window": {"used_percent": 42, "limit_window_seconds": 18000, "reset_at": 1792700000},
    "secondary_window": {"used_percent": 5, "limit_window_seconds": 604800, "reset_at": 1793000000}
  }
}
"""

private let codexAppServer = """
{
  "result": {
    "rateLimits": {
      "limitId": "codex",
      "primary": {"usedPercent": 42, "windowDurationMins": 300, "resetsAt": 1792700000},
      "secondary": {"usedPercent": 5, "windowDurationMins": 10080, "resetsAt": 1793000000},
      "individualLimit": {"limit": "25000", "used": "8000", "remainingPercent": 68, "resetsAt": 1793000000},
      "planType": "plus"
    }
  }
}
"""

private let cursorPeriod = """
{
  "billingCycleStart": "1792481454506",
  "billingCycleEnd": "1793086254506",
  "planUsage": {"autoPercentUsed": 6.9555796316359695, "apiPercentUsed": 0, "totalPercentUsed": 6.9555796316359695},
  "displayMessage": "You've used 7% of your included usage",
  "autoBucketModels": ["default", "composer-1.5"]
}
"""

private let cursorPlan = """
{
  "planInfo": {
    "planName": "Premium",
    "includedUsagePeriod": "INCLUDED_USAGE_PERIOD_WEEKLY",
    "includedUsageResetsAt": "1793086254506"
  }
}
"""

private let cursorHardLimit = """
{"hardLimit": 2147483647}
"""

private let sessionLog = """
{"timestamp":"2026-10-20T01:00:00Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp/demo","base_instructions":{"provenance":{"model":"gpt-test"}}}}
{"timestamp":"2026-10-20T01:00:01Z","type":"turn_context","payload":{"model":"gpt-override","cwd":"/tmp/demo"}}
{"timestamp":"2026-10-20T01:00:02Z","type":"token_usage_record","payload":{"session_id":"s1","response_id":"r1","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}
{"timestamp":"2026-10-20T01:00:03Z","type":"token_usage_record","payload":{"session_id":"s1","response_id":"r1","usage":{"input_tokens":999,"output_tokens":999}}}
{"timestamp":"2026-10-20T01:00:04Z","type":"token_usage_record","payload":{"session_id":"s1","response_id":"r2","usage":{"input_tokens":0,"output_tokens":0}}}
"""
