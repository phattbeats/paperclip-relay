import SwiftUI
import UIKit

struct IssuesView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @EnvironmentObject private var filters: IssueFilterStore

    @State private var search = ""

    var body: some View {
        NavigationView {
            Group {
                if filters.state == .loading && filters.rows.isEmpty {
                    ProgressView()
                } else if filters.rows.isEmpty {
                    EmptyState(
                        title: filters.errorMessage == nil ? "Nothing here" : "Could not load issues",
                        message: filters.errorMessage ?? "No issues match \(filters.selection.title).",
                        actionTitle: "Reload",
                        action: {
                            Task { await filters.refresh(auth: session.credentials) }
                        }
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Issues")
            .searchable(text: $search, prompt: "Search titles")
            .safeAreaInset(edge: .top, spacing: 0) { filterHeader }
        }
        .navigationViewStyle(.stack)
        .task {
            if filters.state == .idle {
                await filters.refresh(auth: session.credentials)
            }
        }
    }

    /// The chip row. Two axes, both visible without opening anything: the
    /// board's task views and the board user's inbox. Every chip carries
    /// its count.
    private var filterHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(IssueChipGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(group.chips) { chip in
                                FilterChipButton(
                                    chip: chip,
                                    count: filters.counts[chip],
                                    isSelected: filters.selection == chip
                                ) {
                                    filters.select(chip)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var list: some View {
        List {
            // A decision is not an issue. It is a question the board
            // cannot answer for itself, so it sits above the list as a
            // card of its own, with the answer attached.
            if !board.decisions.isEmpty || !board.pendingInteractions.isEmpty {
                Section {
                    DecisionCardsView(
                        decisions: board.decisions,
                        interactions: board.pendingInteractions,
                        onResolve: { await refreshBoard() }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            Section {
                ForEach(filtered) { item in
                    NavigationLink {
                        IssueDetailView(issueID: item.id)
                    } label: {
                        IssueRow(item: item, agentName: board.agentById[item.assigneeAgentId ?? ""]?.name)
                    }
                }
                if let notice = filters.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if let failure = filters.errorMessage {
                    Text(failure)
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await filters.refresh(auth: session.credentials)
        }
    }

    /// Reload the decisions and the chip counts after one is resolved.
    private func refreshBoard() async {
        await board.refreshDecisions(auth: session.credentials)
        await filters.refresh(auth: session.credentials)
    }

    private var filtered: [IssueListItem] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return filters.rows }
        return filters.rows.filter {
            $0.title.lowercased().contains(needle)
                || ($0.identifier?.lowercased().contains(needle) ?? false)
        }
    }
}

/// One chip in the filter row: a name and a count.
struct FilterChipButton: View {
    let chip: IssueChip
    let count: ChipCount?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(chip.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                if let count {
                    Text(count.label)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.18),
                                    in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundColor(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct IssueRow: View {
    let item: IssueListItem
    let agentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.identifier ?? "—")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
                StatusBadge(status: item.status)
                Spacer()
                if let priority = item.priority, priority != "medium" {
                    Text(priority)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(priorityColor(priority))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text(item.title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if let agentName {
                Label(agentName, systemImage: "person")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "critical": return .red
        case "high": return .orange
        default: return .secondary
        }
    }
}

/// Status pill. The board's status vocabulary is fixed, so this is a
/// fixed map rather than a colour scale — a status should look the same
/// every time it appears.
struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var label: String {
        status.replacingOccurrences(of: "_", with: " ")
    }

    private var color: Color {
        switch status {
        case "done": return .green
        case "in_progress": return .blue
        case "in_review": return .purple
        case "blocked": return .red
        case "todo": return .orange
        case "monitoring": return .teal
        case "cancelled": return .secondary
        default: return .secondary
        }
    }
}
