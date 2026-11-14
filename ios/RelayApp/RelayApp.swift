import SwiftUI

@main
struct RelayApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var board = BoardStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(board)
                .tint(Color.accentColor)
        }
    }
}

/// Shared observable state: the loaded board data and the error surface.
///
/// One store rather than per-view models because the three tabs read the
/// same board and a pull-to-refresh on one should not leave the others
/// showing stale approvals.
@MainActor
final class BoardStore: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var agents: [Agent] = []
    @Published var issues: [Issue] = []
    @Published var approvals: [Approval] = []
    @Published var attention: AttentionResponse?
    @Published var liveRuns: [LiveRun] = []
    @Published var projects: [Project] = []

    @Published var agentsState: LoadState = .idle
    @Published var issuesState: LoadState = .idle
    @Published var approvalsState: LoadState = .idle
    @Published var attentionState: LoadState = .idle

    @Published var banner: String?

    private let service = BoardService()

    var agentById: [String: Agent] {
        Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
    }

    var projectById: [String: Project] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    func refreshAll(auth: Credentials) async {
        agentsState = .loading
        issuesState = .loading
        approvalsState = .loading
        attentionState = .loading

        // The requests run concurrently; the results are assigned on the
        // main actor afterwards. Mutating published state inside the request
        // closures would be a concurrency violation, and a phone on a slow
        // link should not pay for six sequential round trips.
        async let agentsTask = service.agents(auth: auth)
        async let issuesTask = service.issues(auth: auth)
        async let approvalsTask = service.approvals(auth: auth)
        async let attentionTask = service.attention(auth: auth)
        async let runsTask = service.liveRuns(auth: auth)
        async let projectsTask = service.projects(auth: auth)

        let agentsResult = try? await agentsTask
        let issuesResult = try? await issuesTask
        let approvalsResult = try? await approvalsTask
        let attentionResult = try? await attentionTask
        let runsResult = try? await runsTask
        let projectsResult = try? await projectsTask

        if let agentsResult {
            agents = agentsResult
            agentsState = .loaded
        } else {
            agentsState = .failed("Could not load the agent roster.")
        }
        if let issuesResult {
            issues = issuesResult
            issuesState = .loaded
        } else {
            issuesState = .failed("Could not load issues.")
        }
        if let approvalsResult {
            approvals = approvalsResult
            approvalsState = .loaded
        } else {
            approvalsState = .failed("Could not load approvals.")
        }
        if let attentionResult {
            attention = attentionResult
            attentionState = .loaded
        } else {
            attentionState = .failed("Could not load the attention feed.")
        }
        if let runsResult {
            liveRuns = runsResult
        }
        if let projectsResult {
            projects = projectsResult
        }
    }

    func refreshApprovals(auth: Credentials) async {
        approvalsState = .loading
        if let result = try? await service.approvals(auth: auth) {
            approvals = result
            approvalsState = .loaded
        } else {
            approvalsState = .failed("Could not load approvals.")
        }
    }

    func refreshIssues(auth: Credentials) async {
        issuesState = .loading
        if let result = try? await service.issues(auth: auth) {
            issues = result
            issuesState = .loaded
        } else {
            issuesState = .failed("Could not load issues.")
        }
    }

    func refreshAttention(auth: Credentials) async {
        attentionState = .loading
        if let result = try? await service.attention(auth: auth) {
            attention = result
            attentionState = .loaded
        } else {
            attentionState = .failed("Could not load the attention feed.")
        }
    }
}
