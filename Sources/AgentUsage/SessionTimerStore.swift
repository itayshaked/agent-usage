import Foundation
import SwiftUI

/// A user-started stopwatch that reports the tokens and cost accrued *since it
/// was started*, for both Cursor and Claude. It snapshots each provider's
/// cumulative running totals at start (the "baseline") and reports
/// current − baseline. Start time + baseline are persisted so a running timer
/// survives an app relaunch.
@MainActor
final class SessionTimerStore: ObservableObject {
    struct Baseline: Codable {
        var cursorCostDollars: Double
        var cursorTokens: Int
        var claudeCostDollars: Double
        var claudeTokens: Int
    }

    @Published private(set) var startedAt: Date?
    @Published private(set) var elapsed: TimeInterval = 0

    /// Pulls fresh usage for both providers; set by the app so the timer can
    /// refresh on a faster cadence while running without holding the stores.
    var onRefresh: (() async -> Void)?

    private var baseline: Baseline?
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private let fastRefreshInterval: TimeInterval = 15

    private let startedAtKey = "sessionTimerStartedAt"
    private let baselineKey = "sessionTimerBaseline"

    var isRunning: Bool { startedAt != nil }

    var elapsedText: String {
        let total = Int(elapsed)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    init() {
        if let ts = UserDefaults.standard.object(forKey: startedAtKey) as? Date,
           let data = UserDefaults.standard.data(forKey: baselineKey),
           let saved = try? JSONDecoder().decode(Baseline.self, from: data) {
            startedAt = ts
            baseline = saved
            beginTicking()
        }
    }

    func start(cursorCostDollars: Double, cursorTokens: Int,
               claudeCostDollars: Double, claudeTokens: Int) {
        startedAt = Date()
        baseline = Baseline(cursorCostDollars: cursorCostDollars, cursorTokens: cursorTokens,
                            claudeCostDollars: claudeCostDollars, claudeTokens: claudeTokens)
        persist()
        beginTicking()
        Task { await onRefresh?() }
    }

    func stop() {
        startedAt = nil
        baseline = nil
        elapsed = 0
        refreshTimer?.invalidate(); refreshTimer = nil
        clockTimer?.invalidate(); clockTimer = nil
        UserDefaults.standard.removeObject(forKey: startedAtKey)
        UserDefaults.standard.removeObject(forKey: baselineKey)
    }

    // Deltas clamp at 0 so a billing-cycle / month rollover (which resets the
    // underlying cumulative total below the baseline) can't show a negative.
    func cursorCostDelta(current: Double) -> Double { max(0, current - (baseline?.cursorCostDollars ?? current)) }
    func cursorTokenDelta(current: Int) -> Int { max(0, current - (baseline?.cursorTokens ?? current)) }
    func claudeCostDelta(current: Double) -> Double { max(0, current - (baseline?.claudeCostDollars ?? current)) }
    func claudeTokenDelta(current: Int) -> Int { max(0, current - (baseline?.claudeTokens ?? current)) }

    private func beginTicking() {
        elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: fastRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.onRefresh?() }
        }
    }

    private func persist() {
        UserDefaults.standard.set(startedAt, forKey: startedAtKey)
        if let baseline, let data = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(data, forKey: baselineKey)
        }
    }
}
