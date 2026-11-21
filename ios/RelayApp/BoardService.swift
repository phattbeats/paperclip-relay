import Foundation

/// Typed calls against the board endpoints the app uses.
///
/// Every route here was probed live against the deployed instance with a
/// board credential, so the shapes and status codes are known rather than
/// assumed.
final class BoardService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    private func companyPath(_ suffix: String, _ companyId: String) -> String {
        "/api/companies/\(companyId)\(suffix)"
    }

    // MARK: - Read

    /// The companies this board key can see. The app uses it to find its own
    /// company id instead of making the user type a UUID.
    func companies(auth: Credentials) async throws -> [Company] {
        try await client.get("/api/companies", auth: auth, as: [Company].self)
    }

    func agents(auth: Credentials) async throws -> [Agent] {
        try await client.get(companyPath("/agents", auth.companyId), auth: auth, as: [Agent].self)
    }

    func issue(id: String, auth: Credentials) async throws -> Issue {
        try await client.get("/api/issues/\(id)", auth: auth, as: Issue.self)
    }

    func comments(issueId: String, auth: Credentials) async throws -> [IssueComment] {
        try await client.get("/api/issues/\(issueId)/comments", auth: auth, as: [IssueComment].self)
    }

    func liveRuns(auth: Credentials) async throws -> [LiveRun] {
        try await client.get(companyPath("/live-runs", auth.companyId), auth: auth, as: [LiveRun].self)
    }

    func approvals(auth: Credentials, status: String = "pending") async throws -> [Approval] {
        try await client.get(companyPath("/approvals", auth.companyId),
                             query: [URLQueryItem(name: "status", value: status)],
                             auth: auth,
                             as: [Approval].self)
    }

    /// The attention feed: what is waiting on the board user.
    ///
    /// The live views are `mine`, `unassigned`, `company`, `archived` and
    /// `all`. The web UI's own inbox tab names (mine/unread/blocked/recent/
    /// everything) are a client-side composition over several sources, not
    /// server views — so the app derives them itself in `InboxView`.
    func attention(auth: Credentials, view: String = "mine", limit: Int = 100) async throws -> AttentionResponse {
        try await client.get(companyPath("/attention", auth.companyId),
                             query: [
                                URLQueryItem(name: "view", value: view),
                                URLQueryItem(name: "limit", value: String(limit)),
                             ],
                             auth: auth,
                             as: AttentionResponse.self)
    }

    /// The board user's own inbox: the issues waiting on them.
    func inbox(auth: Credentials) async throws -> InboxPayload {
        try await client.get(companyPath("/inbox/mine", auth.companyId), auth: auth, as: InboxPayload.self)
    }

    /// The issue list, filtered the way the board filters it.
    ///
    /// The list endpoint takes a comma-separated `status` set and the
    /// inbox filters (`touchedByUserId=me`, `unreadForUserId=me`,
    /// `assigneeUserId=me`, `attention=blocked`). That is what the app's
    /// filter chips and inbox tabs are built on, rather than a filter
    /// invented for the phone.
    func issues(auth: Credentials,
                limit: Int = 60,
                statuses: [String]? = nil) async throws -> [Issue] {
        try await issues(auth: auth,
                         limit: limit,
                         offset: 0,
                         filter: IssueListFilter(statuses: statuses))
    }

    /// The issue list for a filter.
    ///
    /// The board's list endpoint takes a comma-separated `status` set and
    /// the inbox filters (`touchedByUserId=me`, `unreadForUserId=me`,
    /// `assigneeUserId=me`, `attention=blocked`). That is what the app's
    /// inbox tabs are built on, rather than a filter invented for the
    /// phone.
    func issues(auth: Credentials,
                limit: Int = 60,
                offset: Int = 0,
                filter: IssueListFilter) async throws -> [Issue] {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "view", value: "index"),
        ]
        if offset > 0 { query.append(URLQueryItem(name: "offset", value: String(offset))) }
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

    /// The interactions on an issue, with their questions.
    func interactions(issueId: String, auth: Credentials) async throws -> [Interaction] {
        try await client.get("/api/issues/\(issueId)/interactions", auth: auth, as: [Interaction].self)
    }

    /// Answer the questions on an interaction.
    func respondToInteraction(issueId: String,
                              interactionId: String,
                              answers: [InteractionAnswer],
                              summary: String?,
                              auth: Credentials) async throws {
        var body: [String: Any] = [
            "answers": answers.map { answer -> [String: Any] in
                var entry: [String: Any] = [
                    "questionId": answer.questionID,
                    "optionIds": answer.optionIDs,
                ]
                if let other = answer.otherText, !other.isEmpty { entry["otherText"] = other }
                return entry
            },
        ]
        if let summary, !summary.isEmpty { body["summaryMarkdown"] = summary }
        try await client.send("POST",
                              "/api/issues/\(issueId)/interactions/\(interactionId)/respond",
                              body: body,
                              auth: auth)
    }

    /// Decisions awaiting a choice.
    ///
    /// Pending decisions are the choices currently waiting on the board
    /// user. The API returns the question body and its options together,
    /// which lets the Issues tab render the card without another fetch.
    func decisions(auth: Credentials, status: String = "pending", limit: Int = 50) async throws -> [Decision] {
        try await client.get(companyPath("/decisions", auth.companyId),
                             query: [
                                URLQueryItem(name: "status", value: status),
                                URLQueryItem(name: "limit", value: String(limit)),
                             ],
                             auth: auth,
                             as: [Decision].self)
    }

    /// The issues an approval is attached to.
    ///
    /// The approval payload does not carry the issue — the board keeps that
    /// link in its own table — so the issue behind a request is read from
    /// here. Verified live: a pending request_board_approval points at
    /// exactly one issue, and that issue's body is the thing a person has
    /// to read before signing.
    func approvalIssues(id: String, auth: Credentials) async throws -> [ApprovalIssueLink] {
        try await client.get("/api/approvals/\(id)/issues", auth: auth, as: [ApprovalIssueLink].self)
    }

    /// Files attached to an issue.
    func attachments(issueId: String, auth: Credentials) async throws -> [Attachment] {
        try await client.get("/api/issues/\(issueId)/attachments", auth: auth, as: [Attachment].self)
    }

    /// The count of issues that are blocked and want attention.
    ///
    /// This one has a dedicated endpoint, and it is the only count the board
    /// exposes directly.
    func blockedCount(auth: Credentials) async throws -> Int {
        struct Count: Decodable { let count: Int }
        let count = try await client.get(companyPath("/issues/count", auth.companyId),
                                         query: [URLQueryItem(name: "attention", value: "blocked")],
                                         auth: auth,
                                         as: Count.self)
        return count.count
    }

    /// An agent's configuration, which carries the model it runs on.
    func agentConfiguration(id: String, auth: Credentials) async throws -> AgentConfiguration {
        try await client.get("/api/agents/\(id)/configuration", auth: auth, as: AgentConfiguration.self)
    }

    /// The models an adapter can run an agent on.
    func adapterModels(type: String, auth: Credentials) async throws -> [AdapterModel] {
        try await client.get(companyPath("/adapters/\(type)/models", auth.companyId),
                             auth: auth,
                             as: [AdapterModel].self)
    }

    func boardAPIKeys(auth: Credentials) async throws -> [BoardAPIKey] {
        try await client.get("/api/board-api-keys", auth: auth, as: [BoardAPIKey].self)
    }

    func projects(auth: Credentials) async throws -> [Project] {
        try await client.get(companyPath("/projects", auth.companyId), auth: auth, as: [Project].self)
    }

    // MARK: - Write

    /// Post a comment. The server returns the created comment, so the
    /// caller can show it without waiting for a second round trip.
    @discardableResult
    func postComment(issueId: String, body: String, auth: Credentials) async throws -> IssueComment {
        try await client.send("POST",
                              "/api/issues/\(issueId)/comments",
                              body: ["body": body],
                              auth: auth,
                              as: IssueComment.self)
    }

    /// Update an issue. A `comment` in the same call is created in the same
    /// write, which the server requires for review and approval decisions —
    /// a separate comment POST does not satisfy the guard.
    func updateIssue(id: String,
                     status: String? = nil,
                     priority: String? = nil,
                     comment: String? = nil,
                     auth: Credentials) async throws -> Issue {
        var body: [String: Any] = [:]
        if let status { body["status"] = status }
        if let priority { body["priority"] = priority }
        if let comment, !comment.isEmpty { body["comment"] = comment }
        return try await client.send("PATCH", "/api/issues/\(id)", body: body, auth: auth, as: Issue.self)
    }

    func approve(id: String, note: String?, auth: Credentials) async throws {
        var body: [String: Any] = [:]
        if let note, !note.isEmpty { body["decisionNote"] = note }
        _ = try await client.send("POST", "/api/approvals/\(id)/approve", body: body, auth: auth)
    }

    func reject(id: String, note: String?, auth: Credentials) async throws {
        var body: [String: Any] = [:]
        if let note, !note.isEmpty { body["decisionNote"] = note }
        _ = try await client.send("POST", "/api/approvals/\(id)/reject", body: body, auth: auth)
    }

    // MARK: - Agent control

    /// Pause an agent. Verified live against the board: the agent's status
    /// becomes `paused` and a `manual` hold appears.
    func pauseAgent(id: String, auth: Credentials) async throws {
        try await client.send("POST", "/api/agents/\(id)/pause", body: [:], auth: auth)
    }

    /// Resume a paused agent.
    func resumeAgent(id: String, auth: Credentials) async throws {
        try await client.send("POST", "/api/agents/\(id)/resume", body: [:], auth: auth)
    }

    /// Change the model an agent runs on.
    ///
    /// The board merges a partial `adapterConfig` rather than replacing it,
    /// so sending only the model leaves the rest of the agent's settings
    /// alone. Verified live: a partial patch preserved every other key.
    func updateAgentModel(id: String, model: String, auth: Credentials) async throws {
        try await client.send("PATCH", "/api/agents/\(id)",
                              body: ["adapterConfig": ["model": model]],
                              auth: auth)
    }

    // MARK: - Decision resolution

    /// Accept a pending issue-thread interaction.
    func acceptInteraction(issueId: String, interactionId: String, auth: Credentials) async throws {
        try await client.send("POST",
                              "/api/issues/\(issueId)/interactions/\(interactionId)/accept",
                              body: [:],
                              auth: auth)
    }

    /// Decline a pending issue-thread interaction, with a reason.
    func rejectInteraction(issueId: String, interactionId: String, reason: String?, auth: Credentials) async throws {
        var body: [String: Any] = [:]
        if let reason, !reason.isEmpty { body["reason"] = reason }
        try await client.send("POST",
                              "/api/issues/\(issueId)/interactions/\(interactionId)/reject",
                              body: body,
                              auth: auth)
    }

    /// Choose an option on a pending decision.
    ///
    /// `inputValues` carries the text of an option that asks for one; the
    /// board takes it as a flat map of strings.
    func decide(id: String,
                optionId: String,
                inputValues: [String: String] = [:],
                auth: Credentials) async throws {
        var body: [String: Any] = ["optionId": optionId]
        if !inputValues.isEmpty { body["inputValues"] = inputValues }
        try await client.send("POST", "/api/decisions/\(id)/decide",
                              body: body,
                              auth: auth)
    }

    /// The attachment's bytes, for a sheet that shows a file inline.
    func attachmentContent(id: String, auth: Credentials) async throws -> Data {
        try await client.getRaw("/api/attachments/\(id)/content", auth: auth)
    }

    func signIn(baseURL: String, email: String, password: String) async throws -> String {
        try await client.signIn(baseURL: baseURL, email: email, password: password)
    }
}
