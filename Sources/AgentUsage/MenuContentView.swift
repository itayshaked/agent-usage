import AppKit
import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var claudeStore: ClaudeUsageStore
    @EnvironmentObject private var displayState: AppDisplayState
    @State private var editingToken = false
    @State private var editingClaudeKey = false
    @State private var bodyHeight: CGFloat = 120
    private let maxBodyHeight: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Grows with content, but scrolls once it would exceed maxBodyHeight.
            // Height is measured so the ScrollView doesn't collapse in the
            // self-sizing menu bar window.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cursorSection
                    Divider()
                    claudeSection
                }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .frame(height: min(bodyHeight, maxBodyHeight))
            .onPreferenceChange(ContentHeightKey.self) { bodyHeight = $0 }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Cursor

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BrandIcon.cursor.resizable().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Cursor").font(.headline)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
            }

            if !store.hasToken || editingToken {
                TokenEntryView(editing: $editingToken)
            } else {
                cursorUsageBody
            }
        }
    }

    @ViewBuilder
    private var cursorUsageBody: some View {
        if let usage = store.usage {
            VStack(alignment: .leading, spacing: 8) {
                if let email = usage.email {
                    Label(email, systemImage: "person.circle").font(.subheadline)
                }
                if let count = usage.memberCount {
                    Label("\(count) members", systemImage: "person.2").font(.subheadline)
                } else if let plan = usage.plan {
                    Label(plan.capitalized, systemImage: "creditcard").font(.subheadline)
                }
                if let start = usage.cycleStart {
                    Text("Cycle: \(Self.dateRange(start, usage.cycleEnd))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let used = usage.requestsUsed {
                    RequestsRow(used: used, limit: usage.requestsLimit)
                }
                if usage.spendLimitCents != nil {
                    IncludedUsageView(usage: usage)
                } else if let dollars = usage.totalSpendDollars {
                    HStack {
                        Text(usage.memberCount != nil ? "Team spend this cycle" : "Spend this cycle")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "$%.2f", dollars)).bold()
                    }
                }

                if !usage.members.isEmpty {
                    Divider()
                    MemberBreakdownView(members: usage.members)
                }
                if !usage.models.isEmpty {
                    Divider()
                    ModelBreakdownView(models: usage.models)
                }
            }
        } else if let error = store.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red)
        } else {
            Text("Loading usage…").font(.caption).foregroundStyle(.secondary)
        }

        if let error = store.errorMessage, store.usage != nil {
            Text(error).font(.caption2).foregroundStyle(.orange)
        }
    }

    // MARK: - Claude

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BrandIcon.claude.resizable().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Claude Code").font(.headline)
                Spacer()
                if claudeStore.isLoading { ProgressView().controlSize(.small) }
            }

            if editingClaudeKey {
                ClaudeKeyEntryView(editing: $editingClaudeKey)
            } else {
                claudeUsageBody
            }
        }
    }

    @ViewBuilder
    private var claudeUsageBody: some View {
        if let usage = claudeStore.usage {
            VStack(alignment: .leading, spacing: 8) {
                Label(usage.scope == .org ? "Org usage" : "This Mac", systemImage: usage.scope == .org ? "building.2" : "laptopcomputer")
                    .font(.subheadline).foregroundStyle(.secondary)

                ClaudeCostView(usage: usage)

                if !usage.models.isEmpty {
                    Divider()
                    ClaudeModelBreakdownView(models: usage.models)
                }
            }
        } else if let error = claudeStore.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red)
        } else {
            Text("Loading usage…").font(.caption).foregroundStyle(.secondary)
        }

        if let error = claudeStore.errorMessage, claudeStore.usage != nil {
            Text(error).font(.caption2).foregroundStyle(.orange)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let updatedAt = lastUpdated {
                Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    await store.refresh()
                    await claudeStore.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading || claudeStore.isLoading)

            Menu {
                Picker("Show in menu bar", selection: Binding(
                    get: { displayState.preference },
                    set: { displayState.setPreference($0) }
                )) {
                    ForEach(DisplayPreference.allCases, id: \.self) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Divider()
                Menu("Cursor") {
                    Button("Use Cursor app login (auto)") { store.useLocalApp() }
                    Button("Change token…") { editingToken = true }
                    Button("Sign out", role: .destructive) { store.clearToken() }
                }
                Menu("Claude") {
                    Button("Use local logs (auto)") { claudeStore.useLocal() }
                    Button("Set Admin API key…") { editingClaudeKey = true }
                    if claudeStore.hasAdminKey {
                        Button("Remove Admin API key", role: .destructive) { claudeStore.clearAdminKey() }
                    }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }

    private var lastUpdated: Date? {
        [store.usage?.updatedAt, claudeStore.usage?.updatedAt].compactMap { $0 }.max()
    }

    private static func dateRange(_ start: Date, _ end: Date?) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let startStr = f.string(from: start)
        guard let end else { return "from \(startStr)" }
        return "\(startStr) – \(f.string(from: end))"
    }
}

private struct IncludedUsageView: View {
    let usage: UsageData

    private func dollars(_ cents: Double?) -> String {
        String(format: "$%.2f", (cents ?? 0) / 100.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Included usage").font(.subheadline)
                Spacer()
                Text("\(dollars(usage.spendCents)) / \(dollars(usage.spendLimitCents))").bold()
            }
            if let fraction = usage.usageFraction {
                ProgressView(value: fraction)
                    .tint(fraction > 0.9 ? .red : (fraction > 0.7 ? .orange : .accentColor))
                HStack {
                    Text("\(Int((fraction * 100).rounded()))% used").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let limit = usage.spendLimitCents, let used = usage.spendCents {
                        Text("\(dollars(max(limit - used, 0))) left").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let odLimit = usage.onDemandLimitCents, odLimit > 0 {
                HStack {
                    Text("On-demand").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(dollars(usage.onDemandUsedCents)) / \(dollars(odLimit))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RequestsRow: View {
    let used: Int
    let limit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Requests").font(.subheadline)
                Spacer()
                Text(limit.map { "\(used) / \($0)" } ?? "\(used)").bold()
            }
            if let limit, limit > 0 {
                ProgressView(value: min(Double(used) / Double(limit), 1.0))
            }
        }
    }
}

private struct MemberBreakdownView: View {
    let members: [MemberSpend]
    @State private var expanded = false

    private var sorted: [MemberSpend] {
        members.sorted { ($0.overallSpendCents ?? 0) > ($1.overallSpendCents ?? 0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sorted.prefix(8)) { member in
                    HStack {
                        Text(member.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(spend(member)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Top spenders (\(sorted.count))").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func spend(_ member: MemberSpend) -> String {
        let cents = member.overallSpendCents ?? member.spendCents ?? 0
        return String(format: "$%.2f", cents / 100.0)
    }
}

private struct ModelBreakdownView: View {
    let models: [ModelUsage]
    // Collapsed by default so the essential usage numbers for both providers
    // are visible without scrolling; the breakdown is opt-in detail.
    @State private var expanded = false

    private var sorted: [ModelUsage] {
        models.sorted { ($0.cents ?? 0, $0.requests ?? 0) > ($1.cents ?? 0, $1.requests ?? 0) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Scrolls instead of pushing the rest of the menu down once the
            // list gets long; the outer menu ScrollView still caps overall height.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sorted) { model in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(model.model).font(.caption).lineLimit(1)
                                Spacer()
                                Text(cost(model)).font(.caption).monospacedDigit().bold()
                            }
                            if let tokens = tokenLine(model) {
                                Text(tokens).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: sorted.count > 5 ? 140 : .infinity)
        } label: {
            Text("By model (\(sorted.count))").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func cost(_ model: ModelUsage) -> String {
        if let cents = model.cents { return String(format: "$%.2f", cents / 100.0) }
        if let requests = model.requests { return "\(requests) req" }
        return ""
    }

    private func tokenLine(_ model: ModelUsage) -> String? {
        var parts: [String] = []
        if let i = model.inputTokens { parts.append("in \(TokenFormat.compact(i))") }
        if let o = model.outputTokens { parts.append("out \(TokenFormat.compact(o))") }
        let cache = (model.cacheReadTokens ?? 0) + (model.cacheWriteTokens ?? 0)
        if cache > 0 { parts.append("cache \(TokenFormat.compact(cache))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct ClaudeCostView: View {
    let usage: ClaudeUsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("This month").font(.subheadline)
                Spacer()
                Text(String(format: "$%.2f", usage.monthCostDollars)).bold()
            }
            HStack {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.2f", usage.todayCostDollars))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Tokens (month)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(TokenFormat.compact(usage.monthTokens))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ClaudeModelBreakdownView: View {
    let models: [ClaudeModelUsage]
    // Collapsed by default so the essential usage numbers for both providers
    // are visible without scrolling; the breakdown is opt-in detail.
    @State private var expanded = false

    private var sorted: [ClaudeModelUsage] {
        models.sorted { $0.costDollars > $1.costDollars }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Scrolls instead of pushing the rest of the menu down once the
            // list gets long; the outer menu ScrollView still caps overall height.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sorted) { model in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(model.model).font(.caption).lineLimit(1)
                                Spacer()
                                Text(String(format: "$%.2f", model.costDollars))
                                    .font(.caption).monospacedDigit().bold()
                            }
                            Text("in \(TokenFormat.compact(model.inputTokens)) · out \(TokenFormat.compact(model.outputTokens)) · cache \(TokenFormat.compact(model.cacheReadTokens + model.cacheWriteTokens))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: sorted.count > 5 ? 140 : .infinity)
        } label: {
            Text("By model (\(sorted.count))").font(.caption).foregroundStyle(.secondary)
        }
    }
}

enum TokenFormat {
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }
}

private struct TokenEntryView: View {
    @EnvironmentObject private var store: UsageStore
    @Binding var editing: Bool
    @State private var input = ""
    @State private var selected: TokenSource = .localApp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Source", selection: $selected) {
                Text("Auto").tag(TokenSource.localApp)
                Text("Cookie").tag(TokenSource.cookie)
                Text("Team key").tag(TokenSource.teamKey)
            }
            .pickerStyle(.segmented)

            switch selected {
            case .localApp:
                Text("Use your Cursor app login").font(.subheadline).bold()
                Text("Reads the token from the signed-in Cursor app automatically — no paste, and it never expires while you're logged in.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if editing { Button("Cancel") { editing = false; input = "" } }
                    Spacer()
                    Button("Use this") {
                        store.useLocalApp()
                        editing = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            case .teamKey, .cookie:
                if selected == .teamKey {
                    Text("Paste a Team API key (admin:* scope)").font(.subheadline).bold()
                    Text("cursor.com/dashboard → team → API Keys → New API Key")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Paste your session token").font(.subheadline).bold()
                    Text("cursor.com → DevTools → Application → Cookies → WorkosCursorSessionToken")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecureField(selected == .teamKey ? "Team API key" : "WorkosCursorSessionToken value",
                            text: $input)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if editing { Button("Cancel") { editing = false; input = "" } }
                    Spacer()
                    Button("Save") {
                        store.setToken(input, source: selected)
                        input = ""
                        editing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { selected = store.source }
    }
}

private struct ClaudeKeyEntryView: View {
    @EnvironmentObject private var claudeStore: ClaudeUsageStore
    @Binding var editing: Bool
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste an Anthropic Admin API key").font(.subheadline).bold()
            Text("Org-wide billing, not personal usage. console.anthropic.com → Settings → Admin API Keys. Leave this and use \"Local logs\" instead to track just this Mac's usage with no key at all.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("sk-ant-admin...", text: $input)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { editing = false; input = "" }
                Spacer()
                Button("Save") {
                    claudeStore.setAdminKey(input)
                    input = ""
                    editing = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
