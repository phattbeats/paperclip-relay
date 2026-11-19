import SwiftUI
import UIKit

/// The board user's needs-you queue.
///
/// The five tabs use the shared `IssueFilterStore`; the Issues and Inbox
/// surfaces therefore show the same rows and counts without making a second
/// round of inbox requests. Approvals and interactions remain first-class
/// entries because they point at a decision rather than an issue row.
struct InboxView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @EnvironmentObject private var filters: IssueFilterStore

    private static let tabs: [IssueChip] = [.mine, .unread, .blocked, .recent, .everything]

    /// One sheet, not two: SwiftUI only honours the last sheet modifier
    /// attached to a view.
    private enum Sheet: Identifiable {
        case approval(Approval)
        case interaction(PendingInteraction)

        var id: String {
            switch self {
            case .approval(let item): return "approval-\(item.id)"
            case .interaction(let item): return "interaction-\(item.id)"
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var selection: IssueChip = .mine

    private var rows: [IssueListItem] { filters.rows(for: selection) }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                tabRow
                Divider()
                content
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(filters.state == .loading)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            if filters.state == .idle {
                await refresh()
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .approval(let approval):
                ApprovalDetailSheet(approval: approval)
            case .interaction(let interaction):
                if let issueID = interaction.issueID {
                    InteractionQuestionsSheet(interactionID: interaction.id,
                                              issueID: issueID) {
                        await refresh()
                    }
                } else {
                    EmptyState(title: "Cannot open",
                               message: "That question is not attached to an issue.")
                }
            }
        }
    }

    // MARK: - Tabs

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.tabs) { chip in
                    FilterChipButton(
                        chip: chip,
                        count: filters.counts[chip],
                        isSelected: selection == chip
                    ) {
                        selection = chip
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filters.state == .loading && rows.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if rows.isEmpty && filters.errorMessage != nil {
            VStack {
                Spacer()
                EmptyState(title: "Could not load",
                           message: filters.errorMessage ?? "Unknown error",
                           actionTitle: "Retry") {
                    Task { await refresh() }
                }
                Spacer()
            }
        } else {
            List {
                if selection == .mine {
                    waitingSection
                }
                Section(selection.title) {
                    if rows.isEmpty {
                        Text("Nothing here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(rows) { item in
                        NavigationLink {
                            IssueDetailView(issueID: item.id)
                        } label: {
                            IssueRow(item: item,
                                     agentName: board.agentById[item.assigneeAgentId ?? ""]?.name)
                        }
                    }
                    if let notice = filters.notice(for: selection) {
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
            .refreshable { await refresh() }
        }
    }

    /// The things on the board that want the user specifically: an approval
    /// to sign or an interaction to answer. These open their own detail
    /// surfaces instead of pretending to be issues.
    @ViewBuilder
    private var waitingSection: some View {
        if !pendingApprovals.isEmpty || !board.pendingInteractions.isEmpty {
            Section("Waiting on you") {
                ForEach(pendingApprovals) { item in
                    Button {
                        sheet = .approval(item)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .font(.caption)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.payload?.displayTitle ?? "Approval")
                                    .font(.callout)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Text("Approval")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(board.pendingInteractions) { interaction in
                    Button {
                        sheet = .interaction(interaction)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(interaction.issueTitle ?? interaction.title ?? "Question")
                                    .font(.callout)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                if let identifier = interaction.issueIdentifier {
                                    Text(identifier)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pendingApprovals: [Approval] {
        board.approvals.filter { $0.status == "pending" }
    }

    private func refresh() async {
        async let filtersRefresh: Void = filters.refresh(auth: session.credentials)
        async let boardRefresh: Void = board.refreshDecisions(auth: session.credentials)
        _ = await (filtersRefresh, boardRefresh)
    }
}
