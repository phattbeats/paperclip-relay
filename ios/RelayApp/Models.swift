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
    /// Which adapter runs this agent. The model catalog is per adapter, so
    /// the agent detail sheet needs it to list the models it can switch to.
    let adapterType: String?
    let pauseReason: String?
    let spendMonthUtc: String?
    // Money comes back as a fractional cent count (2629.306458), not an
    // integer — declaring these Int would fail the whole agents decode.
    let spentMonthlyCents: Double?
    let budgetMonthlyCents: Double?
    let lifecycleHolds: [String]?
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
    /// Read state for the board user. The inbox's "unread" tab is exactly
    /// the rows where this is true.
    let isUnreadForMe: Bool?
    let myLastTouchAt: String?
    let assigneeUserId: String?
    let createdByUserId: String?
    let reviewAttention: IssueReviewAttention?
}

struct IssueReviewAttention: Codable, Hashable {
    let state: String?
    let reason: String?
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
    /// The issue this request is about, as an identifier (PHA-4914). Only
    /// request_board_approval carries it, and it is what makes the body of
    /// the approval loadable.
    let sourceIssue: String?
    let question: String?
    let recommendation: String?
    let recommendedAction: String?
    let risks: [String]?

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

    /// The body of the request, for a request_board_approval. The other
    /// approval types describe a configuration rather than a decision, and
    /// have no prose body worth rendering.
    var body: String? {
        for candidate in [question, summary, recommendation, recommendedAction, plan, description, details] {
            if let value = candidate, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

/// A file attached to an issue.
struct Attachment: Codable, Identifiable, Hashable {
    let id: String
    let originalFilename: String?
    let contentType: String?
    let byteSize: Int?
    let provider: String?
    let createdAt: String?
    let assetId: String?
    let objectKey: String?

    /// Whether the content endpoint will hand back something a phone can
    /// show inline: an image. Everything else is a file to open, not to
    /// render.
    var isImage: Bool {
        guard let contentType else { return false }
        return contentType.hasPrefix("image/")
    }

    var displayName: String {
        if let originalFilename, !originalFilename.isEmpty { return originalFilename }
        if let contentType { return contentType }
        return "Attachment"
    }

    var sizeLabel: String {
        guard let byteSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }
}

/// One answer to one question on an interaction.
struct InteractionAnswer: Hashable {
    let questionID: String
    var optionIDs: [String] = []
    var otherText: String?
}

/// A decision proposed on the board: a question with options.
///
/// The board's decision status vocabulary is `open`, `decided`, `expired`
/// and `cancelled` — there is no `pending`. An open decision is one the
/// board still has to answer.
struct Decision: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let body: String?
    let status: String?
    let ruleKey: String?
    let originIssueId: String?
    let originAgentId: String?
    let createdAt: String?
    let options: [DecisionOption]?

    /// The issue a decision came from, when it came from one.
    var issueIdentifier: String? {
        guard let originIssueId, !originIssueId.isEmpty else { return nil }
        return originIssueId
    }
}

/// An issue-thread interaction: a question an agent asked on an issue.
///
/// The board resolves these through `accept`/`reject`, or `respond` with
/// the answers to the questions it carries.
struct Interaction: Codable, Identifiable, Hashable {
    let id: String
    let issueId: String?
    let kind: String?
    let status: String?
    let title: String?
    let summary: String?
    let createdByAgentId: String?
    let payload: InteractionPayload?
}

struct InteractionPayload: Codable, Hashable {
    /// The storage form of the questions.
    let questions: [InteractionQuestion]?
    /// The canonical question set. This is the one that says whether a
    /// question is answered with text or with a choice, and the board
    /// validates the answers against it.
    let questionSet: InteractionQuestionSet?
    /// The prose prompt, for a `request_confirmation` interaction.
    let prompt: String?
    let allowDeclineReason: Bool?
}

struct InteractionQuestionSet: Codable, Hashable {
    let schema: String?
    let questions: [InteractionQuestionSetEntry]?
}

struct InteractionQuestionSetEntry: Codable, Hashable {
    let id: String
    let prompt: String?
    /// `text`, `single_select` or `multi_select`.
    let answerMode: String?
    let required: Bool?
    let options: [InteractionSetOption]?
    let customAnswer: InteractionCustomAnswer?
}

struct InteractionSetOption: Codable, Hashable {
    let id: String
    let label: String?
}

struct InteractionCustomAnswer: Codable, Hashable {
    let enabled: Bool?
}

struct InteractionQuestion: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String?
    let selectionMode: String?
    let required: Bool?
    let allowOther: Bool?
    let options: [InteractionOption]?
}

struct InteractionOption: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let freeText: Bool?
}

struct DecisionOption: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let description: String?
    let freeText: Bool?
}

/// A question the board user can answer on the phone.
///
/// The interaction carries two forms of the same question set: a storage
/// form (the one the agent authored) and the canonical question set the
/// board validates against. The canonical set decides whether a question
/// is answered with text or with a choice, so that is the one the app
/// renders and builds answers from.
struct AnswerableQuestion: Identifiable, Hashable {
    let id: String
    let prompt: String
    let isText: Bool
    let isMultiSelect: Bool
    let isRequired: Bool
    let allowsCustomAnswer: Bool
    let options: [AnswerableOption]

    struct AnswerableOption: Identifiable, Hashable {
        let id: String
        let label: String
    }
}

extension Interaction {
    /// The questions on this interaction, in the order the board asks them.
    func answerableQuestions() -> [AnswerableQuestion] {
        let storage = payload?.questions ?? []
        let canonical = payload?.questionSet?.questions ?? []

        if !canonical.isEmpty {
            return canonical.map { entry in
                let stored = storage.first { $0.id == entry.id }
                let mode = entry.answerMode
                    ?? (stored?.selectionMode == "multi" ? "multi_select" : "single_select")
                let allowsCustom = entry.customAnswer?.enabled == true
                    || stored?.allowOther == true
                    || (stored?.options?.contains { $0.freeText == true } ?? false)
                return AnswerableQuestion(
                    id: entry.id,
                    prompt: entry.prompt ?? stored?.prompt ?? "",
                    isText: mode == "text",
                    isMultiSelect: mode == "multi_select",
                    isRequired: entry.required ?? stored?.required ?? false,
                    allowsCustomAnswer: allowsCustom,
                    options: (entry.options ?? []).map {
                        AnswerableQuestion.AnswerableOption(id: $0.id, label: $0.label ?? $0.id)
                    })
            }
        }

        // No canonical set: fall back to the storage form, where a lone
        // free-text option means the answer is typed.
        return storage.map { stored in
            let isText = stored.options?.count == 1 && (stored.options?.first?.freeText ?? false)
            let options = (stored.options ?? [])
                .filter { $0.freeText != true }
                .map { AnswerableQuestion.AnswerableOption(id: $0.id, label: $0.label ?? $0.id) }
            return AnswerableQuestion(
                id: stored.id,
                prompt: stored.prompt ?? "",
                isText: isText,
                isMultiSelect: stored.selectionMode == "multi",
                isRequired: stored.required ?? false,
                allowsCustomAnswer: stored.allowOther == true || isText,
                options: options)
        }
    }
}

/// An agent's configuration, which carries the model it runs on.
struct AgentConfiguration: Codable, Hashable {
    let name: String?
    let title: String?
    let role: String?
    let adapterType: String?
    let capabilities: String?
    let adapterConfig: AgentAdapterConfig?
}

struct AgentAdapterConfig: Codable, Hashable {
    let model: String?
    let effort: String?
}

/// A model the board can run an agent on.
struct AdapterModel: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
}

/// The board user's own inbox: the work waiting on them.
struct InboxPayload: Codable, Hashable {
    let userId: String?
    let issues: [Issue]?
    let contextIssues: [Issue]?
    let failureIssueIds: [String]?
}

struct AttentionSubject: Codable, Hashable {
    let kind: String?
    let id: String
    let identifier: String?
    let title: String?
    let status: String?
    let href: String?
    let metadata: AttentionSubjectMetadata?
}

/// The subject's metadata. For an issue-thread interaction this is where
/// the issue the interaction belongs to is named, which is what makes the
/// interaction resolvable from the phone.
struct AttentionSubjectMetadata: Codable, Hashable {
    let kind: String?
    let issueId: String?
    let createdByAgentId: String?
    let createdByUserId: String?
    let targetDocumentKey: String?
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
    let activityAt: String?
    let rank: Double?
    let stale: Bool?

    /// The issue this item is about, when it is about an issue. An
    /// interaction names its issue in the subject metadata; the other
    /// sources carry it on the related issue.
    var issueID: String? {
        if let fromMetadata = subject?.metadata?.issueId { return fromMetadata }
        if let related = relatedIssue { return related.id }
        return nil
    }

    /// The label for the human-facing kind of thing this is.
    /// Whether this item is an agent's question on an issue thread.
    var isInteraction: Bool {
        sourceKind == "issue_thread_interaction"
    }

    var sourceLabel: String {
        switch sourceKind {
        case "approval": return "Approval"
        case "issue_thread_interaction": return "Question"
        case "review": return "Review"
        case "blocker_attention": return "Blocked"
        case "recovery_action": return "Recovery"
        default: return sourceKind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// An issue-thread interaction waiting on the board user, paired with the
/// attention item that surfaced it.
///
/// The attention feed does not carry the interaction's questions — it names
/// the interaction and the issue it belongs to. The questions come from
/// `GET /api/issues/{id}/interactions`.
struct PendingInteraction: Identifiable, Hashable {
    let id: String
    let issueID: String
    let issueIdentifier: String?
    let issueTitle: String?
    let title: String?
    let kind: String?
    let severity: String?
    let verbs: [DecisionVerb]

    init(item: AttentionItem) {
        self.id = item.subject?.id ?? item.id
        self.issueID = item.issueID ?? ""
        self.issueIdentifier = item.relatedIssue?.identifier
        self.issueTitle = item.relatedIssue?.title
        self.title = item.subject?.title
        self.kind = item.subject?.metadata?.kind
        self.severity = item.severity
        self.verbs = item.decisionVerbs ?? []
    }
}

/// The issue-list filter a tab resolves to.
struct IssueListFilter: Hashable {
    var statuses: [String]?
    var touchedByMe: Bool = false
    var unreadForMe: Bool = false
    var assignedToMe: Bool = false
    var blockedAttention: Bool = false

    var isEmpty: Bool {
        statuses == nil && !touchedByMe && !unreadForMe && !assignedToMe && !blockedAttention
    }
}

struct DecisionVerb: Codable, Identifiable, Hashable {
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
    let nextCursor: String?
    let viewCounts: [String: Int]?
}

/// The task views the board itself offers, and the statuses behind each.
///
/// These are the board's own vocabulary, not a guess: `active` is the set
/// of statuses the board considers open, `done` includes cancelled, and
/// `backlog` is not started yet.
enum TaskView: String, CaseIterable, Identifiable {
    case active
    case backlog
    case done
    case all
    case needsAttention = "needs_attention"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .needsAttention: return "Needs attention"
        case .all: return "All"
        default: return rawValue.capitalized
        }
    }

    /// The statuses in this view, or nil for a view that is not a status
    /// filter at all.
    var statuses: [String]? {
        switch self {
        case .active: return ["todo", "in_progress", "monitoring", "in_review", "blocked"]
        case .backlog: return ["backlog"]
        case .done: return ["done", "cancelled"]
        case .all: return nil
        case .needsAttention: return nil
        }
    }
}

extension Issue {
    /// A minimal issue record, for the rows the board summarizes rather
    /// than returns in full — the attention feed names an issue and gives
    /// its title and status, but not the rest.
    init(id: String, identifier: String?, title: String, status: String) {
        self.init(id: id,
                  identifier: identifier,
                  title: title,
                  description: nil,
                  status: status,
                  priority: nil,
                  assigneeAgentId: nil,
                  projectId: nil,
                  parentId: nil,
                  createdAt: nil,
                  updatedAt: nil,
                  lastActivityAt: nil,
                  completedAt: nil,
                  displayStatus: nil,
                  labels: nil,
                  listProjection: nil,
                  isUnreadForMe: nil,
                  myLastTouchAt: nil,
                  assigneeUserId: nil,
                  createdByUserId: nil,
                  reviewAttention: nil)
    }
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
