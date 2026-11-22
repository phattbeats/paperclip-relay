import Foundation

struct CompanyDashboard: Codable, Hashable {
    struct AgentCounts: Codable, Hashable {
        let active: Int
        let running: Int
        let paused: Int
        let error: Int
    }

    struct TaskCounts: Codable, Hashable {
        let open: Int
        let inProgress: Int
        let blocked: Int
        let done: Int
    }

    struct Costs: Codable, Hashable {
        let monthSpendCents: Double?
        let monthBudgetCents: Double?
        let monthUtilizationPercent: Double?
    }

    struct RunActivity: Codable, Hashable, Identifiable {
        let date: String
        let succeeded: Int
        let failed: Int
        let recovered: Int
        let other: Int
        let total: Int
        let failedByErrorCode: [String: Int]?

        var id: String { date }
    }

    struct Budgets: Codable, Hashable {
        let activeIncidents: Int?
        let pendingApprovals: Int?
        let pausedAgents: Int?
        let pausedProjects: Int?
    }

    let companyId: String
    let agents: AgentCounts
    let tasks: TaskCounts
    let costs: Costs
    let pendingApprovals: Int
    let budgets: Budgets?
    let runActivity: [RunActivity]
}

struct CompanyGoal: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let level: String?
    let status: String?
    let ownerAgentId: String?
    let updatedAt: String?
}

struct CompanyRoutine: Codable, Identifiable, Hashable {
    struct Trigger: Codable, Identifiable, Hashable {
        let id: String
        let kind: String
        let label: String?
        let enabled: Bool
        let cronExpression: String?
        let timezone: String?
        let nextRunAt: String?
        let lastFiredAt: String?
        let lastResult: String?
    }

    let id: String
    let title: String
    let status: String?
    let priority: String?
    let assigneeAgentId: String?
    let lastTriggeredAt: String?
    let triggers: [Trigger]?
}

struct CompanyActivity: Codable, Identifiable, Hashable {
    let id: String
    let actorType: String?
    let actorName: String?
    let action: String?
    let entityType: String?
    let entityId: String?
    let createdAt: String?
}

struct CompanyOrgNode: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String?
    let status: String?
    let reports: [CompanyOrgNode]
}

struct CompanySearchResponse: Codable, Hashable {
    struct Result: Codable, Identifiable, Hashable {
        let id: String
        let type: String
        let title: String?
        let href: String?
        let sourceLabel: String?
        let snippet: String?
        let updatedAt: String?
    }

    let query: String
    let results: [Result]
    let hasMore: Bool
}

struct CreatedBoardAPIKey: Codable, Hashable {
    let id: String?
    let name: String?
    let token: String?
    let key: String?
    let expiresAt: String?

    var secret: String? { token ?? key }
}
