import SwiftUI

@main
struct AgentUsageApp: App {
    @StateObject private var cursorStore = UsageStore()
    @StateObject private var claudeStore = ClaudeUsageStore()
    @StateObject private var displayState = AppDisplayState()
    @StateObject private var cycleTicker = MenuBarCycleTicker()
    @StateObject private var sessionTimer = SessionTimerStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(cursorStore)
                .environmentObject(claudeStore)
                .environmentObject(displayState)
                .environmentObject(sessionTimer)
        } label: {
            MenuBarLabelView(cursorStore: cursorStore, claudeStore: claudeStore,
                              displayState: displayState, cycleTicker: cycleTicker)
                .task {
                    sessionTimer.onRefresh = { [weak cursorStore, weak claudeStore] in
                        await cursorStore?.refresh()
                        await claudeStore?.refresh()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ticks a plain @Published flag on a Timer. Deliberately NOT using
/// TimelineView here: driving a MenuBarExtra label (an NSStatusBarButton
/// under the hood, not a normal animatable SwiftUI view) with TimelineView's
/// per-frame schedule caused a continuous AppKit relayout loop that pegged
/// the CPU at 100% and leaked memory. A Timer firing a single state change
/// every few seconds is the same safe pattern already used by the usage
/// stores' refresh timers.
@MainActor
final class MenuBarCycleTicker: ObservableObject {
    @Published private(set) var showingCursor = true
    private var timer: Timer?

    init(interval: TimeInterval = 10) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.showingCursor.toggle() }
        }
    }
}

/// The compact menu bar contents. In "both" mode it cycles between the Cursor
/// and Claude figures every few seconds, since there isn't room to show full
/// detail for two providers side by side. The swap is instant (no
/// transition/animation) — see MenuBarCycleTicker for why.
private struct MenuBarLabelView: View {
    @ObservedObject var cursorStore: UsageStore
    @ObservedObject var claudeStore: ClaudeUsageStore
    @ObservedObject var displayState: AppDisplayState
    @ObservedObject var cycleTicker: MenuBarCycleTicker

    var body: some View {
        switch displayState.preference {
        case .cursorOnly:
            cursorPill
        case .claudeOnly:
            claudePill
        case .both:
            cycleTicker.showingCursor ? AnyView(cursorPill) : AnyView(claudePill)
        }
    }

    private var cursorPill: some View {
        HStack(spacing: 3) {
            brandOrWarningIcon(BrandIcon.cursorTemplate, level: cursorStore.warningLevel)
            Text(cursorStore.menuBarTitle)
        }
        .foregroundStyle(cursorStore.warningLevel.tint)
    }

    private var claudePill: some View {
        HStack(spacing: 3) {
            brandIcon(BrandIcon.claudeTemplate)
            Text(claudeStore.menuBarTitle)
        }
    }

    // Monochrome template glyphs, matching the black/white style of the
    // other status bar icons instead of standing out as colorful squares.
    private func brandIcon(_ icon: Image) -> some View {
        icon.resizable().aspectRatio(contentMode: .fit).frame(width: 12, height: 12)
    }

    @ViewBuilder
    private func brandOrWarningIcon(_ icon: Image, level: WarningLevel) -> some View {
        if level == .normal {
            brandIcon(icon)
        } else {
            Image(systemName: level.symbol)
        }
    }
}
