import Foundation
import SQLite3
import Security

enum CursorPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var support: URL { home.appendingPathComponent("Library/Application Support/Cursor") }
    static var stateDB: URL { support.appendingPathComponent("User/globalStorage/state.vscdb") }
    static var trackingDB: URL { home.appendingPathComponent(".cursor/ai-tracking/ai-code-tracking.db") }
    static var app: URL { URL(fileURLWithPath: "/Applications/Cursor.app") }

    static var isPresent: Bool {
        FileManager.default.fileExists(atPath: app.path)
            || FileManager.default.fileExists(atPath: support.path)
    }
}

enum SQLite {
    static func rows(path: String, sql: String) throws -> [[String: String]] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
            throw ProviderError.message("Could not open the local Cursor database.")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 800)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ProviderError.message("Could not read the local Cursor database.")
        }
        defer { sqlite3_finalize(statement) }

        var results: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            let columns = sqlite3_column_count(statement)
            for index in 0..<columns {
                guard let namePointer = sqlite3_column_name(statement, index) else { continue }
                let name = String(cString: namePointer)
                if let text = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: text)
                }
            }
            results.append(row)
        }
        return results
    }
}

enum CursorCredentials {
    static func token() -> String? {
        if let token = tokenFromDatabase() { return token }
        return tokenFromKeychain()
    }

    static func email() -> String? {
        guard FileManager.default.fileExists(atPath: CursorPaths.stateDB.path) else { return nil }
        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/cachedEmail' LIMIT 1"
        guard let row = try? SQLite.rows(path: CursorPaths.stateDB.path, sql: sql).first,
              let raw = row["value"] else {
            return nil
        }
        return normalize(raw, minimumLength: 3)
    }

    private static func tokenFromDatabase() -> String? {
        guard FileManager.default.fileExists(atPath: CursorPaths.stateDB.path) else { return nil }
        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        guard let row = try? SQLite.rows(path: CursorPaths.stateDB.path, sql: sql).first,
              let raw = row["value"] else {
            return nil
        }
        return normalize(raw, minimumLength: 20)
    }

    private static func tokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "cursor-access-token",
            kSecAttrAccount as String: "cursor-user",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let raw = String(data: data, encoding: .utf8) {
            return normalize(raw, minimumLength: 20)
        }
        if status == errSecInteractionNotAllowed {
            return tokenFromSecurityCLI()
        }
        return nil
    }

    private static func tokenFromSecurityCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "cursor-access-token",
            "-a", "cursor-user",
            "-w",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        return normalize(raw, minimumLength: 20)
    }

    private static func normalize(_ raw: String, minimumLength: Int) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= minimumLength else { return nil }
        return value
    }
}

enum CursorParser {
    static func parse(period data: Data, plan: Data?, hardLimit: Data?) -> CursorUsage? {
        guard let root = JSONValue.object(data: data) else { return nil }
        let planUsage = JSONValue.dictionary(JSONValue.pick(root, "planUsage", "plan_usage")) ?? [:]
        var total = JSONValue.double(JSONValue.pick(planUsage, "totalPercentUsed", "total_percent_used"))
        let auto = JSONValue.double(JSONValue.pick(planUsage, "autoPercentUsed", "auto_percent_used"))
        let api = JSONValue.double(JSONValue.pick(planUsage, "apiPercentUsed", "api_percent_used"))
        let message = JSONValue.string(JSONValue.pick(root, "displayMessage", "display_message"))
        if total == nil {
            total = percent(in: message) ?? auto
        }
        let start = JSONValue.epochDate(JSONValue.pick(root, "billingCycleStart", "billing_cycle_start"))
        let end = JSONValue.epochDate(JSONValue.pick(root, "billingCycleEnd", "billing_cycle_end"))
        guard total != nil || message != nil || start != nil else { return nil }

        let planObject = plan.flatMap(JSONValue.object(data:))
        let planInfo = JSONValue.dictionary(JSONValue.pick(planObject ?? [:], "planInfo", "plan_info"))
        let periodRaw = JSONValue.string(JSONValue.pick(planInfo ?? [:], "includedUsagePeriod", "included_usage_period"))
        let models = (JSONValue.array(JSONValue.pick(root, "autoBucketModels", "auto_bucket_models")) ?? [])
            .compactMap { JSONValue.string($0) }

        return CursorUsage(
            planName: JSONValue.string(JSONValue.pick(planInfo ?? [:], "planName", "plan_name")),
            email: nil,
            periodLabel: Format.planName(periodRaw),
            windowStart: start,
            windowEnd: end ?? JSONValue.epochDate(JSONValue.pick(planInfo ?? [:], "includedUsageResetsAt", "included_usage_resets_at")),
            totalUsedPercent: total,
            autoUsedPercent: auto,
            apiUsedPercent: api,
            remainingCents: JSONValue.double(JSONValue.pick(planUsage, "remaining")),
            limitCents: JSONValue.double(JSONValue.pick(planUsage, "limit")),
            usedCents: JSONValue.double(JSONValue.pick(planUsage, "includedSpend", "included_spend", "totalSpend", "total_spend")),
            displayMessage: message,
            autoModels: models,
            onDemand: parseOnDemand(hardLimit)
        )
    }

    static func percent(in message: String?) -> Double? {
        guard let message else { return nil }
        guard let range = message.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) else {
            return nil
        }
        let raw = message[range].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Double(raw)
    }

    private static func parseOnDemand(_ data: Data?) -> OnDemandStatus? {
        guard let data, let root = JSONValue.object(data: data) else { return nil }
        if JSONValue.bool(JSONValue.pick(root, "noUsageBasedAllowed", "no_usage_based_allowed")) == true {
            return OnDemandStatus(label: "On-demand disabled")
        }
        guard let limit = JSONValue.double(JSONValue.pick(root, "hardLimit", "hard_limit")) else {
            return nil
        }
        if limit >= 1_000_000_000 || limit == 2_147_483_647 {
            return OnDemandStatus(label: "No on-demand cap")
        }
        if limit <= 0 { return nil }
        return OnDemandStatus(label: "On-demand cap \(Format.dollars(cents: limit * 100))")
    }
}

enum CursorAPI {
    static func fetch(token: String) async throws -> CursorUsage {
        async let period = post(token: token, method: "GetCurrentPeriodUsage")
        async let plan = postOptional(token: token, method: "GetPlanInfo")
        async let hardLimit = postOptional(token: token, method: "GetHardLimit")
        let (status, periodData) = try await period
        if status == 401 || status == 403 {
            throw ProviderError.authRejected("Cursor session expired. Open Cursor and sign in again.")
        }
        guard (200..<300).contains(status) else {
            throw ProviderError.message("Cursor usage request failed (HTTP \(status)).")
        }
        guard var usage = CursorParser.parse(period: periodData, plan: await plan, hardLimit: await hardLimit) else {
            throw ProviderError.message("Cursor returned usage in an unexpected shape.")
        }
        usage.email = CursorCredentials.email()
        return usage
    }

    private static func post(token: String, method: String) async throws -> (Int, Data) {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        return try await ProviderHTTP.send(request)
    }

    private static func postOptional(token: String, method: String) async -> Data? {
        guard let (status, data) = try? await post(token: token, method: method),
              (200..<300).contains(status) else {
            return nil
        }
        return data
    }
}

enum CursorClient {
    static func fetch() async -> ProviderLoad<CursorUsage> {
        guard let token = CursorCredentials.token() else {
            if CursorPaths.isPresent {
                return .signedOut("Sign in to Cursor, then refresh.")
            }
            return .unavailable("Cursor is not installed on this Mac.")
        }
        do {
            return .ready(try await CursorAPI.fetch(token: token))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

public enum CursorLocalStats {
    public static func load(range: StatsRange, now: Date = .now, calendar: Calendar = .current) -> CursorActivity {
        let path = CursorPaths.trackingDB.path
        guard FileManager.default.fileExists(atPath: path) else { return .empty }
        let start = range.start(now: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let unit = timestampUnit(path: path)
        let startValue = Int64(start.timeIntervalSince1970 * unit)
        let endValue = Int64(end.timeIntervalSince1970 * unit)

        let modelSQL = """
        SELECT COALESCE(NULLIF(model, ''), 'unknown') AS name, COUNT(*) AS count
        FROM ai_code_hashes
        WHERE timestamp >= \(startValue) AND timestamp < \(endValue)
        GROUP BY name
        ORDER BY count DESC
        LIMIT 8
        """
        let extensionSQL = """
        SELECT COALESCE(NULLIF(fileExtension, ''), 'unknown') AS name, COUNT(*) AS count
        FROM ai_code_hashes
        WHERE timestamp >= \(startValue) AND timestamp < \(endValue)
        GROUP BY name
        ORDER BY count DESC
        LIMIT 8
        """
        let totalSQL = """
        SELECT COUNT(*) AS count FROM ai_code_hashes
        WHERE timestamp >= \(startValue) AND timestamp < \(endValue)
        """
        let models = (try? SQLite.rows(path: path, sql: modelSQL)) ?? []
        let extensions = (try? SQLite.rows(path: path, sql: extensionSQL)) ?? []
        let total = Int((try? SQLite.rows(path: path, sql: totalSQL))?.first?["count"] ?? "0") ?? 0
        let commits = commitSummary(path: path, start: start, end: end)

        return CursorActivity(
            databaseFound: true,
            editCount: total,
            editsByModel: models.compactMap(countStat),
            editsByExtension: extensions.compactMap(countStat),
            commitCount: commits.count,
            averageAIPercent: commits.average,
            composerLines: commits.composer,
            humanLines: commits.human
        )
    }

    private static func timestampUnit(path: String) -> Double {
        let sql = "SELECT timestamp FROM ai_code_hashes ORDER BY timestamp DESC LIMIT 1"
        guard let raw = try? SQLite.rows(path: path, sql: sql).first?["timestamp"],
              let value = Double(raw) else {
            return 1000
        }
        return value > 10_000_000_000 ? 1000 : 1
    }

    private static func countStat(_ row: [String: String]) -> CountStat? {
        guard let name = row["name"], let count = Int(row["count"] ?? "") else { return nil }
        return CountStat(name: name, count: count)
    }

    private static func commitSummary(path: String, start: Date, end: Date) -> (count: Int, average: Double?, composer: Int64, human: Int64) {
        let sql = "SELECT commitDate, v2AiPercentage, composerLinesAdded, humanLinesAdded FROM scored_commits"
        let rows = (try? SQLite.rows(path: path, sql: sql)) ?? []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy Z"
        var count = 0
        var percentTotal = 0.0
        var percentCount = 0
        var composer: Int64 = 0
        var human: Int64 = 0
        for row in rows {
            guard let raw = row["commitDate"], let date = formatter.date(from: raw) else { continue }
            guard date >= start && date < end else { continue }
            count += 1
            if let percent = Double(row["v2AiPercentage"] ?? "") {
                percentTotal += percent
                percentCount += 1
            }
            composer += Int64(row["composerLinesAdded"] ?? "") ?? 0
            human += Int64(row["humanLinesAdded"] ?? "") ?? 0
        }
        let average = percentCount > 0 ? percentTotal / Double(percentCount) : nil
        return (count, average, composer, human)
    }
}
