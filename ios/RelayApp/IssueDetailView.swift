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
    @State private var attachments: [Attachment] = []
    @State private var interactions: [Interaction] = []
    @State private var answering: Interaction?
    @State private var showingAssignee = false
    @State private var showingProject = false
    @State private var showingLabels = false

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
                        MarkdownView(source: description)
                    }
                }

                if !attachments.isEmpty {
                    Section("Attachments (\(attachments.count))") {
                        ForEach(attachments) { attachment in
                            AttachmentRow(attachment: attachment, auth: session.credentials)
                        }
                    }
                }

                if !interactions.isEmpty {
                    Section("Questions") {
                        ForEach(interactions) { interaction in
                            Button {
                                answering = interaction
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(interaction.title ?? interaction.kind ?? "Question")
                                        .font(.callout)
                                        .foregroundColor(.primary)
                                    if let prompt = interaction.payload?.prompt {
                                        Text(prompt)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Text(interaction.status ?? "pending")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Details") {
                    Button { showingAssignee = true } label: {
                        detailRow("Assignee", assigneeName)
                    }
                    .buttonStyle(.plain)
                    Button { showingProject = true } label: {
                        detailRow("Project", projectName)
                    }
                    .buttonStyle(.plain)
                    detailRow("Created", Format.relative(issue.createdAt))
                    detailRow("Updated", Format.relative(issue.updatedAt))
                }

                Section("Labels") {
                    if issueLabelNames.isEmpty {
                        Text("No labels on this issue.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(issueLabelNames, id: \.self) { name in
                            Label(name).font(.callout)
                        }
                    }
                    Button("Manage labels…") { showingLabels = true }
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
        // The toast gets its own space below the navigation bar instead of
        // covering the issue controls.
        .relayBannerInset()
        .task { await load() }
        .sheet(item: $answering) { interaction in
            InteractionQuestionsSheet(interactionID: interaction.id,
                                      issueID: issueID) {
                await load()
            }
        }
        .sheet(isPresented: $showingAssignee) {
            IssueAssigneeSheet(currentAgentId: issue?.assigneeAgentId) { agentId in
                await applyAssignee(agentId)
            }
        }
        .sheet(isPresented: $showingProject) {
            IssueProjectSheet(currentProjectId: issue?.projectId) { projectId in
                await applyProject(projectId)
            }
        }
        .sheet(isPresented: $showingLabels) {
            IssueLabelsSheet(currentLabelIds: issue?.labelIds ?? []) { labelIds in
                await applyLabels(labelIds)
            }
        }
    }

    private var assigneeName: String {
        guard let id = issue?.assigneeAgentId else { return "Unassigned" }
        return board.agentById[id]?.name ?? "Unassigned"
    }

    private var projectName: String {
        guard let id = issue?.projectId else { return "No project" }
        return board.projectById[id]?.name ?? "No project"
    }

    private var issueLabelNames: [String] {
        (issue?.labels ?? []).compactMap { $0.name }
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
            async let files = service.attachments(issueId: issueID, auth: auth)
            async let questions = service.interactions(issueId: issueID, auth: auth)
            issue = try await detail
            comments = try await thread
            attachments = try await files
            interactions = (try await questions).filter { $0.status == "pending" }
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
            board.bannerIsError = false
            board.banner = "Status set to \(newStatus.replacingOccurrences(of: "_", with: " "))"
        } catch {
            board.bannerIsError = true
            board.banner = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyAssignee(_ agentId: String?) async {
        do {
            issue = try await service.updateIssueAssignee(issueId: issueID, agentId: agentId, auth: session.credentials)
            await refreshIssue()
            board.bannerIsError = false
            board.banner = agentId.map { "Assigned to \(board.agentById[$0]?.name ?? "an agent")." } ?? "Assignee cleared."
        } catch {
            board.bannerIsError = true
            board.banner = OpsFailure.message(error)
        }
    }

    private func applyProject(_ projectId: String?) async {
        do {
            issue = try await service.updateIssueProject(issueId: issueID, projectId: projectId, auth: session.credentials)
            await refreshIssue()
            board.bannerIsError = false
            board.banner = projectId.map { "Moved to \(board.projectById[$0]?.name ?? "a project")." } ?? "Removed from its project."
        } catch {
            board.bannerIsError = true
            board.banner = OpsFailure.message(error)
        }
    }

    private func applyLabels(_ labelIds: [String]) async {
        do {
            issue = try await service.updateIssueLabels(issueId: issueID, labelIds: labelIds, auth: session.credentials)
            await refreshIssue()
            board.bannerIsError = false
            board.banner = labelIds.isEmpty ? "Labels cleared." : "Labels updated."
        } catch {
            board.bannerIsError = true
            board.banner = OpsFailure.message(error)
        }
    }

    /// The board owns the truth about an issue, so after a write the phone
    /// re-reads it rather than trusting what it sent.
    private func refreshIssue() async {
        if let fresh = try? await service.issue(id: issueID, auth: session.credentials) {
            issue = fresh
        }
    }

    private func post() async {
        posting = true
        defer { posting = false }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            // The server returns the comment it created. Show it right away
            // instead of waiting on a second round trip that may fail or
            // lag behind the write.
            let created = try await service.postComment(issueId: issueID, body: text, auth: session.credentials)
            draft = ""
            if !comments.contains(where: { $0.id == created.id }) {
                // The board serves the newest comment first, so match that.
                comments.insert(created, at: 0)
            }
            // Then reconcile with the board. A failed read is not a failed
            // post: the comment is already on screen.
            do {
                let thread = try await service.comments(issueId: issueID, auth: session.credentials)
                comments = thread
            } catch {
                board.bannerIsError = true
                board.banner = "Comment posted. The thread could not be re-read."
            }
        } catch {
            board.bannerIsError = true
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
