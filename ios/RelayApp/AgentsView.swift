import SwiftUI

struct AgentsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    var body: some View {
        NavigationView {
            Group {
                if board.agents.isEmpty {
                    EmptyState(title: "No agents",
                               message: "The board did not return an agent roster.",
                               actionTitle: "Reload") {
                        Task { await board.refreshAll(auth: session.credentials) }
                    }
                } else {
                    List {
                        if !board.liveRuns.isEmpty {
                            Section("Running now") {
                                ForEach(board.liveRuns.prefix(8)) { run in
                                    LiveRunRow(run: run)
                                }
                            }
                        }
                        Section("Roster") {
                            ForEach(board.agents) { agent in
                                AgentRow(agent: agent, runCount: runCount(for: agent.id))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await board.refreshAll(auth: session.credentials)
                    }
                }
            }
            .navigationTitle("Agents")
        }
        .navigationViewStyle(.stack)
    }

    private func runCount(for agentID: String) -> Int {
        board.liveRuns.filter { $0.agentId == agentID }.count
    }
}

struct AgentRow: View {
    let agent: Agent
    let runCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.body.weight(.medium))
                if let title = agent.title, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let error = agent.errorReason, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(agent.status ?? "unknown")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(statusColor)
                if runCount > 0 {
                    Text("\(runCount) active")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let heartbeat = Format.relative(agent.lastHeartbeatAt) as String?, heartbeat != "—" {
                    Text("beat \(heartbeat)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch agent.status {
        case "running": return .green
        case "idle": return .secondary
        case "error": return .red
        case "paused": return .orange
        default: return .secondary
        }
    }
}

struct LiveRunRow: View {
    let run: LiveRun

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(run.agentName ?? "Agent")
                    .font(.subheadline.weight(.medium))
                StatusBadge(status: run.status ?? "running")
                Spacer()
                Text(Format.relative(run.startedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if let message = run.currentStatusMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if let snippet = run.lastAssistantSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
