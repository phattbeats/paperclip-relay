import SwiftUI
import UIKit

/// The Inbox: the work waiting on the board user.
///
/// The board's inbox is a composition rather than a single server view —
/// the web app derives its five tabs from the issue list's own filters —
/// so the app derives the same five from the same filters:
///
/// - **Mine** — the board's own snapshot, `GET /api/companies/{id}/inbox/mine`
/// - **Unread** — `unreadForUserId=me`
/// - **Blocked** — `attention=blocked`
/// - **Recent** — `touchedByUserId=me`, in the last week
/// - **Everything** — the whole company list
///
/// Each row opens the thing it points at: an issue, an approval, or a
/// question an agent asked on an issue thread.
struct InboxView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    /// The five tabs the board's inbox has. The chip vocabulary is the
    /// board's own, shared with the Issues tab's filter row.
    private static let tabs: [IssueChip] = [.mine, .unread, .blocked, .recent, .everything]

    /// How many rows the app asks for per dataset. The board has well
    /// over a thousand issues, so no phone fetches the whole thing; a
    /// count that was cut off says so with a "+" rather than lying.
    private let limit = 100

    /// A week is what "Recent" means here.
    private let recentWindow: TimeInterval = 7 * 24 * 60 * 60

    @State private var selection: IssueChip = .mine
    @State private var rows: [IssueListItem] = []
    @State private var counts: [IssueChip: ChipCount] = [:]
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var truncated = false

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

    private let service = BoardService()

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
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await load() }
        .sheet(item: $sheet) { item in
            switch item {
            case .approval(let approval):
                ApprovalDetailSheet(approval: approval)
            case .interaction(let interaction):
                InteractionQuestionsSheet(interactionID: interaction.id,
                                          issueID: interaction.issueID) {
                    await load()
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
                        count: counts[chip],
                        isSelected: selection == chip
                    ) {
                        select(chip)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func select(_ chip: IssueChip) {
        withAnimation(.easeOut(duration: 0.15)) {
            selection = chip
            rows = makeRows(for: chip)
            truncated = counts[chip]?.overflow ?? false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if loading && rows.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if let errorMessage {
            VStack {
                Spacer()
                EmptyState(title: "Could not load",
                           message: errorMessage,
                           actionTitle: "Retry") {
                    Task { await load() }
                }
                Spacer()
            }
        } else {
            List {
                if selection == .mine {
                    waitingSection
                }
                Section {
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
                    if truncated {
                        Text("Showing the first \(limit). The board has more.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text(selection.title)
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }
        }
    }

    /// The things on the board that want the user specifically: an
    /// approval to sign, a question to answer.
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

    /// The approvals still waiting on the user.
    private var pendingApprovals: [Approval] {
        board.approvals.filter { $0.status == "pending" }
    }

    // MARK: - Loading

    /// Load every dataset the tabs count from.
    ///
    /// The requests run concurrently; one failing endpoint leaves its tab
    /// empty instead of blanking the whole inbox.
    private func load() async {
        loading = true
        errorMessage = nil
        let auth = session.credentials

        async let mine = fetch { try await service.inbox(auth: auth).issues ?? [] }
        async let unread = fetch {
            try await service.issues(auth: auth,
                                     limit: limit,
                                     filter: IssueListFilter(unreadForMe: true))
        }
        async let blocked = fetch {
            try await service.issues(auth: auth,
                                     limit: limit,
                                     filter: IssueListFilter(blockedAttention: true))
        }
        async let recent = fetch {
            try await service.issues(auth: auth,
                                     limit: limit,
                                     filter: IssueListFilter(touchedByMe: true))
        }
        async let everything = fetch {
            try await service.issues(auth: auth, limit: limit)
        }
        async let blockedCount = fetchCount { try await service.blockedCount(auth: auth) }

        let (mineRows, unreadRows, blockedRows, recentRows, everythingRows, exactBlocked) =
            await (mine, unread, blocked, recent, everything, blockedCount)

        if let failure = firstFailure([mineRows, unreadRows, blockedRows, recentRows, everythingRows]) {
            errorMessage = failure
        }

        datasets = [
            .mine: mineRows.value,
            .unread: unreadRows.value,
            .blocked: blockedRows.value,
            .recent: recentRows.value,
            .everything: everythingRows.value,
        ]

        var counts: [IssueChip: ChipCount] = [:]
        for (chip, rows) in datasets {
            if chip == .recent {
                // A week is the window, so the number is what was found
                // inside it rather than a floor of the whole set.
                counts[chip] = ChipCount(value: rows.filter { isRecent($0) }.count, overflow: false)
            } else {
                counts[chip] = ChipCount(value: rows.count, overflow: rows.count >= limit)
            }
        }
        // Blocked has a dedicated count on the board, so this one is the
        // real number rather than a floor.
        if let exactBlocked {
            counts[.blocked] = ChipCount(value: exactBlocked, overflow: false)
        }
        self.counts = counts
        rows = makeRows(for: selection)
        truncated = counts[selection]?.overflow ?? false
        loading = false
    }

    /// The rows behind each tab.
    @State private var datasets: [IssueChip: [Issue]] = [:]

    private func makeRows(for chip: IssueChip) -> [IssueListItem] {
        let rows = datasets[chip] ?? []
        switch chip {
        case .recent:
            return rows.filter { isRecent($0) }.map(IssueListItem.init(issue:))
        default:
            return rows.map(IssueListItem.init(issue:))
        }
    }

    private func isRecent(_ issue: Issue) -> Bool {
        guard let stamp = issue.myLastTouchAt ?? issue.lastActivityAt ?? issue.updatedAt,
              let date = Self.date(from: stamp) else { return false }
        return date.timeIntervalSinceNow > -recentWindow
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// One dataset, or the reason it failed.
    private struct Loaded {
        let value: [Issue]
        let failure: String?
    }

    private func fetch(_ work: () async throws -> [Issue]) async -> Loaded {
        do {
            return Loaded(value: try await work(), failure: nil)
        } catch {
            return Loaded(value: [], failure: BoardStore.message(for: error))
        }
    }

    private func fetchCount(_ work: () async throws -> Int) async -> Int? {
        try? await work()
    }

    private func firstFailure(_ loaded: [Loaded]) -> String? {
        loaded.compactMap { $0.failure }.first
    }
}
