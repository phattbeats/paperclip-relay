import SwiftUI

struct IssueDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    let issueID: String

    @State private var issue: Issue?
    @State private var comments: [IssueComment] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var draft = ""
    @State private var posting = false
    @State private var newStatus: String?
    @State private var statusNote = ""
    @State private var savingStatus = false

    private let service = BoardService()

    var body: some View {
        Form {
            if let issue {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(issue.identifier ?? "—")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.secondary)
                            StatusBadge(status: issue.status)
                            Spacer()
                            if let priority = issue.priority {
                                Text(priority)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(issue.title)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                if let description = issue.description, !description.isEmpty {
                    Section("Description") {
                        Text(description)
                            .font(.callout)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }

                Section("Details") {
                    detailRow("Assignee", board.agentById[issue.assigneeAgentId ?? ""]?.name ?? "Unassigned")
                    if let project = board.projectById[issue.projectId ?? ""] {
                        detailRow("Project", project.name)
                    }
                    detailRow("Created", Format.relative(issue.createdAt))
                    detailRow("Updated", Format.relative(issue.updatedAt))
                }

                Section {
                    Picker("Status", selection: $newStatus) {
                        Text("Choose…").tag(String?.none)
                        ForEach(["backlog", "todo", "in_progress", "in_review", "done", "blocked"], id: \.self) { value in
                            Text(value.replacingOccurrences(of: "_", with: " ")).tag(String?.some(value))
                        }
                    }
                    TextField("Note (optional)", text: $statusNote, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        Task { await applyStatus() }
                    } label: {
                        if savingStatus {
                            ProgressView()
                        } else {
                            Text("Apply status")
                        }
                    }
                    .disabled(newStatus == nil || savingStatus)
                } header: {
                    Text("Update")
                } footer: {
                    Text("The note travels in the same write as the status change, which the board requires for review decisions.")
                }

                Section("Comments (\(comments.count))") {
                    if comments.isEmpty {
                        Text("No comments yet.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(comments) { comment in
                        CommentCell(comment: comment)
                    }
                }

                Section {
                    TextField("Add a comment", text: $draft, axis: .vertical)
                        .lineLimit(2...6)
                    Button {
                        Task { await post() }
                    } label: {
                        if posting {
                            ProgressView()
                        } else {
                            Text("Post comment")
                        }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || posting)
                }
            } else if loading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let errorMessage {
                Section {
                    Text(errorMessage).foregroundColor(.red).font(.footnote)
                    Button("Retry") { Task { await load() } }
                }
            }
        }
        .navigationTitle(issue?.identifier ?? "Issue")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        let auth = session.credentials
        do {
            async let detail = service.issue(id: issueID, auth: auth)
            async let thread = service.comments(issueId: issueID, auth: auth)
            issue = try await detail
            comments = try await thread
            newStatus = issue?.status
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func applyStatus() async {
        guard let newStatus else { return }
        savingStatus = true
        defer { savingStatus = false }
        do {
            let updated = try await service.updateIssue(id: issueID,
                                                       status: newStatus,
                                                       comment: statusNote.isEmpty ? nil : statusNote,
                                                       auth: session.credentials)
            issue = updated
            statusNote = ""
            comments = (try? await service.comments(issueId: issueID, auth: session.credentials)) ?? comments
            board.banner = "Status set to \(newStatus.replacingOccurrences(of: "_", with: " "))"
        } catch {
            board.banner = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func post() async {
        posting = true
        defer { posting = false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await service.postComment(issueId: issueID, body: text, auth: session.credentials)
            draft = ""
            comments = (try? await service.comments(issueId: issueID, auth: session.credentials)) ?? comments
        } catch {
            board.banner = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct CommentCell: View {
    let comment: IssueComment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: comment.authorType == "agent" ? "cpu" : "person")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(authorLabel)
                    .font(.caption.weight(.semibold))
                Text(Format.relative(comment.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(comment.body)
                .font(.callout)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var authorLabel: String {
        switch comment.authorType {
        case "agent": return "Agent"
        case "user": return "Board"
        default: return comment.authorType ?? "Unknown"
        }
    }
}

/// Date formatting. The board returns ISO-8601 with fractional seconds, and
/// the phone only needs "how long ago" at a glance plus an absolute stamp
/// for the detail view.
enum Format {
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    static func relative(_ value: String?) -> String {
        guard let value, let parsed = date(value) else { return "—" }
        return relativeFormatter.localizedString(for: parsed, relativeTo: Date())
    }

    static func absolute(_ value: String?) -> String {
        guard let value, let parsed = date(value) else { return "—" }
        return absoluteFormatter.string(from: parsed)
    }
}
