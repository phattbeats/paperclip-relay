import SwiftUI

/// The Approvals tab: what the board is waiting for the user to sign.
///
/// Tapping an approval opens its detail, which carries the body of the
/// issue behind it and whatever is attached to that issue — an approval
/// that says only "please approve" is not enough to approve from.
struct ApprovalsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    /// One sheet, not two: SwiftUI only honours the last sheet modifier
    /// attached to a view.
    private enum Sheet: Identifiable {
        case detail(Approval)
        case note(Approval, ApprovalDetailSheet.ApprovalAction)

        var id: String {
            switch self {
            case .detail(let item): return "detail-\(item.id)"
            case .note(let item, let action): return "note-\(item.id)-\(action.rawValue)"
            }
        }
    }

    @State private var workingID: String?
    @State private var sheet: Sheet?
    @State private var note = ""

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
                        ForEach(board.approvals) { approval in
                            ApprovalCell(approval: approval,
                                         isWorking: workingID == approval.id,
                                         onOpen: { sheet = .detail(approval) },
                                         onApprove: { ask(.approve, approval) },
                                         onReject: { ask(.reject, approval) })
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
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .detail(let approval):
                ApprovalDetailSheet(approval: approval)
            case .note(let approval, let action):
                ApprovalNoteSheet(action: action, note: $note) { text in
                    await decide(approval, action: action, note: text)
                }
            }
        }
    }

    private func ask(_ action: ApprovalDetailSheet.ApprovalAction, _ approval: Approval) {
        sheet = .note(approval, action)
        note = ""
    }

    private func decide(_ approval: Approval,
                        action: ApprovalDetailSheet.ApprovalAction,
                        note: String) async {
        workingID = approval.id
        defer { workingID = nil }
        do {
            let service = BoardService()
            let decisionNote = note.isEmpty ? nil : note
            switch action {
            case .approve:
                try await service.approve(id: approval.id, note: decisionNote, auth: session.credentials)
            case .reject:
                try await service.reject(id: approval.id, note: decisionNote, auth: session.credentials)
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
    let onOpen: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(approval.type.replacingOccurrences(of: "_", with: " "))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(approval.payload?.displayTitle ?? "Approval request")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(Format.relative(approval.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let source = approval.payload?.sourceIssue, !source.isEmpty {
                            Text(source)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Details")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack {
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
