import Foundation

public enum LedgerService {
    public static func refresh(range: StatsRange, now: Date = .now) async -> LedgerSnapshot {
        async let codex = CodexClient.fetch()
        async let cursor = CursorClient.fetch()
        let scan = CodexSessionScanner.scan(now: now)
        let cursorActivity = CursorLocalStats.load(range: range, now: now)
        return LedgerSnapshot(
            fetchedAt: now,
            codex: await codex,
            cursor: await cursor,
            codexSamples: scan.samples,
            codexLogsFound: scan.logsFound,
            cursorActivity: cursorActivity
        )
    }
}

public enum SnapshotStore {
    public static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AgentLedger/trend.json")
    }

    public static func load(from url: URL = fileURL()) -> [TrendPoint] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TrendPoint].self, from: data)) ?? []
    }

    public static func record(
        points: [TrendPoint],
        provider: String,
        usedPercent: Double?,
        at: Date,
        url: URL = fileURL()
    ) -> [TrendPoint] {
        guard let usedPercent, usedPercent.isFinite else { return points }
        var updated = points
        if let recent = updated.last(where: { $0.provider == provider }) {
            let elapsed = at.timeIntervalSince(recent.at)
            let delta = abs(recent.usedPercent - usedPercent)
            if elapsed < 60 { return points }
            if elapsed < 15 * 60 && delta < 0.5 { return points }
        }
        updated.append(TrendPoint(at: at, provider: provider, usedPercent: usedPercent))
        let cutoff = at.addingTimeInterval(-180 * 86_400)
        updated.removeAll { $0.at < cutoff }
        save(updated, to: url)
        return updated
    }

    public static func save(_ points: [TrendPoint], to url: URL = fileURL()) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(points)
            try data.write(to: url, options: .atomic)
        } catch {
            // Trend history is optional. Quota display still works if it cannot be saved.
        }
    }
}
