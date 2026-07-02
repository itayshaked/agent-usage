import Foundation

/// Static $/token pricing for Claude model families, used to turn local token
/// counts into an estimated cost (Claude Code's local logs don't include a
/// precomputed cost). Rates are per-token, matching Anthropic's published
/// per-million-token prices divided by 1,000,000. Matched by substring against
/// the versioned model name (e.g. "claude-opus-4-6" -> Opus tier) so new dated
/// releases keep working without an update.
enum ClaudePricing {
    private struct Rates {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    // Per-token rates (USD). Source: platform.claude.com pricing, standard tier.
    private static let opus = Rates(input: 15e-6, output: 75e-6, cacheWrite: 18.75e-6, cacheRead: 1.5e-6)
    private static let sonnet = Rates(input: 3e-6, output: 15e-6, cacheWrite: 3.75e-6, cacheRead: 0.3e-6)
    private static let haiku = Rates(input: 0.8e-6, output: 4e-6, cacheWrite: 1e-6, cacheRead: 0.08e-6)

    private static func rates(for model: String) -> Rates {
        let m = model.lowercased()
        if m.contains("opus") { return opus }
        if m.contains("haiku") { return haiku }
        // Sonnet (and anything unrecognized) defaults to the mid tier.
        return sonnet
    }

    /// Estimated cost in USD for one usage record.
    static func cost(model: String, inputTokens: Int, outputTokens: Int,
                      cacheWriteTokens: Int, cacheReadTokens: Int) -> Double {
        let r = rates(for: model)
        return Double(inputTokens) * r.input
            + Double(outputTokens) * r.output
            + Double(cacheWriteTokens) * r.cacheWrite
            + Double(cacheReadTokens) * r.cacheRead
    }
}
