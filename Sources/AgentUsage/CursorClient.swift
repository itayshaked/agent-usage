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

        // Per-model spend/tokens for the current cycle. The backend refuses windows
        // spanning its cutovers, so scope the query to the billing cycle.
        if let userId {
            let start = data.cycleStart ?? Date(timeIntervalSinceNow: -30 * 24 * 3600)
            let startMs = String(Int(start.timeIntervalSince1970 * 1000))
            let endMs = String(Int(Date().timeIntervalSince1970 * 1000))
            let payload: [String: Any] = [
                "teamId": 0,
                "userId": userId,
                "startDate": startMs,
                "endDate": endMs,
            ]
            let bodyData = try? JSONSerialization.data(withJSONObject: payload)
            if let agg = try? await fetchJSON(request(path: "/api/dashboard/get-aggregated-usage-events",
                                                      method: "POST", body: bodyData)) {
                parseAggregated(agg, into: &data)
            }
        }

        data.updatedAt = Date()
        return data
    }

    /// Aggregated events: `aggregations[]` with per-model `totalCents` and token counts.
    private func parseAggregated(_ json: Any, into data: inout UsageData) {
        let entries = JSON.collectDicts(json) { dict in
            dict["totalCents"] != nil || dict["inputTokens"] != nil
        }
        guard !entries.isEmpty else { return }

        var models: [ModelUsage] = []
        var spend = 0.0
        var sawCents = false
        for entry in entries {
            let name = JSON.string(entry, keys: ["modelIntent", "model", "name"]) ?? "unknown"
            let cents = JSON.double(entry, keys: ["totalCents", "chargedCents"])
            if let cents { spend += cents; sawCents = true }
            models.append(ModelUsage(
                model: name,
                requests: JSON.int(entry, keys: ["requestCount", "numRequests"]),
                inputTokens: JSON.int(entry, keys: ["inputTokens"]),
                outputTokens: JSON.int(entry, keys: ["outputTokens"]),
                cacheReadTokens: JSON.int(entry, keys: ["cacheReadTokens"]),
                cacheWriteTokens: JSON.int(entry, keys: ["cacheWriteTokens"]),
                cents: cents
            ))
        }
        data.models = models
        // Only fall back to summed model spend if the summary didn't give us a figure.
        if sawCents, data.spendCents == nil { data.spendCents = spend }
    }
}
