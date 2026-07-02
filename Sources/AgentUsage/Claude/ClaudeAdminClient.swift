import Foundation

enum ClaudeAdminClientError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Talks to Anthropic's official Admin API for org-wide usage/cost. Requires
/// an Admin API key (sk-ant-admin...), which is org-level, not personal.
struct ClaudeAdminClient {
    let adminKey: String
    private let base = "https://api.anthropic.com/v1/organizations"

    private static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func request(path: String, query: [String: [String]]) -> URLRequest {
        var components = URLComponents(string: base + path)!
        components.queryItems = query.flatMap { key, values in
            values.map { URLQueryItem(name: key, value: $0) }
        }
        var req = URLRequest(url: components.url!)
        req.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func fetchJSON(_ req: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAdminClientError.message("No HTTP response from Anthropic.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = body.isEmpty ? "" : " — \(body.prefix(200))"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ClaudeAdminClientError.message(
                    "Admin API key rejected (\(http.statusCode)). Use an sk-ant-admin... key with usage/cost read access.\(snippet)")
            }
            throw ClaudeAdminClientError.message("Anthropic returned HTTP \(http.statusCode)\(snippet)")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    func fetchUsage() async throws -> ClaudeUsageData {
        var data = ClaudeUsageData(scope: .org)
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let startOfToday = calendar.startOfDay(for: now)
        let startParam = Self.rfc3339.string(from: startOfMonth)

        // Cost report: authoritative $ totals, bucketed daily.
        let costJSON = try await fetchJSON(request(
            path: "/cost_report",
            query: ["starting_at": [startParam], "bucket_width": ["1d"]]
        ))
        let buckets = (JSON.find(costJSON, keys: ["data"]) as? [Any]) ?? []
        for case let bucket as [String: Any] in buckets {
            guard let bucketStart = JSON.date(bucket, keys: ["starting_at"]) else { continue }
            let results = (bucket["results"] as? [Any]) ?? []
            let bucketCentsTotal = results.reduce(0.0) { sum, entry in
                guard let dict = entry as? [String: Any] else { return sum }
                return sum + (JSON.double(dict, keys: ["amount"]) ?? 0)
            }
            let bucketDollars = bucketCentsTotal / 100.0
            data.monthCostDollars += bucketDollars
            if bucketStart >= startOfToday {
                data.todayCostDollars += bucketDollars
            }
        }

        // Usage report: per-model token breakdown (cost for the breakdown is
        // estimated via our own pricing table, same as local mode).
        let usageJSON = try await fetchJSON(request(
            path: "/usage_report/messages",
            query: ["starting_at": [startParam], "bucket_width": ["1d"], "group_by[]": ["model"]]
        ))
        let usageBuckets = (JSON.find(usageJSON, keys: ["data"]) as? [Any]) ?? []
        var modelTotals: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]
        var monthTokens = 0, todayTokens = 0
        for case let bucket as [String: Any] in usageBuckets {
            let bucketStart = JSON.date(bucket, keys: ["starting_at"])
            let results = (bucket["results"] as? [Any]) ?? []
            for case let entry as [String: Any] in results {
                let model = JSON.string(entry, keys: ["model"]) ?? "unknown"
                let input = JSON.int(entry, keys: ["uncached_input_tokens", "input_tokens"]) ?? 0
                let output = JSON.int(entry, keys: ["output_tokens"]) ?? 0
                let cacheRead = JSON.int(entry, keys: ["cache_read_input_tokens"]) ?? 0
                let cacheCreation = entry["cache_creation"] as? [String: Any]
                let cacheWrite = (JSON.int(cacheCreation, keys: ["ephemeral_1h_input_tokens"]) ?? 0)
                    + (JSON.int(cacheCreation, keys: ["ephemeral_5m_input_tokens"]) ?? 0)

                let tokens = input + output + cacheRead + cacheWrite
                monthTokens += tokens
                if let bucketStart, bucketStart >= startOfToday { todayTokens += tokens }

                var totals = modelTotals[model] ?? (0, 0, 0, 0)
                totals.input += input
                totals.output += output
                totals.cacheRead += cacheRead
                totals.cacheWrite += cacheWrite
                modelTotals[model] = totals
            }
        }

        data.monthTokens = monthTokens
        data.todayTokens = todayTokens
        data.models = modelTotals.map { model, t in
            ClaudeModelUsage(
                model: model, inputTokens: t.input, outputTokens: t.output,
                cacheReadTokens: t.cacheRead, cacheWriteTokens: t.cacheWrite,
                costDollars: ClaudePricing.cost(model: model, inputTokens: t.input, outputTokens: t.output,
                                                 cacheWriteTokens: t.cacheWrite, cacheReadTokens: t.cacheRead)
            )
        }
        data.updatedAt = now
        return data
    }
}
