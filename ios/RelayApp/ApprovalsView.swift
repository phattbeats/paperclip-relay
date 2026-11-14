import SwiftUI

struct ApprovalsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    @State private var workingID: String?
    @State private var note = ""
    @State private var pending: PendingDecision?

    struct PendingDecision: Identifiable {
        let id = UUID()
        let action: ApprovalAction
        let approvalID: String
    }

    enum ApprovalAction: String {
        case approve, reject
    }

    var body: some View {
        NavigationView {
            Group {
                if board.approvals.isEmpty {
                    EmptyState(title: "Nothing waiting",
                               message: "No approvals are pending on the board.",
                               actionTitle: "Reload") {
                        Task { await board.refreshApprovals(auth: session.credentials) }
                    }
                } else {
                    List {
                        Section {
                            ForEach(board.approvals) { approval in
                                ApprovalCell(approval: approval,
                                             isWorking: workingID == approval.id,
                                             onApprove: { ask(.approve, approval) },
                                             onReject: { ask(.reject, approval) })
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await board.refreshApprovals(auth: session.credentials)
                        await board.refreshAttention(auth: session.credentials)
                    }
                }
            }
            .navigationTitle("Approvals")
        }
        .navigationViewStyle(.stack)
        .sheet(item: $pending) { pending in
            DecisionSheet(action: pending.action, note: $note) { text in
                Task { await decide(pending) }
            }
        }
    }

    private func ask(_ action: ApprovalAction, _ approval: Approval) {
        pending = PendingDecision(action: action, approvalID: approval.id)
        note = ""
    }

    private func decide(_ pending: PendingDecision) async {
        workingID = pending.approvalID
        defer {
            workingID = nil
            self.pending = nil
        }
        do {
            let service = BoardService()
            let decisionNote = note.isEmpty ? nil : note
            switch pending.action {
            case .approve:
                try await service.approve(id: pending.approvalID, note: decisionNote, auth: session.credentials)
            case .reject:
                try await service.reject(id: pending.approvalID, note: decisionNote, auth: session.credentials)
            }
            await board.refreshApprovals(auth: session.credentials)
            await board.refreshAttention(auth: session.credentials)
        } catch {
            board.banner = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ApprovalCell: View {
    let approval: Approval
    let isWorking: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(approval.type.replacingOccurrences(of: "_", with: " "))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(approval.payload?.displayTitle ?? "Approval request")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(Format.relative(approval.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if isWorking {
                    ProgressView()
                } else {
                    Button("Reject", action: onReject)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Approve", action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DecisionSheet: View {
    let action: ApprovalsView.ApprovalAction
    @Binding var note: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Decision note (optional)") {
                    TextField("Why", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button(action == .approve ? "Approve" : "Reject", role: action == .reject ? .destructive : nil) {
                        onConfirm(note)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .navigationTitle(action == .approve ? "Approve" : "Reject")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
