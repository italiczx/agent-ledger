import Foundation

enum ProviderError: LocalizedError {
    case authRejected(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .authRejected(let message), .message(let message):
            return message
        }
    }

    var isAuthRejection: Bool {
        if case .authRejected = self { return true }
        return false
    }
}

enum CodexPaths {
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static var auth: URL { home.appendingPathComponent("auth.json") }
    static var sessions: URL { home.appendingPathComponent("sessions") }

    static var isPresent: Bool {
        FileManager.default.fileExists(atPath: home.path)
    }
}

enum BinaryLocator {
    static func codex() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates = [
            home.appendingPathComponent(".local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".bun/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("codex"))
            }
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

struct CodexCredentials {
    var accessToken: String
    var accountID: String?
}

enum CodexAuth {
    static func load() -> CodexCredentials? {
        guard let data = try? Data(contentsOf: CodexPaths.auth),
              let root = JSONValue.object(data: data) else {
            return nil
        }
        let tokens = JSONValue.dictionary(root["tokens"]) ?? root
        guard let accessToken = JSONValue.string(JSONValue.pick(tokens, "access_token", "accessToken")),
              !accessToken.isEmpty else {
            return nil
        }
        let accountID = JSONValue.string(JSONValue.pick(tokens, "account_id", "accountId"))
            ?? JSONValue.string(JSONValue.pick(root, "account_id", "accountId"))
        return CodexCredentials(accessToken: accessToken, accountID: accountID)
    }
}

enum CodexParser {
    static func parse(data: Data) -> CodexUsage? {
        guard let json = JSONValue.object(data: data) else { return nil }
        return parse(json: json)
    }

    static func parse(json: Any) -> CodexUsage? {
        guard var root = json as? [String: Any] else { return nil }
        if let result = JSONValue.dictionary(root["result"]) {
            root = result
        }

        let rateLimits = JSONValue.dictionary(JSONValue.pick(root, "rateLimits", "rate_limits")) ?? [:]
        let httpRateLimit = JSONValue.dictionary(JSONValue.pick(root, "rate_limit", "rateLimit"))
        let plan = JSONValue.string(JSONValue.pick(root, "plan_type", "planType"))
            ?? JSONValue.string(JSONValue.pick(rateLimits, "planType", "plan_type"))
        let email = JSONValue.string(JSONValue.pick(root, "email"))
        let spend = parseSpend(root: root, rateLimits: rateLimits)
        let credits = parseCredits(root: root, rateLimits: rateLimits)
        var windows = parseWindows(container: httpRateLimit, prefix: "main")
        windows.append(contentsOf: parseWindows(container: rateLimits, prefix: "main"))
        windows.append(contentsOf: parseAdditional(root))
        windows.append(contentsOf: parsePools(root, primaryID: JSONValue.string(JSONValue.pick(rateLimits, "limitId", "limit_id"))))
        if let review = JSONValue.dictionary(JSONValue.pick(root, "code_review_rate_limit", "codeReviewRateLimit")) {
            windows.append(contentsOf: parseWindows(container: review, prefix: "code-review", titlePrefix: "Code review"))
        }

        let blocked = (JSONValue.dictionary(JSONValue.pick(root, "model_usage", "modelUsage")) ?? [:])
            .compactMap { name, value -> String? in
                guard let info = value as? [String: Any] else { return nil }
                if JSONValue.bool(JSONValue.pick(info, "available")) == false { return name }
                return nil
            }
            .sorted()

        let includedBlocked = JSONValue.bool(JSONValue.pick(root, "ordinaryUsageAllowed", "ordinary_usage_allowed")) == false
        let reached = JSONValue.bool(JSONValue.pick(root, "spendControlReached", "spend_control_reached"))
            ?? JSONValue.bool(JSONValue.pick(JSONValue.dictionary(JSONValue.pick(root, "spend_control", "spendControl")) ?? [:], "reached"))
            ?? false

        let hasSignal = plan != nil || spend != nil || credits != nil || !windows.isEmpty || includedBlocked
        guard hasSignal else { return nil }

        var seen = Set<String>()
        let uniqueWindows = windows.filter { seen.insert($0.id).inserted }
        return CodexUsage(
            planType: plan,
            email: email,
            windows: uniqueWindows.sorted { $0.remainingPercent < $1.remainingPercent },
            credits: credits,
            spend: spend,
            spendReached: reached,
            unavailableModels: blocked,
            includedUsageBlocked: includedBlocked
        )
    }

    private static func parseSpend(root: [String: Any], rateLimits: [String: Any]) -> SpendLimit? {
        let httpControl = JSONValue.dictionary(JSONValue.pick(root, "spend_control", "spendControl"))
        let httpLimit = JSONValue.dictionary(JSONValue.pick(httpControl ?? [:], "individual_limit", "individualLimit"))
        let rpcLimit = JSONValue.dictionary(JSONValue.pick(rateLimits, "individualLimit", "individual_limit"))
        guard let source = httpLimit ?? rpcLimit else { return nil }
        guard let limit = JSONValue.double(JSONValue.pick(source, "limit")) else { return nil }
        let used = JSONValue.double(JSONValue.pick(source, "used")) ?? 0
        return SpendLimit(
            unit: JSONValue.string(JSONValue.pick(source, "unit")) ?? "credits",
            limit: limit,
            used: used,
            remaining: JSONValue.double(JSONValue.pick(source, "remaining")),
            usedPercent: JSONValue.double(JSONValue.pick(source, "used_percent", "usedPercent")),
            remainingPercent: JSONValue.double(JSONValue.pick(source, "remaining_percent", "remainingPercent")),
            resetsAt: JSONValue.epochDate(JSONValue.pick(source, "reset_at", "resetsAt", "resets_at"))
        )
    }

    private static func parseCredits(root: [String: Any], rateLimits: [String: Any]) -> CreditBalance? {
        let source = JSONValue.dictionary(JSONValue.pick(root, "credits"))
            ?? JSONValue.dictionary(JSONValue.pick(rateLimits, "credits"))
        guard let source else { return nil }
        return CreditBalance(
            hasCredits: JSONValue.bool(JSONValue.pick(source, "has_credits", "hasCredits")) ?? false,
            unlimited: JSONValue.bool(JSONValue.pick(source, "unlimited")) ?? false,
            balance: JSONValue.double(JSONValue.pick(source, "balance"))
        )
    }

    private static func parseAdditional(_ root: [String: Any]) -> [UsageWindow] {
        let rows = JSONValue.array(JSONValue.pick(root, "additional_rate_limits", "additionalRateLimits")) ?? []
        var windows: [UsageWindow] = []
        for row in rows {
            guard let object = row as? [String: Any] else { continue }
            let name = JSONValue.string(JSONValue.pick(object, "limit_name", "limitName", "metered_feature", "meteredFeature"))
                ?? "Extra"
            let nested = JSONValue.dictionary(JSONValue.pick(object, "rate_limit", "rateLimit")) ?? object
            windows.append(contentsOf: parseWindows(container: nested, prefix: name, titlePrefix: name))
        }
        return windows
    }

    private static func parsePools(_ root: [String: Any], primaryID: String?) -> [UsageWindow] {
        let pools = JSONValue.dictionary(JSONValue.pick(root, "rateLimitsByLimitId", "rate_limits_by_limit_id")) ?? [:]
        var windows: [UsageWindow] = []
        for (key, value) in pools where key != primaryID {
            guard let object = value as? [String: Any] else { continue }
            let name = JSONValue.string(JSONValue.pick(object, "limitName", "limit_name")) ?? key
            windows.append(contentsOf: parseWindows(container: object, prefix: "pool-\(key)", titlePrefix: name))
        }
        return windows
    }

    private static func parseWindows(
        container: [String: Any]?,
        prefix: String,
        titlePrefix: String? = nil
    ) -> [UsageWindow] {
        guard let container else { return [] }
        var windows: [UsageWindow] = []
        let pairs: [(String, [String])] = [
            ("primary", ["primary_window", "primaryWindow", "primary"]),
            ("secondary", ["secondary_window", "secondaryWindow", "secondary"]),
        ]
        for (slot, keys) in pairs {
            guard let raw = JSONValue.dictionary(JSONValue.pick(container, keys[0], keys[1], keys[2])),
                  let used = JSONValue.double(JSONValue.pick(raw, "used_percent", "usedPercent")) else {
                continue
            }
            let seconds = durationSeconds(raw)
            let base = seconds.map(Format.windowTitle(seconds:)) ?? (slot == "primary" ? "Session" : "Longer window")
            let title = titlePrefix.map { "\($0) · \(base)" } ?? base
            windows.append(UsageWindow(
                id: "\(prefix)-\(slot)",
                title: title,
                usedPercent: used,
                resetsAt: JSONValue.epochDate(JSONValue.pick(raw, "reset_at", "resetsAt", "resets_at")),
                durationSeconds: seconds
            ))
        }
        return windows
    }

    private static func durationSeconds(_ raw: [String: Any]) -> Double? {
        if let seconds = JSONValue.double(JSONValue.pick(raw, "limit_window_seconds", "limitWindowSeconds")) {
            return seconds
        }
        if let minutes = JSONValue.double(JSONValue.pick(raw, "window_duration_mins", "windowDurationMins")) {
            return minutes * 60
        }
        return nil
    }
}

enum CodexAPI {
    static func fetchUsage(credentials: CodexCredentials) async throws -> CodexUsage {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("agent-ledger", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (status, data) = try await ProviderHTTP.send(request)
        if status == 401 || status == 403 {
            throw ProviderError.authRejected("Codex declined the saved login. Run codex login, then refresh.")
        }
        guard (200..<300).contains(status) else {
            throw ProviderError.message("Codex usage request failed (HTTP \(status)).")
        }
        guard let usage = CodexParser.parse(data: data) else {
            throw ProviderError.message("Codex returned usage in an unexpected shape.")
        }
        return usage
    }
}

enum CodexAppServer {
    static func fetch(binary: URL) async throws -> CodexUsage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try run(binary: binary))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func run(binary: URL) throws -> CodexUsage {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server", "--stdio"]
        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        try process.run()

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
        }

        try write(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "agent-ledger", "version": "0.1.0"],
            "capabilities": [:],
        ]], to: stdin)
        _ = try readObject(matchingID: 1, from: stdout.fileHandleForReading, process: process)
        try write(["jsonrpc": "2.0", "method": "initialized", "params": [:]], to: stdin)
        try write(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": [:]], to: stdin)
        let response = try readObject(matchingID: 2, from: stdout.fileHandleForReading, process: process)
        if let error = response["error"] as? [String: Any] {
            let message = JSONValue.string(error["message"]) ?? "Codex could not read the account limits."
            throw ProviderError.message(message)
        }
        guard let usage = CodexParser.parse(json: response) else {
            throw ProviderError.message("Codex app-server returned an unexpected usage shape.")
        }
        return usage
    }

    private static func write(_ object: [String: Any], to pipe: Pipe) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try pipe.fileHandleForWriting.write(contentsOf: data)
    }

    private static func readObject(matchingID expected: Int, from handle: FileHandle, process: Process) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(18)
        var buffer = Data()
        while Date() < deadline {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 65_536)
            } catch {
                throw ProviderError.message("Lost the connection to the Codex app-server.")
            }
            if let chunk, !chunk.isEmpty {
                buffer.append(chunk)
            } else if !process.isRunning {
                break
            } else {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                    continue
                }
                if let number = object["id"] as? NSNumber, number.intValue == expected {
                    return object
                }
            }
        }
        throw ProviderError.message("Timed out waiting for Codex usage.")
    }
}

enum CodexClient {
    static func fetch() async -> ProviderLoad<CodexUsage> {
        let binary = BinaryLocator.codex()
        guard CodexPaths.isPresent || binary != nil else {
            return .unavailable("Codex CLI is not installed on this Mac.")
        }

        var httpFailure: String?
        if let credentials = CodexAuth.load() {
            do {
                return .ready(try await CodexAPI.fetchUsage(credentials: credentials))
            } catch {
                httpFailure = error.localizedDescription
                let rejected = (error as? ProviderError)?.isAuthRejection == true
                if !rejected && binary == nil {
                    return .failed(httpFailure ?? "Could not read Codex usage.")
                }
            }
        }

        if let binary {
            do {
                return .ready(try await CodexAppServer.fetch(binary: binary))
            } catch {
                if let httpFailure { return .failed(httpFailure) }
                return .failed(error.localizedDescription)
            }
        }

        if let httpFailure { return .failed(httpFailure) }
        return .signedOut("Run codex login in Terminal, then refresh.")
    }
}

enum CodexSessionScanner {
    static func scan(now: Date = .now, calendar: Calendar = .current) -> (samples: [CodexTurnSample], logsFound: Bool) {
        let root = CodexPaths.sessions
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ([], false)
        }
        let earliest = StatsRange.quarter.start(now: now, calendar: calendar).addingTimeInterval(-36 * 3600)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], true)
        }

        var samples: [CodexTurnSample] = []
        var files = 0
        while let item = enumerator.nextObject() as? URL {
            guard item.pathExtension == "jsonl" else { continue }
            files += 1
            if files > 2_000 { break }
            if let values = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate,
               modified < earliest {
                continue
            }
            samples.append(contentsOf: parseFile(item, earliest: earliest))
            if samples.count > 20_000 { break }
        }
        return (samples, true)
    }

    static func parseFile(_ url: URL, earliest: Date) -> [CodexTurnSample] {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > 80_000_000 { return [] }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var model = "unknown"
        var project = "Other"
        var sessionID = url.deletingPathExtension().lastPathComponent
        var seen = Set<String>()
        var samples: [CodexTurnSample] = []
        return parseText(
            text,
            earliest: earliest,
            fallbackSession: sessionID,
            model: &model,
            project: &project,
            sessionID: &sessionID,
            seen: &seen,
            samples: &samples
        )
    }

    static func parseText(
        _ text: String,
        earliest: Date,
        fallbackSession: String,
        model: inout String,
        project: inout String,
        sessionID: inout String,
        seen: inout Set<String>,
        samples: inout [CodexTurnSample]
    ) -> [CodexTurnSample] {
        model = "unknown"
        project = "Other"
        sessionID = fallbackSession
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard rawLine.contains("\"type\"") else { continue }
            guard let data = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let kind = JSONValue.string(object["type"]) ?? ""
            let payload = JSONValue.dictionary(object["payload"]) ?? [:]
            let timestamp = JSONValue.string(object["timestamp"]).flatMap(JSONValue.isoDate) ?? JSONValue.epochDate(object["timestamp"])

            switch kind {
            case "session_meta":
                if let id = JSONValue.string(JSONValue.pick(payload, "id", "session_id")) {
                    sessionID = id
                }
                if let cwd = JSONValue.string(payload["cwd"]) {
                    project = projectName(cwd)
                }
                if let discovered = modelName(in: payload) {
                    model = discovered
                }
            case "turn_context":
                if let discovered = JSONValue.string(JSONValue.pick(payload, "model", "model_id")) {
                    model = discovered
                }
                if let cwd = JSONValue.string(payload["cwd"]) {
                    project = projectName(cwd)
                }
            case "token_usage_record":
                guard let timestamp, timestamp >= earliest else { continue }
                if let responseID = JSONValue.string(JSONValue.pick(payload, "response_id", "responseId")) {
                    if !seen.insert(responseID).inserted { continue }
                }
                let usage = JSONValue.dictionary(JSONValue.pick(payload, "usage")) ?? [:]
                let input = JSONValue.int64(usage["input_tokens"])
                let output = JSONValue.int64(usage["output_tokens"])
                let cached = JSONValue.int64(usage["cached_input_tokens"])
                let reasoning = JSONValue.int64(usage["reasoning_output_tokens"])
                if input == 0 && output == 0 && cached == 0 && reasoning == 0 { continue }
                let recordSession = JSONValue.string(JSONValue.pick(payload, "session_id", "sessionId")) ?? sessionID
                samples.append(CodexTurnSample(
                    at: timestamp,
                    model: model,
                    project: project,
                    sessionID: recordSession,
                    input: input,
                    output: output,
                    cached: cached,
                    reasoning: reasoning
                ))
            default:
                break
            }
        }
        return samples
    }

    private static func modelName(in payload: [String: Any]) -> String? {
        if let model = JSONValue.string(JSONValue.pick(payload, "model", "model_id")) { return model }
        let instructions = JSONValue.dictionary(JSONValue.pick(payload, "base_instructions", "baseInstructions"))
        let provenance = JSONValue.dictionary(JSONValue.pick(instructions ?? [:], "provenance"))
        return JSONValue.string(JSONValue.pick(provenance ?? [:], "model", "model_id"))
    }

    private static func projectName(_ cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Other" : name
    }
}

enum ProviderHTTP {
    static func send(_ request: URLRequest) async throws -> (Int, Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard data.count < 2_000_000 else {
                throw ProviderError.message("The usage response was unexpectedly large.")
            }
            return (status, data)
        } catch let error as ProviderError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw ProviderError.message("You appear to be offline.")
            case .timedOut:
                throw ProviderError.message("The usage request timed out.")
            default:
                throw ProviderError.message("Could not reach the usage service.")
            }
        }
    }
}
