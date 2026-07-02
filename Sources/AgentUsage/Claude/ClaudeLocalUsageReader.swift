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

            guard var reader = LineReader(path: fileURL.path) else { continue }
            defer { reader.close() }

            while let line = reader.nextLine() {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let timestamp = JSON.date(obj, keys: ["timestamp"]),
                      timestamp >= startOfMonth
                else { continue }

                let model = message["model"] as? String ?? "unknown"
                let input = JSON.int(usage, keys: ["input_tokens"]) ?? 0
                let output = JSON.int(usage, keys: ["output_tokens"]) ?? 0
                let cacheRead = JSON.int(usage, keys: ["cache_read_input_tokens"]) ?? 0
                let cacheWrite = JSON.int(usage, keys: ["cache_creation_input_tokens"]) ?? 0
                let cost = ClaudePricing.cost(model: model, inputTokens: input, outputTokens: output,
                                               cacheWriteTokens: cacheWrite, cacheReadTokens: cacheRead)
                let tokens = input + output + cacheRead + cacheWrite

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
                totals.cacheWrite += cacheWrite
                totals.cost += cost
                modelTotals[model] = totals
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
        data.updatedAt = now
        return data
    }
}
