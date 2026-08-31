import Foundation

/// Reads Claude Code's local session transcripts to compute usage — the same
/// technique the open-source `ccusage` tool uses. No auth needed: Claude Code
/// already writes every assistant message's token usage to
/// ~/.claude/projects/<project>/<session>.jsonl.
enum ClaudeLocalUsageReader {
    /// Reads a file's lines without loading the whole (sometimes multi-MB) file into memory at once.
    private struct LineReader {
        private let fileHandle: FileHandle
        private var buffer = Data()
        private let newline = UInt8(ascii: "\n")
        private var atEOF = false

        init?(path: String) {
            guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
            fileHandle = fh
        }

        mutating func nextLine() -> String? {
            while true {
                if let index = buffer.firstIndex(of: newline) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<index)
                    buffer.removeSubrange(buffer.startIndex...index)
                    return String(data: lineData, encoding: .utf8)
                }
                guard !atEOF else {
                    guard !buffer.isEmpty else { return nil }
                    let lineData = buffer
                    buffer.removeAll()
                    return String(data: lineData, encoding: .utf8)
                }
                let chunk = fileHandle.readData(ofLength: 64 * 1024)
                if chunk.isEmpty { atEOF = true } else { buffer.append(chunk) }
            }
        }

        func close() { fileHandle.closeFile() }
    }

    private struct Totals {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        var cost = 0.0
    }

    /// Per-transcript totals plus the bits needed to label the session.
    private struct SessionTotals {
        var totals = Totals()
        var requests = 0
        var title: String?
        var firstSeen: Date?
        var lastSeen: Date?
        var modelCounts: [String: Int] = [:]

        var tokens: Int { totals.input + totals.output + totals.cacheRead + totals.cacheWrite }
        var topModel: String? { modelCounts.max { $0.value < $1.value }?.key }
    }

    /// Claude Code names a session by what you first asked it. Skips the
    /// synthetic `<command-…>` and system-reminder envelopes so the title is
    /// the sentence the person actually typed.
    private static func userText(_ message: [String: Any]) -> String? {
        func clean(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { return nil }
            return trimmed.replacingOccurrences(of: "\n", with: " ")
        }
        if let text = message["content"] as? String { return clean(text) }
        if let parts = message["content"] as? [Any] {
            for case let part as [String: Any] in parts {
                if part["type"] as? String == "text",
                   let text = part["text"] as? String,
                   let cleaned = clean(text) { return cleaned }
            }
        }
        return nil
    }

    /// "-Users-itay-shaked-kibush" -> "~/kibush". The directory name is the
    /// project path with separators flattened, so recover a readable tail.
    private static func projectLabel(_ directoryName: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let homeKey = home.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        guard directoryName.hasPrefix(homeKey) else {
            return directoryName.replacingOccurrences(of: "-", with: "/")
        }
        let tail = String(directoryName.dropFirst(homeKey.count)).drop { $0 == "-" }
        return tail.isEmpty ? "~" : "~/" + tail
    }

    /// Scans local transcripts for the current calendar month and today. Safe to call off the main thread.
    static func read() -> ClaudeUsageData {
        var data = ClaudeUsageData(scope: .thisMac)
        let fm = FileManager.default
        let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

        let calendar = Calendar.current
        let now = Date()
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return data
        }
        let startOfToday = calendar.startOfDay(for: now)

        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return data
        }

        var modelTotals: [String: Totals] = [:]
        var sessionTotals: [String: SessionTotals] = [:]
        var sessionProjects: [String: String?] = [:]
        var monthTokens = 0, todayTokens = 0
        var monthCost = 0.0, todayCost = 0.0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            // Skip files that haven't changed this month — cheap way to avoid
            // re-scanning a person's entire multi-year history every refresh.
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= startOfMonth else { continue }

            // The transcript file *is* the session: its name is the session id
            // and its parent directory is the project it ran in.
            let sessionID = fileURL.deletingPathExtension().lastPathComponent
            let project = projectLabel(fileURL.deletingLastPathComponent().lastPathComponent)

            guard var reader = LineReader(path: fileURL.path) else { continue }
            defer { reader.close() }

            while let line = reader.nextLine() {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                if obj["type"] as? String == "user",
                   sessionTotals[sessionID]?.title == nil,
                   let message = obj["message"] as? [String: Any],
                   let text = userText(message) {
                    sessionTotals[sessionID, default: SessionTotals()].title = String(text.prefix(120))
                }

                guard obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let timestamp = JSON.date(obj, keys: ["timestamp"]),
                      timestamp >= startOfMonth
                else { continue }

                let model = message["model"] as? String ?? "unknown"
                let input = JSON.int(usage, keys: ["input_tokens"]) ?? 0
                let output = JSON.int(usage, keys: ["output_tokens"]) ?? 0
                let cacheRead = JSON.int(usage, keys: ["cache_read_input_tokens"]) ?? 0

                // A 1-hour cache write costs 2x the input rate against 1.25x for
                // 5 minutes, and Claude Code writes most of its cache at 1 hour —
                // so the TTL split is worth reading rather than assuming.
                let creation = usage["cache_creation"] as? [String: Any]
                let write1h = JSON.int(creation, keys: ["ephemeral_1h_input_tokens"]) ?? 0
                let write5m = JSON.int(creation, keys: ["ephemeral_5m_input_tokens"]) ?? 0
                let cacheWrite = JSON.int(usage, keys: ["cache_creation_input_tokens"]) ?? 0
                // Transcripts written before the split existed carry only the
                // total; charge those at the 5-minute rate.
                let hasSplit = (write5m + write1h) > 0
                let write5mTokens = hasSplit ? write5m : cacheWrite
                let write1hTokens = hasSplit ? write1h : 0

                let cost = ClaudePricing.cost(model: model,
                                               speed: usage["speed"] as? String,
                                               inputTokens: input, outputTokens: output,
                                               cacheWrite5mTokens: write5mTokens,
                                               cacheWrite1hTokens: write1hTokens,
                                               cacheReadTokens: cacheRead)
                let tokens = input + output + cacheRead + write5mTokens + write1hTokens

                monthTokens += tokens
                monthCost += cost
                if timestamp >= startOfToday {
                    todayTokens += tokens
                    todayCost += cost
                }

                var totals = modelTotals[model] ?? Totals()
                totals.input += input
                totals.output += output
                totals.cacheRead += cacheRead
                totals.cacheWrite += write5mTokens + write1hTokens
                totals.cost += cost
                modelTotals[model] = totals

                var session = sessionTotals[sessionID] ?? SessionTotals()
                session.totals.input += input
                session.totals.output += output
                session.totals.cacheRead += cacheRead
                session.totals.cacheWrite += write5mTokens + write1hTokens
                session.totals.cost += cost
                session.requests += 1
                session.modelCounts[model, default: 0] += 1
                session.firstSeen = min(session.firstSeen ?? timestamp, timestamp)
                session.lastSeen = max(session.lastSeen ?? timestamp, timestamp)
                sessionTotals[sessionID] = session
                sessionProjects[sessionID] = project
            }
        }

        data.monthTokens = monthTokens
        data.todayTokens = todayTokens
        data.monthCostDollars = monthCost
        data.todayCostDollars = todayCost
        data.models = modelTotals.map { model, totals in
            ClaudeModelUsage(model: model, inputTokens: totals.input, outputTokens: totals.output,
                              cacheReadTokens: totals.cacheRead, cacheWriteTokens: totals.cacheWrite,
                              costDollars: totals.cost)
        }
        // Sessions are folded from the same records as the month totals, so the
        // list always adds up to the figure shown above it.
        data.sessions = sessionTotals.compactMap { id, session in
            guard session.requests > 0, let first = session.firstSeen, let last = session.lastSeen else { return nil }
            return AgentSession(
                id: id,
                provider: .claude,
                title: session.title ?? "Session " + id.prefix(8),
                subtitle: (sessionProjects[id] ?? nil),
                costDollars: session.totals.cost,
                tokens: session.tokens,
                requests: session.requests,
                topModel: session.topModel,
                startedAt: first,
                lastActiveAt: last,
                costIsEstimate: true
            )
        }
        .sorted { $0.costDollars > $1.costDollars }
        data.updatedAt = now
        return data
    }
}
