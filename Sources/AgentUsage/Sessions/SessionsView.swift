import SwiftUI

/// The session list: what each piece of work cost, with the provider's own
/// name on it. Bundles roll several sessions up under a name you choose.
struct SessionsView: View {
    let sessions: [AgentSession]
    @EnvironmentObject private var bundles: BundleStore

    /// Which session is having a bundle named for it right now.
    @State private var namingFor: String?
    @State private var draftName: String = ""
    @State private var showingAll = false
    /// Collapsed state sticks across launches — the list is the tallest thing
    /// in the popover, so whether it's open is a lasting preference.
    @AppStorage("sessionsExpanded") private var expanded = true

    private let collapsedLimit = 5

    /// Today's work, richest first. Anything already in a bundle is shown
    /// inside that bundle instead of twice.
    private var loose: [AgentSession] {
        let bundled = bundles.bundledSessionIDs
        return sessions.filter { $0.isFromToday && !bundled.contains($0.id) }
    }

    private var rollups: [BundleRollup] {
        bundles.rollups(from: sessions).filter { !$0.sessions.isEmpty || $0.unresolvedCount > 0 }
    }

    private var todayTotal: Double {
        sessions.filter { $0.isFromToday }.reduce(0) { $0 + $1.costDollars }
    }

    private var visibleLoose: [AgentSession] {
        showingAll ? loose : Array(loose.prefix(collapsedLimit))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content.padding(.top, 6)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions").font(.headline)
                Spacer()
                Text(Money.short(todayTotal))
                    .font(.subheadline).monospacedDigit().bold()
                Text("today").font(.caption).foregroundStyle(.secondary)
            }
            // The whole header toggles, not just the triangle.
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sessions.isEmpty {
                Text("No sessions yet. Cursor chats and Claude Code sessions appear here as they run.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if loose.isEmpty && rollups.isEmpty {
                Text("Nothing today yet.").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(rollups, id: \.bundle.id) { rollup in
                BundleRow(rollup: rollup)
            }

            ForEach(visibleLoose) { session in
                SessionRow(session: session,
                           isNaming: namingFor == session.id,
                           draftName: $draftName,
                           onNewBundle: { beginNaming(session.id) },
                           onCommitName: { commitName(for: session.id) },
                           onCancelName: { cancelNaming() })
            }

            if loose.count > collapsedLimit {
                Button(showingAll
                       ? "Show fewer"
                       : "\(loose.count - collapsedLimit) more today · \(Money.short(hiddenTotal))") {
                    showingAll.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var hiddenTotal: Double {
        loose.dropFirst(collapsedLimit).reduce(0) { $0 + $1.costDollars }
    }

    private func beginNaming(_ sessionID: String) {
        draftName = ""
        namingFor = sessionID
    }

    private func commitName(for sessionID: String) {
        bundles.create(name: draftName, seededWith: sessionID)
        cancelNaming()
    }

    private func cancelNaming() {
        namingFor = nil
        draftName = ""
    }
}

// MARK: - Rows

private struct SessionRow: View {
    let session: AgentSession
    let isNaming: Bool
    @Binding var draftName: String
    let onNewBundle: () -> Void
    let onCommitName: () -> Void
    let onCancelName: () -> Void

    @EnvironmentObject private var bundles: BundleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                LivePip(isLive: session.isLive())
                Text(session.title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(Money.short(session.costDollars))
                    .font(.caption).monospacedDigit().bold()
                    .foregroundStyle(session.isLive() ? Color.green : Color.primary)
                bundleMenu
            }
            Text(metaLine)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 14)

            if isNaming {
                HStack(spacing: 6) {
                    TextField("Bundle name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit(onCommitName)
                    Button("Add", action: onCommitName)
                        .buttonStyle(.borderless).font(.caption)
                        .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel", action: onCancelName)
                        .buttonStyle(.borderless).font(.caption)
                }
                .padding(.leading, 14)
            }
        }
    }

    private var metaLine: String {
        var parts = [session.timeSpanText()]
        if let model = session.topModel { parts.append(ModelName.short(model)) }
        parts.append("\(session.requests) req")
        if let subtitle = session.subtitle { parts.append(subtitle) }
        if session.costIsEstimate { parts.append("est.") }
        return parts.joined(separator: " · ")
    }

    private var bundleMenu: some View {
        Menu {
            Button("New bundle…", action: onNewBundle)
            if !bundles.bundles.isEmpty {
                Divider()
                ForEach(bundles.bundles) { bundle in
                    Button("Add to \(bundle.name)") { bundles.add(session.id, to: bundle.id) }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 18)
        .help("Bundle this session")
    }
}

private struct BundleRow: View {
    let rollup: BundleRollup
    @EnvironmentObject private var bundles: BundleStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rollup.sessions) { session in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            LivePip(isLive: session.isLive())
                            Text(session.title).font(.caption2).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Money.short(session.costDollars))
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            Button {
                                bundles.remove(session.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from bundle")
                        }
                    }
                    if rollup.unresolvedCount > 0 {
                        Text("\(rollup.unresolvedCount) older session(s) not in the current window")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 3)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "shippingbox")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(rollup.bundle.name).font(.caption).bold().lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Money.short(rollup.costDollars))
                        .font(.caption).monospacedDigit().bold()
                        .foregroundStyle(rollup.isLive ? Color.green : Color.primary)
                }
                .contextMenu {
                    Button("Delete bundle", role: .destructive) { bundles.delete(rollup.bundle.id) }
                }
            }
            Text(summaryLine)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.leading, 14)
        }
    }

    private var summaryLine: String {
        var parts = ["\(rollup.sessions.count) session(s)"]
        let providers = rollup.providers.map { $0.label }.sorted()
        if !providers.isEmpty { parts.append(providers.joined(separator: " + ")) }
        if rollup.costIsEstimate { parts.append("partly est.") }
        return parts.joined(separator: " · ")
    }
}

private struct LivePip: View {
    let isLive: Bool

    var body: some View {
        Circle()
            .fill(isLive ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 6, height: 6)
            .accessibilityLabel(isLive ? "Running" : "Finished")
    }
}

// MARK: - Formatting

enum Money {
    static func short(_ dollars: Double) -> String {
        String(format: "$%.2f", dollars)
    }
}

enum ModelName {
    /// "claude-sonnet-5-thinking-medium" is too wide for a 340pt popover;
    /// drop the vendor prefix and keep the part that identifies the model.
    static func short(_ model: String) -> String {
        var name = model
        for prefix in ["claude-", "cursor-", "anthropic/"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name.count > 26 ? String(name.prefix(25)) + "…" : name
    }
}
