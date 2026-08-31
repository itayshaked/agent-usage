import Foundation

/// Which tool a session belongs to. Sessions from both providers sit in one
/// list and can be bundled together, so they need a common shape.
enum SessionProvider: String, Codable {
    case cursor
    case claude

    var label: String {
        switch self {
        case .cursor: return "Cursor"
        case .claude: return "Claude Code"
        }
    }
}

/// One unit of work that a provider already tracks and named on its own: a
/// Cursor conversation, or a Claude Code session transcript.
///
/// Deliberately *not* a stopwatch. Both providers stamp every dollar with the
/// session it belongs to, so cost is attributed rather than measured as a
/// delta — which is what makes overlapping sessions add up correctly instead
/// of each claiming the same spend.
struct AgentSession: Identifiable {
    /// The provider's own identifier (Cursor `conversationId`, Claude session
    /// UUID). Stable across refreshes, which is what bundles are keyed on.
    let id: String
    let provider: SessionProvider
    let title: String
    /// Workspace or project the session ran in, when we can resolve one.
    let subtitle: String?
    let costDollars: Double
    let tokens: Int
    let requests: Int
    /// Most-used model, for the one-line summary.
    let topModel: String?
    let startedAt: Date
    let lastActiveAt: Date
    /// Cursor bills per conversation, so its figure is authoritative. Claude
    /// Code's is derived from local token counts against a static price table.
    let costIsEstimate: Bool

    /// Sessions touched within this window are shown as still running.
    static let liveWindow: TimeInterval = 8 * 60

    func isLive(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastActiveAt) < Self.liveWindow
    }

    var isFromToday: Bool {
        Calendar.current.isDateInToday(lastActiveAt)
    }

    /// "11:17–13:48", or "15:06 → now" while it's still going.
    func timeSpanText(asOf now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let start = f.string(from: startedAt)
        if isLive(asOf: now) { return "\(start) → now" }
        let end = f.string(from: lastActiveAt)
        return start == end ? start : "\(start)–\(end)"
    }
}
