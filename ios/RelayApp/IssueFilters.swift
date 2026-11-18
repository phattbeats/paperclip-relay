import Foundation
import SwiftUI

// The issue filter: a row of chips that replaces the old status menu.
//
// The vocabulary is the board's own, not the app's invention. The web
// board's task views are `needs_attention`, `all`, `active`, `backlog`
// and `done`, and its inbox tabs are `mine`, `unread`, `blocked`,
// `recent` and `everything`. The status sets come from the board's
// issue-filter presets, so the phone and the web board say the same
// thing about the same issue.

/// The board's status vocabulary, grouped the way the board groups it.
enum IssueStatusSet {
    /// The board's "Active" preset: work that is moving, plus work that
    /// is waiting on someone (blocked) or on a review.
    static let active = ["todo", "in_progress", "monitoring", "in_review", "blocked"]
    static let backlog = ["backlog"]
    static let done = ["done", "cancelled"]
    static let all = active + backlog + done
}

/// One chip in the filter row.
enum IssueChip: String, CaseIterable, Identifiable {
    // Board views.
    case needsAttention
    case all
    case active
    case backlog
    case done

    // Inbox tabs.
    case mine
    case unread
    case blocked
    case recent
    case everything

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsAttention: return "Needs attention"
        case .all: return "All"
        case .active: return "Active"
        case .backlog: return "Backlog"
        case .done: return "Done"
        case .mine: return "Mine"
        case .unread: return "Unread"
        case .blocked: return "Blocked"
        case .recent: return "Recent"
        case .everything: return "Everything"
        }
    }

    var group: IssueChipGroup {
        switch self {
        case .needsAttention, .all, .active, .backlog, .done:
            return .views
        case .mine, .unread, .blocked, .recent, .everything:
            return .inbox
        }
    }

    /// The status set this chip selects, or nil when the chip reads from
    /// its own source (the attention feed, the inbox).
    var statusSet: [String]? {
        switch self {
        case .active: return IssueStatusSet.active
        case .backlog: return IssueStatusSet.backlog
        case .done: return IssueStatusSet.done
        case .all: return IssueStatusSet.all
        case .needsAttention, .mine, .unread, .blocked, .recent, .everything:
            return nil
        }
    }
}

/// The two rows of chips. Each row is one axis: the board's views, and
/// the board user's inbox.
enum IssueChipGroup: String, CaseIterable, Identifiable {
    case views
    case inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .views: return "Board views"
        case .inbox: return "Your inbox"
        }
    }

    var chips: [IssueChip] {
        IssueChip.allCases.filter { $0.group == self }
    }
}

/// A count on a chip. `overflow` means the board had more rows than the
/// app asked for, so the number is a floor rather than a total.
struct ChipCount: Equatable {
    let value: Int
    let overflow: Bool

    var label: String {
        overflow ? "\(value)+" : "\(value)"
    }
}

/// A row in the issue list, from whichever source the chip reads.
struct IssueListItem: Identifiable, Hashable {
    let id: String
    let identifier: String?
    let title: String
    let status: String
    let priority: String?
    let assigneeAgentId: String?

    init(issue: Issue) {
        id = issue.id
        identifier = issue.identifier
        title = issue.title
        status = issue.status
        priority = issue.priority
        assigneeAgentId = issue.assigneeAgentId
    }

    init(inboxIssue: InboxIssue) {
        id = inboxIssue.id
        identifier = inboxIssue.identifier
        title = inboxIssue.title
        status = inboxIssue.status
        priority = inboxIssue.priority
        assigneeAgentId = inboxIssue.assigneeAgentId
    }

    init(attention item: AttentionFeedItem) {
        id = item.issueID ?? item.id
        identifier = item.relatedIssue?.identifier
        title = item.relatedIssue?.title ?? item.subject?.title ?? "Untitled issue"
        status = item.relatedIssue?.status ?? item.subject?.status ?? "todo"
        priority = nil
        assigneeAgentId = nil
    }
}

/// Holds the datasets behind the chips and turns them into counts and
/// rows.
///
/// Every chip is a module with its own source: a board view reads one
/// status set, the attention chip reads the decision feed, an inbox chip
/// reads the board user's inbox. One refresh loads them all, so switching
/// chips is instant and every chip can carry a count.
@MainActor
final class IssueFilterStore: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The chip the list is showing. Active is the default: it is the
    /// working set, and it is what the board itself opens on.
    @Published private(set) var selection: IssueChip = .active

    @Published private(set) var rows: [IssueListItem] = []
    @Published private(set) var counts: [IssueChip: ChipCount] = [:]
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var banner: String?

    /// How many rows the app asks for per dataset. The board has well
    /// over a thousand issues, so no phone fetches the whole thing; a
    /// chip whose set is bigger says so with a "+".
    private let limit = 100

    /// A week is what "Recent" means here: touched in the last seven
    /// days.
    private let recentWindow: TimeInterval = 7 * 24 * 60 * 60

    private let service = IssueFilterService()

    private var activeIssues: [Issue] = []
    private var backlogIssues: [Issue] = []
    private var doneIssues: [Issue] = []
    private var allIssues: [Issue] = []
    private var inboxIssues: [InboxIssue] = []
    private var attentionItems: [AttentionFeedItem] = []

    private var activeOverflow = false
    private var backlogOverflow = false
    private var doneOverflow = false
    private var allOverflow = false
    private var inboxOverflow = false
    private var attentionOverflow = false

    private var failures: [String] = []

    /// The count on the selected chip, if it has one.
    var selectedCount: ChipCount? {
        counts[selection]
    }

    /// The reason the last load could not finish, if it could not.
    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// A line under the list when the selected chip is showing only the
    /// first slice of a larger set.
    var notice: String? {
        guard let count = counts[selection], count.overflow else { return nil }
        return "Showing the first \(count.value). The board has more."
    }

    func select(_ chip: IssueChip) {
        guard chip != selection else { return }
        selection = chip
        rows = makeRows(for: chip)
    }

    /// Load every dataset the chips count from. The requests run
    /// concurrently; one failing endpoint leaves its chips empty instead
    /// of blanking the tab.
    func refresh(auth: Credentials) async {
        state = .loading
        failures = []

        async let active = loadIssues(auth, statuses: IssueStatusSet.active)
        async let backlog = loadIssues(auth, statuses: IssueStatusSet.backlog)
        async let done = loadIssues(auth, statuses: IssueStatusSet.done)
        async let all = loadIssues(auth, statuses: [])
        async let inbox = loadInbox(auth)
        async let attention = loadAttention(auth)

        let (activeResult, backlogResult, doneResult, allResult, inboxResult, attentionResult) =
            await (active, backlog, done, all, inbox, attention)

        activeIssues = activeResult.issues
        activeOverflow = activeResult.overflow
        backlogIssues = backlogResult.issues
        backlogOverflow = backlogResult.overflow
        doneIssues = doneResult.issues
        doneOverflow = doneResult.overflow
        allIssues = allResult.issues
        allOverflow = allResult.overflow
        inboxIssues = inboxResult.issues
        inboxOverflow = inboxResult.overflow
        attentionItems = attentionResult.items
        attentionOverflow = attentionResult.overflow

        rebuildCounts()
        rows = makeRows(for: selection)

        if failures.isEmpty {
            state = .loaded
        } else {
            let message = failures.joined(separator: "\n")
            state = .failed(message)
            banner = message
        }
    }

    // MARK: - Loading

    private struct IssueBatch {
        let issues: [Issue]
        let overflow: Bool
    }

    private struct InboxBatch {
        let issues: [InboxIssue]
        let overflow: Bool
    }

    private struct AttentionBatch {
        let items: [AttentionFeedItem]
        let overflow: Bool
    }

    private func loadIssues(_ auth: Credentials, statuses: [String]) async -> IssueBatch {
        do {
            let issues = try await service.issues(auth: auth, statuses: statuses, limit: limit)
            return IssueBatch(issues: issues, overflow: issues.count >= limit)
        } catch {
            failures.append(Self.message(for: error))
            return IssueBatch(issues: [], overflow: false)
        }
    }

    private func loadInbox(_ auth: Credentials) async -> InboxBatch {
        do {
            let feed = try await service.inbox(auth: auth)
            let issues = feed.issues ?? []
            return InboxBatch(issues: issues, overflow: issues.count >= limit)
        } catch {
            failures.append(Self.message(for: error))
            return InboxBatch(issues: [], overflow: false)
        }
    }

    private func loadAttention(_ auth: Credentials) async -> AttentionBatch {
        do {
            let feed = try await service.attention(auth: auth, limit: limit)
            let items = feed.items ?? []
            let truncated = items.count >= limit || (feed.totalCount ?? 0) > items.count
            return AttentionBatch(items: items, overflow: truncated)
        } catch {
            failures.append(Self.message(for: error))
            return AttentionBatch(items: [], overflow: false)
        }
    }

    // MARK: - Counts

    private func rebuildCounts() {
        var counts: [IssueChip: ChipCount] = [:]

        counts[.active] = ChipCount(value: activeIssues.count, overflow: activeOverflow)
        counts[.backlog] = ChipCount(value: backlogIssues.count, overflow: backlogOverflow)
        counts[.done] = ChipCount(value: doneIssues.count, overflow: doneOverflow)
        counts[.all] = ChipCount(value: allIssues.count, overflow: allOverflow)

        let pendingIssues = attentionItems.filter { $0.isPendingDecision }
        counts[.needsAttention] = ChipCount(value: Set(pendingIssues.compactMap { $0.issueID }).count,
                                             overflow: attentionOverflow)

        counts[.mine] = ChipCount(value: inboxIssues.count, overflow: inboxOverflow)
        counts[.unread] = ChipCount(value: inboxIssues.filter { $0.isUnreadForMe == true }.count,
                                     overflow: inboxOverflow)
        counts[.blocked] = ChipCount(value: inboxIssues.filter { $0.status == "blocked" }.count,
                                      overflow: inboxOverflow)
        counts[.recent] = ChipCount(value: inboxIssues.filter { isRecent($0) }.count,
                                     overflow: inboxOverflow)
        counts[.everything] = ChipCount(value: deskItems().count,
                                         overflow: inboxOverflow || attentionOverflow)

        self.counts = counts
    }

    /// Everything that is on the board user's desk: their own inbox, the
    /// issues waiting on a decision, and anything blocked company-wide.
    private func deskItems() -> [IssueListItem] {
        var byId: [String: IssueListItem] = [:]
        for issue in inboxIssues {
            byId[issue.id] = IssueListItem(inboxIssue: issue)
        }
        for issue in activeIssues where issue.status == "blocked" {
            if byId[issue.id] == nil {
                byId[issue.id] = IssueListItem(issue: issue)
            }
        }
        for item in attentionItems where item.isPendingDecision {
            let row = IssueListItem(attention: item)
            if byId[row.id] == nil {
                byId[row.id] = row
            }
        }
        return byId.keys.sorted().compactMap { byId[$0] }
    }

    // MARK: - Rows

    private func makeRows(for chip: IssueChip) -> [IssueListItem] {
        switch chip {
        case .active:
            return activeIssues.map(IssueListItem.init(issue:))
        case .backlog:
            return backlogIssues.map(IssueListItem.init(issue:))
        case .done:
            return doneIssues.map(IssueListItem.init(issue:))
        case .all:
            return allIssues.map(IssueListItem.init(issue:))
        case .needsAttention:
            return attentionItems
                .filter { $0.isPendingDecision }
                .map(IssueListItem.init(attention:))
        case .mine:
            return inboxIssues.map(IssueListItem.init(inboxIssue:))
        case .unread:
            return inboxIssues
                .filter { $0.isUnreadForMe == true }
                .map(IssueListItem.init(inboxIssue:))
        case .blocked:
            return inboxIssues
                .filter { $0.status == "blocked" }
                .map(IssueListItem.init(inboxIssue:))
        case .recent:
            return inboxIssues
                .filter { isRecent($0) }
                .map(IssueListItem.init(inboxIssue:))
        case .everything:
            return deskItems()
        }
    }

    // MARK: - Helpers

    private func isRecent(_ issue: InboxIssue) -> Bool {
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

    private static func message(for error: Error) -> String {
        (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
    }
}
