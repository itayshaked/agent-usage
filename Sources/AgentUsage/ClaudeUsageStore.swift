import Foundation

@MainActor
final class ClaudeUsageStore: ObservableObject {
    @Published var usage: ClaudeUsageData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var source: ClaudeSource
    @Published var hasAdminKey = false

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 600 // 10 minutes
    private let sourceKey = "claudeSource"

    init() {
        source = ClaudeSource(rawValue: UserDefaults.standard.string(forKey: sourceKey) ?? "") ?? .local
        hasAdminKey = Keychain.load(account: Keychain.claudeAdminAccount) != nil
        startTimer()
        Task { await refresh() }
    }

    /// Claude Code has no queryable dollar limit for personal accounts, so the
    /// menu bar icon stays neutral — this exists mainly to match Cursor's
    /// view model shape for the combined label in the app entry point.
    var menuBarTitle: String {
        guard let usage else { return "Claude" }
        return String(format: "$%.2f", usage.monthCostDollars)
    }

    func useLocal() {
        setSource(.local)
    }

    func setAdminKey(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.save(trimmed, account: Keychain.claudeAdminAccount)
        hasAdminKey = true
        setSource(.adminKey)
    }

    func clearAdminKey() {
        Keychain.delete(account: Keychain.claudeAdminAccount)
        hasAdminKey = false
        if source == .adminKey { useLocal() }
    }

    private func setSource(_ newSource: ClaudeSource) {
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: sourceKey)
        errorMessage = nil
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        switch source {
        case .local:
            usage = await Task.detached(priority: .utility) { ClaudeLocalUsageReader.read() }.value
        case .adminKey:
            guard let key = Keychain.load(account: Keychain.claudeAdminAccount), !key.isEmpty else {
                errorMessage = "No Admin API key set."
                hasAdminKey = false
                isLoading = false
                return
            }
            do {
                usage = try await ClaudeAdminClient(adminKey: key).fetchUsage()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }
}
