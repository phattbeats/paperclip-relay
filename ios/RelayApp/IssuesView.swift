import SwiftUI

struct IssuesView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    @State private var search = ""
    @State private var statusFilter = ""

    private let filters = ["", "todo", "in_progress", "blocked", "in_review", "done"]

    var body: some View {
        NavigationView {
            Group {
                if board.issuesState == .loading && board.issues.isEmpty {
                    ProgressView()
                } else if board.issues.isEmpty {
                    EmptyState(
                        title: "No issues",
                        message: "Nothing matches this filter.",
                        actionTitle: "Reload",
                        action: {
                            Task { await board.refreshIssues(auth: session.credentials) }
                        }
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Issues")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Status", selection: $statusFilter) {
                            ForEach(filters, id: \.self) { value in
                                Text(value.isEmpty ? "All" : value.replacingOccurrences(of: "_", with: " "))
                                    .tag(value)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .searchable(text: $search, prompt: "Search titles")
        }
        .navigationViewStyle(.stack)
    }

    private var list: some View {
        List {
            ForEach(filtered) { issue in
                NavigationLink {
                    IssueDetailView(issueID: issue.id)
                } label: {
                    IssueRow(issue: issue, agentName: board.agentById[issue.assigneeAgentId ?? ""]?.name)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await board.refreshIssues(auth: session.credentials)
        }
    }

    private var filtered: [Issue] {
        var result = board.issues
        if !statusFilter.isEmpty {
            result = result.filter { $0.status == statusFilter }
        }
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(needle)
                    || ($0.identifier?.lowercased().contains(needle) ?? false)
            }
        }
        return result
    }
}

struct IssueRow: View {
    let issue: Issue
    let agentName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(issue.identifier ?? "—")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
                StatusBadge(status: issue.status)
                Spacer()
                if let priority = issue.priority, priority != "medium" {
                    Text(priority)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(priorityColor(priority))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text(issue.title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if let agentName {
                Label(agentName, systemImage: "person")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "critical": return .red
        case "high": return .orange
        default: return .secondary
        }
    }
}

/// Status pill. The board's status vocabulary is fixed, so this is a
/// fixed map rather than a colour scale — a status should look the same
/// every time it appears.
struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var label: String {
        status.replacingOccurrences(of: "_", with: " ")
    }

    private var color: Color {
        switch status {
        case "done": return .green
        case "in_progress": return .blue
        case "in_review": return .purple
        case "blocked": return .red
        case "todo": return .orange
        case "cancelled": return .secondary
        default: return .secondary
        }
    }
}
