import Foundation

enum AuthMode: String {
    case cookie   // individual: reverse-engineered dashboard endpoints via session cookie
    case teamKey  // team/enterprise: official Admin API via api.cursor.com
}

/// Where the credential comes from.
enum TokenSource: String, CaseIterable {
    case localApp  // auto: read from the logged-in Cursor IDE
    case cookie    // manual: pasted WorkosCursorSessionToken
    case teamKey   // manual: Team Admin API key

    var authMode: AuthMode { self == .teamKey ? .teamKey : .cookie }
}

struct ModelUsage: Identifiable {
    let id = UUID()
    let model: String
    let requests: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let cents: Double?

    var totalTokens: Int? {
        let parts = [inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
}

struct MemberSpend: Identifiable {
    let id = UUID()
    let name: String
    let email: String?
    let role: String?
    let spendCents: Double?
    let overallSpendCents: Double?
    let fastRequests: Int?
}

/// Normalized snapshot shown in the UI. Every field is optional because the
/// underlying endpoints are unofficial and their shapes drift over time.
struct UsageData {
    var email: String?
    var plan: String?
    var cycleStart: Date?
    var cycleEnd: Date?
    var requestsUsed: Int?
    var requestsLimit: Int?
    var spendCents: Double?          // included usage used (cents)
    var spendLimitCents: Double?     // included usage limit (cents)
    var onDemandUsedCents: Double?
    var onDemandLimitCents: Double?
    var models: [ModelUsage] = []
    /// Per-conversation attribution — the basis for the session list.
    var sessions: [AgentSession] = []
    var members: [MemberSpend] = []
    var memberCount: Int?
    var updatedAt: Date = Date()

    var totalSpendDollars: Double? {
        guard let spendCents else { return nil }
        return spendCents / 100.0
    }

    /// Fraction of the included-usage limit consumed (0...1), if a limit exists.
    var usageFraction: Double? {
        guard let spendCents, let limit = spendLimitCents, limit > 0 else { return nil }
        return min(spendCents / limit, 1.0)
    }
}

enum CursorClientError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Talks to Cursor for usage data, either via the official Admin API (team key)
/// or the undocumented dashboard endpoints (individual session cookie).
struct CursorClient {
    let token: String
    let mode: AuthMode
    private let base = "https://cursor.com"

    /// Strips characters that could break out of the Cookie header (CR/LF would
    /// allow injecting extra headers; ';' would terminate the cookie early) in
    /// case a malformed value ever gets pasted or extracted.
    private var sanitizedToken: String {
        token.filter { !$0.isNewline && $0 != ";" }
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.setValue("WorkosCursorSessionToken=\(sanitizedToken)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // CSRF: state-changing endpoints require a matching Origin.
            req.setValue(base, forHTTPHeaderField: "Origin")
            req.httpBody = body
        }
        return req
    }

    func fetchUsage() async throws -> UsageData {
        switch mode {
        case .cookie: return try await fetchCookieUsage()
        case .teamKey: return try await fetchTeamUsage()
        }
    }

    // MARK: - Official Admin API (team key)

    private func adminRequest(path: String, body: Data?) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.cursor.com" + path)!)
        req.httpMethod = "POST"
        // Basic auth: API key as username, empty password.
        let credentials = Data("\(token):".utf8).base64EncodedString()
        req.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body
        return req
    }

    private func fetchTeamUsage() async throws -> UsageData {
        var data = UsageData()
        var members: [MemberSpend] = []
        var page = 1

        while true {
            let payload: [String: Any] = ["sortBy": "amount", "sortDirection": "desc",
                                          "page": page, "pageSize": 1000]
            let body = try? JSONSerialization.data(withJSONObject: payload)
            let json = try await fetchJSON(adminRequest(path: "/teams/spend", body: body))

            if let start = JSON.date(json, keys: ["subscriptionCycleStart"]) {
                data.cycleStart = start
            }
            data.memberCount = JSON.int(json, keys: ["totalMembers"])

            let entries = (JSON.find(json, keys: ["teamMemberSpend"]) as? [Any]) ?? []
            for case let entry as [String: Any] in entries {
                members.append(MemberSpend(
                    name: JSON.string(entry, keys: ["name"]) ?? "Unknown",
                    email: JSON.string(entry, keys: ["email"]),
                    role: JSON.string(entry, keys: ["role"]),
                    spendCents: JSON.double(entry, keys: ["spendCents"]),
                    overallSpendCents: JSON.double(entry, keys: ["overallSpendCents"]),
                    fastRequests: JSON.int(entry, keys: ["fastPremiumRequests"])
                ))
            }

            let totalPages = JSON.int(json, keys: ["totalPages"]) ?? 1
            if page >= totalPages || entries.isEmpty { break }
            page += 1
        }

        data.members = members
        data.spendCents = members.compactMap { $0.overallSpendCents ?? $0.spendCents }.reduce(0, +)
        data.plan = "Team"
        data.updatedAt = Date()
        return data
    }

    private func fetchJSON(_ req: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CursorClientError.message("No HTTP response from Cursor.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = body.isEmpty ? "" : " — \(body.prefix(200))"
            if http.statusCode == 401 || http.statusCode == 403 {
                let hint = mode == .teamKey
                    ? "API key rejected (\(http.statusCode)). Use a Team API key with admin:* scope (not a User/Agent key)."
                    : "Session token invalid or expired (\(http.statusCode)). Paste a fresh WorkosCursorSessionToken."
                throw CursorClientError.message(hint + snippet)
            }
            throw CursorClientError.message("Cursor returned HTTP \(http.statusCode)\(snippet)")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Dashboard endpoints (individual cookie)

    /// Fetches everything best-effort. A failure in one endpoint doesn't sink the others.
    private func fetchCookieUsage() async throws -> UsageData {
        var data = UsageData()

        // Identity is the anchor; if it 401s the token is bad and we surface that.
        let identity = try await fetchJSON(request(path: "/api/auth/me"))
        data.email = JSON.string(identity, keys: ["email"])
        let userId = JSON.int(identity, keys: ["id"])

        if let summary = try? await fetchJSON(request(path: "/api/usage-summary")) {
            data.plan = JSON.string(summary, keys: ["membershipType", "plan", "membership"])
            data.cycleStart = JSON.date(summary, keys: ["billingCycleStart", "startOfMonth", "cycleStart"])
            data.cycleEnd = JSON.date(summary, keys: ["billingCycleEnd", "cycleEnd", "endOfMonth"])
            // Included usage (individualUsage.overall) drives the limit + progress bar.
            let overall = JSON.find(summary, keys: ["overall"])
            data.spendCents = JSON.double(overall, keys: ["used"])
            data.spendLimitCents = JSON.double(overall, keys: ["limit"])
            // On-demand pool, if enabled.
            if let onDemand = JSON.find(summary, keys: ["onDemand"]) {
                data.onDemandUsedCents = JSON.double(onDemand, keys: ["used"])
                data.onDemandLimitCents = JSON.double(onDemand, keys: ["limit"])
            }
        }

        // Per-model and per-conversation breakdowns for the current cycle, both
        // folded from one pass over the event feed. The backend refuses windows
        // spanning its cutovers, so scope the query to the billing cycle.
        if let userId {
            let start = data.cycleStart ?? Date(timeIntervalSinceNow: -30 * 24 * 3600)
            let events = await fetchUsageEvents(userId: userId, start: start, end: Date())
            data.models = Self.models(from: events)
            data.sessions = Self.sessions(from: events, composers: CursorComposerReader.composers())
            // Only fall back to summed model spend if the summary didn't give us a figure.
            if data.spendCents == nil, !data.models.isEmpty {
                data.spendCents = data.models.compactMap { $0.cents }.reduce(0, +)
            }
        }

        data.updatedAt = Date()
        return data
    }

    /// The raw usage-event feed for a window.
    ///
    /// The older `get-aggregated-usage-events` endpoint now answers 200 with an
    /// empty object, which silently left the breakdown blank. This feed is what
    /// the dashboard itself reads; its `chargedCents` reconciles exactly with
    /// the included-usage figure from `/api/usage-summary`, and every event
    /// carries the `conversationId` that sessions are grouped by.
    private func fetchUsageEvents(userId: Int, start: Date, end: Date) async -> [[String: Any]] {
        var collected: [[String: Any]] = []
        var page = 1

        while page <= Self.maxEventPages {
            let payload: [String: Any] = [
                "teamId": 0,
                "userId": userId,
                "startDate": String(Int(start.timeIntervalSince1970 * 1000)),
                "endDate": String(Int(end.timeIntervalSince1970 * 1000)),
                "page": page,
                "pageSize": Self.eventPageSize,
            ]
            let body = try? JSONSerialization.data(withJSONObject: payload)
            guard let json = try? await fetchJSON(request(path: "/api/dashboard/get-filtered-usage-events",
                                                          method: "POST", body: body)),
                  let events = JSON.find(json, keys: ["usageEventsDisplay"]) as? [Any],
                  !events.isEmpty
            else { break }

            collected.append(contentsOf: events.compactMap { $0 as? [String: Any] })
            if collected.count >= (JSON.int(json, keys: ["totalUsageEventsCount"]) ?? collected.count) { break }
            page += 1
        }
        return collected
    }

    /// The feed pages; a heavy month runs to a few hundred events, and the cap
    /// keeps a drifting `totalUsageEventsCount` from spinning us forever.
    private static let eventPageSize = 1000
    private static let maxEventPages = 20

    // MARK: - Folding the feed

    private static func models(from events: [[String: Any]]) -> [ModelUsage] {
        var totals: [String: EventTotals] = [:]
        var order: [String] = []
        for event in events {
            let name = JSON.string(event, keys: ["model"]) ?? "unknown"
            if totals[name] == nil {
                totals[name] = EventTotals()
                order.append(name)
            }
            totals[name]?.add(event)
        }
        return order.compactMap { name in
            totals[name].map { totals in
                ModelUsage(model: name,
                           requests: totals.requests,
                           inputTokens: totals.inputTokens,
                           outputTokens: totals.outputTokens,
                           cacheReadTokens: totals.cacheReadTokens,
                           cacheWriteTokens: totals.cacheWriteTokens,
                           cents: totals.cents)
            }
        }
    }

    private static func sessions(from events: [[String: Any]],
                                 composers: [String: CursorComposerReader.Composer]) -> [AgentSession] {
        var totals: [String: EventTotals] = [:]
        for event in events {
            guard let id = JSON.string(event, keys: ["conversationId"]) else { continue }
            if totals[id] == nil { totals[id] = EventTotals() }
            totals[id]?.add(event)
        }

        return totals.map { id, totals in
            let composer = composers[id]
            // Subagent runs are named by their type, which is more useful than
            // the generic title Cursor gives them.
            let title = composer?.name
                ?? composer?.subagentTypeName
                ?? "Conversation " + id.prefix(8)
            return AgentSession(
                id: id,
                provider: .cursor,
                title: title,
                subtitle: composer?.isSubagent == true ? "subagent" : nil,
                costDollars: totals.cents / 100.0,
                tokens: totals.totalTokens,
                requests: totals.requests,
                topModel: totals.topModel,
                startedAt: totals.firstSeen ?? Date(),
                lastActiveAt: totals.lastSeen ?? Date(),
                costIsEstimate: false
            )
        }
        .sorted { $0.costDollars > $1.costDollars }
    }

    /// Running totals while folding the event feed, shared by both groupings.
    private struct EventTotals {
        var requests = 0
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
        var cents = 0.0
        var firstSeen: Date?
        var lastSeen: Date?
        private var modelCounts: [String: Int] = [:]

        var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
        var topModel: String? { modelCounts.max { $0.value < $1.value }?.key }

        mutating func add(_ event: [String: Any]) {
            requests += 1
            // Request-based (non-token) events carry no tokenUsage at all.
            let tokens = JSON.find(event, keys: ["tokenUsage"])
            inputTokens += JSON.int(tokens, keys: ["inputTokens"]) ?? 0
            outputTokens += JSON.int(tokens, keys: ["outputTokens"]) ?? 0
            cacheReadTokens += JSON.int(tokens, keys: ["cacheReadTokens"]) ?? 0
            cacheWriteTokens += JSON.int(tokens, keys: ["cacheWriteTokens"]) ?? 0
            cents += JSON.double(event, keys: ["chargedCents", "totalCents"]) ?? 0

            if let model = JSON.string(event, keys: ["model"]) {
                modelCounts[model, default: 0] += 1
            }
            if let at = JSON.date(event, keys: ["timestamp"]) {
                firstSeen = min(firstSeen ?? at, at)
                lastSeen = max(lastSeen ?? at, at)
            }
        }
    }
}
