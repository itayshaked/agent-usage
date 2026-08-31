import Foundation

/// Static $/token pricing for Claude models, used to turn local token counts
/// into an estimated cost — Claude Code's transcripts record tokens, not money.
///
/// Rates are matched by exact model id first, because pricing varies *within* a
/// family and not just between families: Sonnet 5 is cheaper than Sonnet 4.6,
/// and the Opus family dropped to $5/$25 at 4.6. Substring matching on "opus"
/// alone overcharged Opus 5 threefold.
enum ClaudePricing {
    struct Rates {
        /// USD per input token.
        let input: Double
        /// USD per output token.
        let output: Double

        /// Cache multipliers are uniform across models: a read costs 0.1x the
        /// base input rate, a 5-minute write 1.25x, and a 1-hour write 2x.
        var cacheRead: Double { input * 0.1 }
        var cacheWrite5m: Double { input * 1.25 }
        var cacheWrite1h: Double { input * 2.0 }

        static let free = Rates(input: 0, output: 0)
    }

    private static func perMTok(_ input: Double, _ output: Double) -> Rates {
        Rates(input: input / 1_000_000, output: output / 1_000_000)
    }

    /// Published standard-tier rates in $/MTok. Source: platform.claude.com pricing.
    private static let standard: [String: Rates] = [
        "claude-fable-5":    perMTok(10, 50),
        "claude-mythos-5":   perMTok(10, 50),
        "claude-opus-5":     perMTok(5, 25),
        "claude-opus-4-8":   perMTok(5, 25),
        "claude-opus-4-7":   perMTok(5, 25),
        "claude-opus-4-6":   perMTok(5, 25),
        "claude-sonnet-5":   perMTok(2, 10),
        "claude-sonnet-4-6": perMTok(3, 15),
        "claude-haiku-4-5":  perMTok(1, 5),
    ]

    /// Fast mode runs the same model at premium pricing, and the transcripts
    /// record which speed served each request.
    private static let fast: [String: Rates] = [
        "claude-opus-5":   perMTok(10, 50),
        "claude-opus-4-8": perMTok(10, 50),
    ]

    /// Rates for a model id, or nil when we have no published figure for it.
    private static func rates(for model: String, speed: String?) -> Rates? {
        // Claude Code writes bare ids, but a dated snapshot id
        // ("claude-haiku-4-5-20251001") names the same priced model.
        let id = undated(model.lowercased())
        if speed == "fast", let rate = fast[id] { return rate }
        if let rate = standard[id] { return rate }

        // An unrecognised id is most likely a model released after this table
        // was written. Fall back to the current rate for its family rather than
        // dropping the request from the total.
        if id.contains("fable") || id.contains("mythos") { return standard["claude-fable-5"] }
        if id.contains("opus") { return standard["claude-opus-5"] }
        if id.contains("haiku") { return standard["claude-haiku-4-5"] }
        if id.contains("sonnet") { return standard["claude-sonnet-4-6"] }
        return nil
    }

    /// Strips a trailing `-YYYYMMDD` snapshot suffix.
    private static func undated(_ id: String) -> String {
        let parts = id.split(separator: "-")
        guard let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) else { return id }
        return parts.dropLast().joined(separator: "-")
    }

    /// Estimated cost in USD for one usage record.
    ///
    /// Cache writes are split by TTL because the difference is large and real:
    /// a 1-hour write costs 2x the input rate against 1.25x for 5 minutes, and
    /// Claude Code leans on the 1-hour TTL for most of its caching.
    static func cost(model: String,
                     speed: String? = nil,
                     inputTokens: Int,
                     outputTokens: Int,
                     cacheWrite5mTokens: Int,
                     cacheWrite1hTokens: Int,
                     cacheReadTokens: Int) -> Double {
        // Claude Code's synthetic placeholder messages are never billed.
        guard !model.hasPrefix("<"), let rate = rates(for: model, speed: speed) else { return 0 }
        return Double(inputTokens) * rate.input
            + Double(outputTokens) * rate.output
            + Double(cacheWrite5mTokens) * rate.cacheWrite5m
            + Double(cacheWrite1hTokens) * rate.cacheWrite1h
            + Double(cacheReadTokens) * rate.cacheRead
    }

    /// True when the id has a published rate rather than a family fallback —
    /// lets the UI say so instead of quietly presenting a guess as a figure.
    static func hasPublishedRate(for model: String) -> Bool {
        standard[undated(model.lowercased())] != nil
    }
}
