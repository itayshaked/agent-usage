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
    @State private var editingToken = false
    @State private var bodyHeight: CGFloat = 120
    private let maxBodyHeight: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !store.hasToken || editingToken {
                TokenEntryView(editing: $editingToken)
            } else {
                // Grows with content, but scrolls once it would exceed maxBodyHeight.
                // Height is measured so the ScrollView doesn't collapse in the
                // self-sizing menu bar window.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) { usageBody }
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                        })
                }
                .frame(height: min(bodyHeight, maxBodyHeight))
                .onPreferenceChange(ContentHeightKey.self) { bodyHeight = $0 }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "cursorarrow.rays")
            Text("Cursor Usage").font(.headline)
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var usageBody: some View {
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

    private var footer: some View {
        HStack {
            if let usage = store.usage {
                Text("Updated \(usage.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!store.hasToken || store.isLoading)

            Menu {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Divider()
                Button("Use Cursor app login (auto)") { store.useLocalApp() }
                Button("Change token…") { editingToken = true }
                Button("Sign out", role: .destructive) { store.clearToken() }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
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

    private var sorted: [MemberSpend] {
        members.sorted { ($0.overallSpendCents ?? 0) > ($1.overallSpendCents ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top spenders").font(.caption).foregroundStyle(.secondary)
            ForEach(sorted.prefix(8)) { member in
                HStack {
                    Text(member.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(spend(member)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func spend(_ member: MemberSpend) -> String {
        let cents = member.overallSpendCents ?? member.spendCents ?? 0
        return String(format: "$%.2f", cents / 100.0)
    }
}

private struct ModelBreakdownView: View {
    let models: [ModelUsage]

    private var sorted: [ModelUsage] {
        models.sorted { ($0.cents ?? 0, $0.requests ?? 0) > ($1.cents ?? 0, $1.requests ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By model").font(.caption).foregroundStyle(.secondary)
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
    }

    private func cost(_ model: ModelUsage) -> String {
        if let cents = model.cents { return String(format: "$%.2f", cents / 100.0) }
        if let requests = model.requests { return "\(requests) req" }
        return ""
    }

    private func tokenLine(_ model: ModelUsage) -> String? {
        var parts: [String] = []
        if let i = model.inputTokens { parts.append("in \(Self.compact(i))") }
        if let o = model.outputTokens { parts.append("out \(Self.compact(o))") }
        let cache = (model.cacheReadTokens ?? 0) + (model.cacheWriteTokens ?? 0)
        if cache > 0 { parts.append("cache \(Self.compact(cache))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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
