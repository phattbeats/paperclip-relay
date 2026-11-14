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

    /// Issue list. `view=index` is the lightweight projection the web UI
    /// uses — descriptions are null there, which is what we want for a
    /// phone list; the full body comes from `issue(id:)`.
    func issues(auth: Credentials, limit: Int = 60, status: String? = nil) async throws -> [Issue] {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "view", value: "index"),
        ]
        if let status, !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        return try await client.get(companyPath("/issues", auth.companyId),
                                   query: query,
                                   auth: auth,
                                   as: [Issue].self)
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

    func attention(auth: Credentials) async throws -> AttentionResponse {
        try await client.get(companyPath("/attention", auth.companyId), auth: auth, as: AttentionResponse.self)
    }

    func boardAPIKeys(auth: Credentials) async throws -> [BoardAPIKey] {
        try await client.get("/api/board-api-keys", auth: auth, as: [BoardAPIKey].self)
    }

    func projects(auth: Credentials) async throws -> [Project] {
        try await client.get(companyPath("/projects", auth.companyId), auth: auth, as: [Project].self)
    }

    // MARK: - Write

    func postComment(issueId: String, body: String, auth: Credentials) async throws {
        _ = try await client.send("POST",
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

    func signIn(baseURL: String, email: String, password: String) async throws -> String {
        try await client.signIn(baseURL: baseURL, email: email, password: password)
    }
}
