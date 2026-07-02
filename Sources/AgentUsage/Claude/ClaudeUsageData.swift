import Foundation

/// Where a ClaudeUsageData snapshot came from — matters for how we label the
/// numbers, since local data is personal but Admin API data is org-wide.
enum ClaudeUsageScope {
    case thisMac
    case org
}

/// Personal (local) vs org (Admin API) data source for Claude Code usage.
enum ClaudeSource: String, CaseIterable {
    case local
    case adminKey
}

struct ClaudeModelUsage: Identifiable {
    let id = UUID()
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let costDollars: Double

    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
}

struct ClaudeUsageData {
    var scope: ClaudeUsageScope = .thisMac
    var todayCostDollars: Double = 0
    var monthCostDollars: Double = 0
    var todayTokens: Int = 0
    var monthTokens: Int = 0
    /// Per-model breakdown for the current month.
    var models: [ClaudeModelUsage] = []
    var updatedAt: Date = Date()
}
