import Foundation
import SwiftUI

/// A user-named group of sessions — "RMPD-3408" holding its planning chat, its
/// CI chat, and the review subagents it spawned.
///
/// A bundle stores only session *ids*; every total is recomputed from the live
/// session list, so a bundle can never drift from the underlying numbers.
struct SessionBundle: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Provider session ids. Ordered for a stable display; membership is unique.
    var sessionIDs: [String] = []

    func contains(_ sessionID: String) -> Bool { sessionIDs.contains(sessionID) }
}

/// Totals for one bundle, folded from whichever of its sessions are currently loaded.
struct BundleRollup {
    let bundle: SessionBundle
    let sessions: [AgentSession]
    /// Ids in the bundle that no loaded session matches — usually sessions
    /// older than the current fetch window rather than anything wrong.
    let unresolvedCount: Int

    var costDollars: Double { sessions.reduce(0) { $0 + $1.costDollars } }
    var tokens: Int { sessions.reduce(0) { $0 + $1.tokens } }
    var costIsEstimate: Bool { sessions.contains { $0.costIsEstimate } }
    var isLive: Bool { sessions.contains { $0.isLive() } }
    var providers: Set<SessionProvider> { Set(sessions.map { $0.provider }) }
}

@MainActor
final class BundleStore: ObservableObject {
    @Published private(set) var bundles: [SessionBundle] = []

    private let key = "sessionBundles"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([SessionBundle].self, from: data) {
            bundles = saved
        }
    }

    // MARK: - Editing

    @discardableResult
    func create(name: String, seededWith sessionID: String? = nil) -> SessionBundle? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var bundle = SessionBundle(name: trimmed)
        if let sessionID { bundle.sessionIDs = [sessionID] }
        bundles.append(bundle)
        persist()
        return bundle
    }

    func rename(_ bundleID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = bundles.firstIndex(where: { $0.id == bundleID }) else { return }
        bundles[index].name = trimmed
        persist()
    }

    func delete(_ bundleID: UUID) {
        bundles.removeAll { $0.id == bundleID }
        persist()
    }

    /// Moves a session into a bundle. A session belongs to at most one bundle,
    /// so totals across bundles never double-count the same spend.
    func add(_ sessionID: String, to bundleID: UUID) {
        for index in bundles.indices {
            bundles[index].sessionIDs.removeAll { $0 == sessionID }
        }
        guard let index = bundles.firstIndex(where: { $0.id == bundleID }) else { return }
        bundles[index].sessionIDs.append(sessionID)
        persist()
    }

    func remove(_ sessionID: String) {
        for index in bundles.indices {
            bundles[index].sessionIDs.removeAll { $0 == sessionID }
        }
        bundles.removeAll { $0.sessionIDs.isEmpty && $0.name.isEmpty }
        persist()
    }

    // MARK: - Queries

    func bundle(containing sessionID: String) -> SessionBundle? {
        bundles.first { $0.contains(sessionID) }
    }

    var bundledSessionIDs: Set<String> {
        Set(bundles.flatMap { $0.sessionIDs })
    }

    /// Folds the current session list into per-bundle totals, richest first.
    func rollups(from sessions: [AgentSession]) -> [BundleRollup] {
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return bundles
            .map { bundle in
                let members = bundle.sessionIDs.compactMap { byID[$0] }
                return BundleRollup(bundle: bundle,
                                    sessions: members,
                                    unresolvedCount: bundle.sessionIDs.count - members.count)
            }
            .sorted { $0.costDollars > $1.costDollars }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bundles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
