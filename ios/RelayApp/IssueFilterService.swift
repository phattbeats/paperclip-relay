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

    /// The issue this item is about. An issue-thread interaction names it
    /// in the subject metadata; the other sources carry it on the related
    /// issue.
    var issueID: String? {
        if let fromSubject = subject?.metadata?.issueId { return fromSubject }
        return relatedIssue?.id
    }

    /// Whether this item is a decision still waiting on an answer, as
    /// opposed to a status change the board is simply reporting.
    var isPendingDecision: Bool {
        guard issueID != nil else { return false }
        guard let status = subject?.status else { return true }
        return status == "pending"
    }
}

struct AttentionFeedSubject: Codable, Hashable {
    let kind: String?
    let id: String?
    let title: String?
    let status: String?
    let metadata: AttentionFeedMetadata?
}

struct AttentionFeedMetadata: Codable, Hashable {
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

    /// The attention feed: what is waiting on a decision.
    func attention(auth: Credentials, limit: Int = 100) async throws -> AttentionFeedResponse {
        try await client.get(companyPath("/attention", auth.companyId),
                             query: [URLQueryItem(name: "limit", value: String(limit))],
                             auth: auth,
                             as: AttentionFeedResponse.self)
    }
}
