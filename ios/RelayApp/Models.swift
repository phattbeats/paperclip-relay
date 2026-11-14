import Foundation

// Wire types for the Paperclip board API.
//
// These mirror the JSON the deployed instance actually returns (verified
// against https://paperclip.phatt.vip on 2026-11-14). Every field the app
// does not use is deliberately absent rather than optional-and-ignored:
// an absent key fails to decode loudly, which is what we want when upstream
// changes a shape we depend on.

struct CompanyRef: Codable, Hashable {
    let id: String
    let name: String?
}

struct Company: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let issuePrefix: String?
    let status: String?
}

struct Agent: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let title: String?
    let role: String?
    let icon: String?
    let status: String?
    let lifecycleState: String?
    let errorReason: String?
    let reportsTo: String?
    let capabilities: String?
    let lastHeartbeatAt: String?
    let updatedAt: String?
    let urlKey: String?
    let spendMonthUtc: String?
    // Money comes back as a fractional cent count (2629.306458), not an
    // integer — declaring these Int would fail the whole agents decode.
    let spentMonthlyCents: Double?
    let budgetMonthlyCents: Double?
}

struct Issue: Codable, Identifiable, Hashable {
    let id: String
    let identifier: String?
    let title: String
    let description: String?
    let status: String
    let priority: String?
    let assigneeAgentId: String?
    let projectId: String?
    let parentId: String?
    let createdAt: String?
    let updatedAt: String?
    let lastActivityAt: String?
    let completedAt: String?
    let displayStatus: String?
    let labels: [IssueLabel]?
    let listProjection: String?
}

struct IssueLabel: Codable, Hashable {
    let id: String
    let name: String?
    let color: String?
}

struct IssueComment: Codable, Identifiable, Hashable {
    let id: String
    let issueId: String?
    let body: String
    let authorType: String?
    let authorAgentId: String?
    let authorUserId: String?
    let createdAt: String?
    let origin: String?
}

struct LiveRun: Codable, Identifiable, Hashable {
    let id: String
    let agentId: String?
    let agentName: String?
    let issueId: String?
    let status: String?
    let startedAt: String?
    let finishedAt: String?
    let currentStatusMessage: String?
    let currentToolName: String?
    let lastAssistantSnippet: String?
    let scopeKind: String?
    let invocationSource: String?
}

struct Approval: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let status: String
    let payload: ApprovalPayload?
    let requestedByAgentId: String?
    let requestedByUserId: String?
    let createdAt: String?
    let updatedAt: String?
    let decidedAt: String?
    let decisionNote: String?
}

struct ApprovalPayload: Codable, Hashable {
    let title: String?
    let name: String?
    let summary: String?
    let plan: String?
    let description: String?
    let command: String?
    let details: String?
    let type: String?
    let issueId: String?

    /// Approval payload keys differ per approval type, so the human-facing
    /// line is whichever of them happens to be populated.
    var displayTitle: String {
        for candidate in [title, name, summary, plan, description, command, details] {
            if let value = candidate, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return type ?? "Approval request"
    }
}

struct AttentionSubject: Codable, Hashable {
    let kind: String?
    let id: String
    let identifier: String?
    let title: String?
    let status: String?
    let href: String?
}

struct AttentionItem: Codable, Identifiable, Hashable {
    let id: String
    let sourceKind: String
    let subject: AttentionSubject?
    let whyNow: String?
    let severity: String?
    let required: Bool?
    let inlineResolvable: Bool?
    let decisionVerbs: [DecisionVerb]?
    let relatedIssue: AttentionRelatedIssue?
    let createdAt: String?
    let updatedAt: String?
}

struct DecisionVerb: Codable, Hashable {
    let id: String
    let label: String?
    let description: String?
}

struct AttentionRelatedIssue: Codable, Hashable {
    let id: String
    let identifier: String?
    let title: String?
    let status: String?
}

struct AttentionResponse: Codable, Hashable {
    let companyId: String
    let generatedAt: String?
    let totalCount: Int
    let deskBadgeCount: Int
    let countsBySourceKind: [String: Int]?
    let items: [AttentionItem]?
}

struct BoardAPIKey: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let createdAt: String?
    let lastUsedAt: String?
    let revokedAt: String?
    let expiresAt: String?
}

struct Project: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String?
    let color: String?
    let icon: String?
    let description: String?
    let urlKey: String?
}
