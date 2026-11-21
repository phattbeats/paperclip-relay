import SwiftUI

@main
struct RelayApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var board = BoardStore()
    /// One source for the board views and the Inbox queue. Keeping this at
    /// app scope prevents each tab from independently fetching the same
    /// five inbox datasets and then disagreeing about a count.
    @StateObject private var issueFilters = IssueFilterStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(board)
                .environmentObject(issueFilters)
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
    @Published var approvals: [Approval] = []
    @Published var attention: AttentionResponse?
    @Published var liveRuns: [LiveRun] = []
    @Published var projects: [Project] = []

    /// Decisions the board still has to answer.
    @Published var decisions: [Decision] = []

    /// Agent questions on issue threads, waiting on the board user.
    @Published var pendingInteractions: [PendingInteraction] = []

    @Published var agentsState: LoadState = .idle
    @Published var approvalsState: LoadState = .idle
    @Published var attentionState: LoadState = .idle

    @Published var banner: String?

    /// Whether the current banner reports a failure or a confirmation.
    /// A confirmation ("Status set to todo.") gets a checkmark; a failure
    /// gets the warning triangle. Without this, a success message wears an
    /// error icon and reads as a problem.
    @Published var bannerIsError: Bool = true

    private let service = BoardService()

    var agentById: [String: Agent] {
        Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
    }

    var projectById: [String: Project] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    /// Load everything the three tabs read. The requests run concurrently;
    /// each one owns its own state and its own error, so one failing
    /// endpoint does not blank the rest of the app.
    ///
    /// The issue list is not here: the Issues tab owns its own datasets
    /// (`IssueFilterStore`), because it reads one status set at a time
    /// rather than a single list.
    func refreshAll(auth: Credentials) async {
        async let agentsLoad = loadAgents(auth)
        async let approvalsLoad = loadApprovals(auth)
        async let attentionLoad = loadAttention(auth)
        async let runsLoad = loadLiveRuns(auth)
        async let projectsLoad = loadProjects(auth)
        async let decisionsLoad = loadDecisions(auth)
        _ = await (agentsLoad, approvalsLoad, attentionLoad, runsLoad,
                   projectsLoad, decisionsLoad)
    }

    func refreshApprovals(auth: Credentials) async {
        await loadApprovals(auth)
    }

    func refreshAttention(auth: Credentials) async {
        await loadAttention(auth)
    }

    /// Reload the decisions and the questions waiting on the board user.
    func refreshDecisions(auth: Credentials) async {
        await loadDecisions(auth)
        await loadAttention(auth)
    }

    private func loadAgents(_ auth: Credentials) async {
        do {
            agents = try await service.agents(auth: auth)
            agentsState = .loaded
        } catch {
            agentsState = .failed(Self.message(for: error))
            bannerIsError = true
            banner = Self.message(for: error)
        }
    }

    private func loadApprovals(_ auth: Credentials) async {
        do {
            approvals = try await service.approvals(auth: auth)
            approvalsState = .loaded
        } catch {
            approvalsState = .failed(Self.message(for: error))
            bannerIsError = true
            banner = Self.message(for: error)
        }
    }

    private func loadAttention(_ auth: Credentials) async {
        do {
            attention = try await service.attention(auth: auth)
            pendingInteractions = (attention?.items ?? [])
                .filter { $0.isInteraction }
                .map(PendingInteraction.init(item:))
            attentionState = .loaded
        } catch {
            attentionState = .failed(Self.message(for: error))
            bannerIsError = true
            banner = Self.message(for: error)
        }
    }

    private func loadLiveRuns(_ auth: Credentials) async {
        do {
            liveRuns = try await service.liveRuns(auth: auth)
        } catch {
            bannerIsError = true
            banner = Self.message(for: error)
        }
    }

    private func loadProjects(_ auth: Credentials) async {
        do {
            projects = try await service.projects(auth: auth)
        } catch {
            bannerIsError = true
            banner = Self.message(for: error)
        }
    }

    private func loadDecisions(_ auth: Credentials) async {
        do {
            decisions = try await service.decisions(auth: auth)
        } catch {
            bannerIsError = true
            banner = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
    }
}
