import SwiftUI
import UIKit

/// The detail behind an approval.
///
/// An approval row says what is being asked for. It does not say why, and
/// the why is usually in the issue the request came from — so the sheet
/// loads that issue, renders its body as Markdown, and lists whatever is
/// attached to it.
struct ApprovalDetailSheet: View {
    let approval: Approval

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    @State private var issue: Issue?
    @State private var attachments: [Attachment] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var working = false
    @State private var action: ApprovalAction?
    @State private var note = ""

    enum ApprovalAction: String, Identifiable {
        case approve, reject

        var id: String { rawValue }
    }

    private let service = BoardService()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(approval.payload?.displayTitle ?? "Approval request")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let summary = approval.payload?.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let question = approval.payload?.question, !question.isEmpty {
                            Text(question)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let recommendation = approval.payload?.recommendation, !recommendation.isEmpty {
                    Section("Recommendation") {
                        Text(recommendation)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let risks = approval.payload?.risks, !risks.isEmpty {
                    Section("Risks") {
                        ForEach(risks, id: \.self) { risk in
                            Label(risk, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let source = approval.payload?.sourceIssue, !source.isEmpty {
                    Section {
                        if loading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else if let issue {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text(issue.identifier ?? source)
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    StatusBadge(status: issue.status)
                                }
                                if let description = issue.description, !description.isEmpty {
                                    MarkdownView(source: description)
                                } else {
                                    Text("The issue has no description.")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        } else {
                            Text(errorMessage ?? "The issue behind this approval could not be loaded.")
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    } header: {
                        Text(source)
                    }
                } else if let body = approval.payload?.body, !body.isEmpty {
                    Section("Request") {
                        MarkdownView(source: body)
                    }
                }

                if !attachments.isEmpty {
                    Section("Attachments (\(attachments.count))") {
                        ForEach(attachments) { attachment in
                            AttachmentRow(attachment: attachment, auth: session.credentials)
                        }
                    }
                }

                Section {
                    if working {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Button("Reject", role: .destructive) {
                            action = .reject
                            note = ""
                        }
                        Button("Approve") {
                            action = .approve
                            note = ""
                        }
                    }
                } header: {
                    Text("Decision")
                }
            }
            .navigationTitle("Approval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $action) { action in
            ApprovalNoteSheet(action: action, note: $note) { text in
                await decide(action, note: text)
            }
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        let auth = session.credentials
        guard let source = approval.payload?.sourceIssue, !source.isEmpty else {
            loading = false
            return
        }
        do {
            let loaded = try await service.issue(id: source, auth: auth)
            issue = loaded
            attachments = (try? await service.attachments(issueId: loaded.id, auth: auth)) ?? []
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func decide(_ action: ApprovalAction, note: String) async {
        working = true
        defer { working = false }
        do {
            switch action {
            case .approve:
                try await service.approve(id: approval.id,
                                         note: note.isEmpty ? nil : note,
                                         auth: session.credentials)
            case .reject:
                try await service.reject(id: approval.id,
                                         note: note.isEmpty ? nil : note,
                                         auth: session.credentials)
            }
            dismiss()
            await board.refreshApprovals(auth: session.credentials)
            await board.refreshAttention(auth: session.credentials)
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A sheet that collects the note that travels with an approval decision.
struct ApprovalNoteSheet: View {
    let action: ApprovalDetailSheet.ApprovalAction
    @Binding var note: String
    let onConfirm: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationView {
            Form {
                Section("Decision note (optional)") {
                    TextField("Why", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button(action == .approve ? "Approve" : "Reject",
                           role: action == .reject ? .destructive : nil) {
                        working = true
                        Task {
                            await onConfirm(note)
                            working = false
                            dismiss()
                        }
                    }
                    .disabled(working)
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle(action == .approve ? "Approve" : "Reject")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

/// One attachment, with its image shown inline when the board will serve
/// one.
struct AttachmentRow: View {
    let attachment: Attachment
    let auth: Credentials

    @State private var image: UIImage?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: attachment.isImage ? "photo" : "paperclip")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(attachment.displayName)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                if !attachment.sizeLabel.isEmpty {
                    Text(attachment.sizeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if attachment.isImage {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if loading {
                    ProgressView()
                } else if failed {
                    Text("The preview could not be loaded.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .task { await loadImage() }
    }

    private func loadImage() async {
        guard attachment.isImage, image == nil, !failed else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await BoardService().attachmentContent(id: attachment.id, auth: auth)
            guard let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            image = decoded
        } catch {
            failed = true
        }
    }
}
