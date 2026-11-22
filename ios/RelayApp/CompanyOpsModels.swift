import Foundation

// MARK: - Spend
//
// Every shape here was read from the live board with a board credential
// before it was written down. Fields that the board might add or omit are
// optional so one unexpected key cannot blank an entire pane.

struct SpendSummary: Codable, Hashable {
    let companyId: String?
    let eventCount: Int?
    let unpricedEventCount: Int?
    let unknownBillingEventCount: Int?
    let estimatedEventCount: Int?
    let pendingRunCount: Int?
    let pricingComplete: Bool?
    let spendCents: Double?
    let spendCentsExact: String?
    let budgetCents: Double?
    let utilizationPercent: Double?
}

struct SpendByAgent: Codable, Identifiable, Hashable {
    let agentId: String?
    let agentName: String?
    let agentStatus: String?
    let eventCount: Int?
    let unpricedEventCount: Int?
    let estimatedEventCount: Int?
    let costCents: Double?
    let costCentsExact: String?
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let apiRunCount: Int?
    let subscriptionRunCount: Int?

    var id: String { agentId ?? "agent-\(agentName ?? "unknown")" }
}

struct SpendByProject: Codable, Identifiable, Hashable {
    let projectId: String?
    let projectName: String?
    let eventCount: Int?
    let unpricedEventCount: Int?
    let costCents: Double?
    let costCentsExact: String?
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?

    var id: String { projectId ?? "unassigned" }
    var title: String { projectName ?? "Unassigned" }
}

struct SpendByProvider: Codable, Identifiable, Hashable {
    let provider: String?
    let biller: String?
    let billingType: String?
    let model: String?
    let costCents: Double?
    let costCentsExact: String?
    let eventCount: Int?
    let estimatedEventCount: Int?
    let unpricedEventCount: Int?
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?

    var id: String { "\(provider ?? "provider")-\(model ?? "model")" }
}

struct WindowSpend: Codable, Identifiable, Hashable {
    let provider: String?
    let biller: String?
    let window: String?
    let windowHours: Int?
    let costCents: Double?
    let costCentsExact: String?
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?

    var id: String { "\(provider ?? "provider")-\(window ?? "window")" }
}

struct BudgetsOverview: Codable, Hashable {
    struct Policy: Codable, Identifiable, Hashable {
        let policyId: String?
        let companyId: String?
        let scopeType: String?
        let scopeId: String?
        let scopeName: String?
        let metric: String?
        let windowKind: String?
        let amount: Double?
        let observedAmount: Double?
        let observedAmountExact: String?
        let reservationCents: String?
        let unpricedEventCount: Int?
        let pendingRunCount: Int?
        let unpricedUsagePolicy: String?

        var id: String { policyId ?? scopeId ?? scopeName ?? "policy" }
    }

    let companyId: String?
    let policies: [Policy]?
    let pausedAgentCount: Int?
    let pausedProjectCount: Int?
    let pendingApprovalCount: Int?
}

struct QuotaReport: Codable, Identifiable, Hashable {
    struct Window: Codable, Identifiable, Hashable {
        let label: String?
        let usedPercent: Double?
        let resetsAt: String?
        let valueLabel: String?
        let detail: String?

        var id: String { label ?? "window" }
    }

    let provider: String?
    let accountKey: String?
    let accountLabel: String?
    let source: String?
    let ok: Bool?
    let windows: [Window]?
    let capturedAt: String?

    var id: String { accountKey ?? accountLabel ?? provider ?? "quota" }
}

// MARK: - People

struct CompanyMembers: Codable, Hashable {
    struct MemberUser: Codable, Hashable {
        let id: String?
        let email: String?
        let name: String?
        let image: String?
    }

    struct Grant: Codable, Identifiable, Hashable {
        let id: String?
        let permissionKey: String?
        let grantedByUserId: String?
        let createdAt: String?

        var id: String { id ?? permissionKey ?? "grant" }
    }

    struct Member: Codable, Identifiable, Hashable {
        let id: String
        let companyId: String?
        let principalType: String?
        let principalId: String?
        let status: String?
        let membershipRole: String?
        let createdAt: String?
        let updatedAt: String?
        let user: MemberUser?
        let grants: [Grant]?
    }

    struct Access: Codable, Hashable {
        let currentUserRole: String?
        let canManageMembers: Bool?
        let canInviteUsers: Bool?
        let canApproveJoinRequests: Bool?
    }

    let members: [Member]?
    let access: Access?
}

// MARK: - Timeline

struct CompanyTimeline: Codable, Hashable {
    struct Actor: Codable, Identifiable, Hashable {
        let id: String
        let type: String?
        let name: String?
        let avatar: String?
    }

    struct Span: Codable, Identifiable, Hashable {
        let actorId: String?
        let laneHint: String?
        let runId: String?
        let issueId: String?
        let issueIdentifier: String?
        let issueTitle: String?
        let start: String?
        let end: String?
        let status: String?
        let retryOfRunId: String?
        let continuationAttempt: Int?
        let invocationSource: String?

        var id: String { runId ?? "\(actorId ?? "actor")-\(start ?? "start")" }
    }

    struct Event: Codable, Identifiable, Hashable {
        let actorId: String?
        let kind: String?
        let issueId: String?
        let at: String?

        var id: String { "\(actorId ?? "actor")-\(kind ?? "event")-\(at ?? "at")" }
    }

    struct Pagination: Codable, Hashable {
        let limit: Int?
        let offset: Int?
        let totalIssues: Int?
        let hasMore: Bool?
    }

    struct Window: Codable, Hashable {
        let from: String?
        let to: String?
        let capped: Bool?
    }

    let actors: [Actor]?
    let spans: [Span]?
    let events: [Event]?
    let pagination: Pagination?
    let window: Window?
}

// MARK: - Health

struct ObservabilityStatus: Codable, Hashable {
    struct LastTest: Codable, Hashable {
        let status: String?
        let finishedAt: String?
    }

    let configured: Bool?
    let enabled: Bool?
    let provider: String?
    let credentialsConfigured: Bool?
    let updatedAt: String?
    let lastTest: LastTest?
}

// MARK: - Shared formatting

enum OpsFormat {
    /// The board reports money in cents, sometimes with fractions.
    static func money(_ cents: Double?) -> String {
        guard let cents else { return "—" }
        return (cents / 100).formatted(.currency(code: "USD"))
    }

    static func compactNumber(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    /// How long a run took, from the board's own start and end stamps.
    static func duration(start: String?, end: String?) -> String {
        guard let start, let end,
              let first = Format.date(start), let last = Format.date(end), last > first else { return "—" }
        let seconds = Int(last.timeIntervalSince(first))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return String(format: "%.1fh", Double(seconds) / 3600)
    }
}
