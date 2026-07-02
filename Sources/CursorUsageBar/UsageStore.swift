import Foundation
import SwiftUI

enum WarningLevel {
    case normal, warn, critical

    var symbol: String {
        switch self {
        case .normal: return "cursorarrow.rays"
        case .warn: return "exclamationmark.circle"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .normal: return .primary
        case .warn: return .orange
        case .critical: return .red
        }
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var usage: UsageData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasToken = false
    @Published var source: TokenSource
    @Published var launchAtLogin: Bool

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 600 // 10 minutes
    private let sourceKey = "tokenSource"

    init() {
        source = TokenSource(rawValue: UserDefaults.standard.string(forKey: sourceKey) ?? "") ?? .localApp
        launchAtLogin = LoginItem.isEnabled
        refreshHasToken()
        if hasToken {
            startTimer()
            Task { await refresh() }
        }
    }

    var warningLevel: WarningLevel {
        guard let f = usage?.usageFraction else { return .normal }
        if f >= 0.9 { return .critical }
        if f >= 0.7 { return .warn }
        return .normal
    }

    var menuBarTitle: String {
        guard let usage else { return hasToken ? "…" : "Cursor" }
        if let fraction = usage.usageFraction, let dollars = usage.totalSpendDollars {
            return String(format: "$%.0f · %d%%", dollars, Int((fraction * 100).rounded()))
        }
        if let dollars = usage.totalSpendDollars {
            return String(format: "$%.2f", dollars)
        }
        if let used = usage.requestsUsed {
            if let limit = usage.requestsLimit { return "\(used)/\(limit)" }
            return "\(used)"
        }
        return "Cursor"
    }

    /// Resolves the actual credential + mode for the current source.
    private func resolveToken() -> (String, AuthMode)? {
        switch source {
        case .localApp:
            guard let token = LocalTokenReader.cookieToken() else { return nil }
            return (token, .cookie)
        case .cookie, .teamKey:
            guard let token = Keychain.load(), !token.isEmpty else { return nil }
            return (token, source.authMode)
        }
    }

    private func refreshHasToken() {
        hasToken = resolveToken() != nil
    }

    func useLocalApp() {
        setSource(.localApp)
    }

    func setToken(_ raw: String, source: TokenSource) {
        if source != .localApp {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Keychain.save(trimmed)
        }
        setSource(source)
    }

    private func setSource(_ newSource: TokenSource) {
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: sourceKey)
        errorMessage = nil
        refreshHasToken()
        startTimer()
        Task { await refresh() }
    }

    func clearToken() {
        Keychain.delete()
        usage = nil
        errorMessage = nil
        hasToken = false
        timer?.invalidate()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        launchAtLogin = LoginItem.isEnabled
    }

    func refresh() async {
        guard let (token, mode) = resolveToken() else {
            errorMessage = source == .localApp
                ? "Couldn't read the Cursor app login. Open Cursor and sign in, or paste a token."
                : "No token set."
            hasToken = false
            return
        }
        hasToken = true
        isLoading = true
        errorMessage = nil
        do {
            usage = try await CursorClient(token: token, mode: mode).fetchUsage()
        } catch {
            errorMessage = error.localizedDescription
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
