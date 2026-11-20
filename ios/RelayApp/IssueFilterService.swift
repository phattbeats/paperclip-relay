import Foundation

// The board endpoints the issue filter reads.
//
// These live apart from `BoardService` on purpose: the filter needs a
// different slice of the board (one status set at a time, the board
// user's inbox, the attention feed) and it decodes a narrower shape than
// the rest of the app, so a change to the filter does not touch the
// service every other tab shares.

/// The board user's own inbox — the work waiting on them.
struct InboxFeed: Codable, Hashable {
    let userId: String?
    let issues: [InboxIssue]?
}

/// An issue as the inbox projection returns it.
///
/// The inbox adds fields the plain issue list does not carry — whether the
/// board user has read it, and when they last touched it — and those are
/// exactly the fields the Unread and Recent chips are built on. Decoding a
/// separate type keeps the app's strict "absent key fails loudly" rule
/// intact for the shape the rest of the app depends on.
struct InboxIssue: Codable, Identifiable, Hashable {
    let id: String
    let identifier: String?
    let title: String
    let status: String
    let priority: String?
    let assigneeAgentId: String?
    let updatedAt: String?
    let lastActivityAt: String?
    let myLastTouchAt: String?
    let isUnreadForMe: Bool?
}

/// One item on the attention feed, in the narrow shape the filter needs.
struct AttentionFeedItem: Codable, Identifiable, Hashable {
    let id: String
    let sourceKind: String
    let subject: AttentionFeedSubject?
    let relatedIssue: AttentionFeedIssue?
    let decisionVerbs: [DecisionVerb]?

    /// The issue this item is about, if it is about one.
    ///
    /// The board names that issue in three different places depending on
    /// the kind of item: a question and an approval carry it in the
    /// subject metadata, a review and a blocker name the issue as the
    /// subject itself, and a recovery names it as the related issue.
    var issue: AttentionFeedIssue? {
        if let issueID = subject?.metadata?.issueId {
            if let related = relatedIssue, related.id == issueID { return related }
            return AttentionFeedIssue(id: issueID,
                                       identifier: nil,
                                       title: subject?.title,
                                       status: subject?.status)
        }
        if subject?.kind == "issue", let id = subject?.id {
            return AttentionFeedIssue(id: id,
                                       identifier: subject?.identifier,
                                       title: subject?.title,
                                       status: subject?.status)
        }
        return relatedIssue
    }

    /// Whether this item is waiting on the board user.
    ///
    /// Every item on the attention feed is something that wants a person:
    /// a question to answer, a review to give, a blocker to clear, a
    /// request to sign. An item with no issue behind it — an agent in
    /// error — is on the feed but is not a row in the issue list.
    var needsAttention: Bool {
        issue != nil
    }
}

struct AttentionFeedSubject: Codable, Hashable {
    let kind: String?
    let id: String?
    let identifier: String?
    let title: String?
    let status: String?
    let metadata: AttentionFeedMetadata?
}

struct AttentionFeedMetadata: Codable, Hashable {
    let kind: String?
    let issueId: String?
}

struct AttentionFeedIssue: Codable, Hashable {
    let id: String
    let identifier: String?
    let title: String?
    let status: String?
}

struct AttentionFeedResponse: Codable, Hashable {
    let totalCount: Int?
    let items: [AttentionFeedItem]?
}

final class IssueFilterService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    private func companyPath(_ suffix: String, _ companyId: String) -> String {
        "/api/companies/\(companyId)\(suffix)"
    }

    /// Issues for one status set.
    ///
    /// `statuses` is sent as the board's own comma-separated status
    /// filter, which is how the web board expresses a preset like
    /// "Active" (todo + in_progress + monitoring + in_review + blocked).
    /// An empty list means every status.
    func issues(auth: Credentials, statuses: [String], limit: Int) async throws -> [Issue] {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "view", value: "index"),
        ]
        if !statuses.isEmpty {
            query.append(URLQueryItem(name: "status", value: statuses.joined(separator: ",")))
        }
        return try await client.get(companyPath("/issues", auth.companyId),
                                   query: query,
                                   auth: auth,
                                   as: [Issue].self)
    }

    /// The board user's own inbox.
    func inbox(auth: Credentials) async throws -> InboxFeed {
        try await client.get(companyPath("/inbox/mine", auth.companyId),
                             auth: auth,
                             as: InboxFeed.self)
    }

    /// Issues for one of the board user's inbox filters.
    ///
    /// The board's own issue list takes the filters its inbox tabs use:
    /// `unreadForUserId=me`, `touchedByUserId=me` and `attention=blocked`.
    /// The app's two surfaces read the same endpoints, so the same chip
    /// carries the same number in both of them.
    func issues(auth: Credentials, filter: IssueListFilter, limit: Int) async throws -> [Issue] {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "view", value: "index"),
        ]
        if let statuses = filter.statuses, !statuses.isEmpty {
            query.append(URLQueryItem(name: "status", value: statuses.joined(separator: ",")))
        }
        if filter.touchedByMe { query.append(URLQueryItem(name: "touchedByUserId", value: "me")) }
        if filter.unreadForMe { query.append(URLQueryItem(name: "unreadForUserId", value: "me")) }
        if filter.assignedToMe { query.append(URLQueryItem(name: "assigneeUserId", value: "me")) }
        if filter.blockedAttention { query.append(URLQueryItem(name: "attention", value: "blocked")) }
        return try await client.get(companyPath("/issues", auth.companyId),
                                   query: query,
                                   auth: auth,
                                   as: [Issue].self)
    }

    /// The count of issues that are blocked and want attention.
    ///
    /// This one has a dedicated endpoint on the board, and it is the only
    /// count the board exposes directly — so it is the number the chip
    /// shows rather than the size of a page.
    func blockedCount(auth: Credentials) async throws -> Int {
        struct Count: Decodable { let count: Int }
        let count = try await client.get(companyPath("/issues/count", auth.companyId),
                                         query: [URLQueryItem(name: "attention", value: "blocked")],
                                         auth: auth,
                                         as: Count.self)
        return count.count
    }

    /// The attention feed: what is waiting on the board user.
    ///
    /// Scoped to the board user's own desk (`view=mine`), because this is
    /// the board user's desk and not the company's.
    func attention(auth: Credentials, limit: Int = 100) async throws -> AttentionFeedResponse {
        try await client.get(companyPath("/attention", auth.companyId),
                             query: [
                                URLQueryItem(name: "view", value: "mine"),
                                URLQueryItem(name: "limit", value: String(limit)),
                             ],
                             auth: auth,
                             as: AttentionFeedResponse.self)
    }
}
