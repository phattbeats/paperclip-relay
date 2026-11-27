import SwiftUI

/// A run selected from a list or timeline.
struct RunInspectorTarget: Identifiable {
    let runId: String
    let issueIdentifier: String?

    var id: String { runId }
}

/// The run inspector.
///
/// The console could tell you that a run happened, who it belonged to and
/// whether it succeeded. It could not tell you what the agent was doing
/// inside it, what it cost, or why it stalled. That is the question an
/// operator actually asks at 11pm, so this screen exists to answer it.
///
/// It is opened from a run row rather than loaded eagerly, because a single
/// run record is around 300 KB on the wire. Opening one is a deliberate act.
struct RunInspectorView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    let runId: String
    /// The issue this run belongs to, when the operator opened it from an
    /// issue. Used as the sheet's title context.
    var issueIdentifier: String?

    @State private var record: RunRecord?
    @State private var events: [RunEvent] = []
    @State private var log: RunLog?
    @State private var touchedIssues: [RunIssueLink] = []
    @State private var loading = true
    @State private var error: String?
    @State private var tab = RunInspectorTab.detail

    private let service = BoardService()

    enum RunInspectorTab: String, CaseIterable, Identifiable {
        case detail, events, log

        var id: String { rawValue }

        var title: String {
            switch self {
            case .detail: return "Detail"
            case .events: return "Events"
            case .log: return "Log"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loading && record == nil {
                    ProgressView("Reading the run…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Picker("Run", selection: $tab) {
                        ForEach(RunInspectorTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    Group {
                        switch tab {
                        case .detail: detailTab
                        case .events: eventsTab
                        case .log: logTab
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private var title: String {
        issueIdentifier ?? "Run"
    }

    // MARK: - Detail

    private var detailTab: some View {
        List {
            if let record {
                Section("State") {
                    RunStateRow(label: "Status", value: record.status?.replacingOccurrences(of: "_", with: " ") ?? "—")
                    if let phase = record.execution?.label ?? record.execution?.phase {
                        RunStateRow(label: "Phase", value: phase)
                    }
                    if let message = record.currentStatusMessage, !message.isEmpty {
                        RunStateRow(label: "Doing", value: message)
                    }
                    if let tool = record.currentToolName, !tool.isEmpty {
                        RunStateRow(label: "Tool", value: tool)
                    }
                    if let snippet = record.lastAssistantSnippet, !snippet.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last output").font(.caption).foregroundColor(.secondary)
                            Text(snippet)
                                .font(.footnote)
                                .textSelection(.enabled)
                                .lineLimit(12)
                        }
                    }
                    if let liveness = record.livenessState {
                        RunStateRow(label: "Liveness", value: liveness)
                    }
                    if let reason = record.livenessReason, !reason.isEmpty {
                        Text(reason).font(.footnote).foregroundColor(.secondary)
                    }
                }

                if let error = record.error, !error.isEmpty {
                    Section("Failure") {
                        Text(error).font(.footnote).foregroundColor(.red).textSelection(.enabled)
                        if let code = record.errorCode {
                            Text(code).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section("Cost") {
                    RunStateRow(label: "Spend", value: record.costLabel ?? "—")
                    if let usage = record.usageJson {
                        if let tokens = usage.resolvedInputTokens {
                            RunStateRow(label: "Input tokens", value: tokens.formatted())
                        }
                        if let tokens = usage.resolvedOutputTokens {
                            RunStateRow(label: "Output tokens", value: tokens.formatted())
                        }
                        if let cached = usage.resolvedCachedTokens, cached > 0 {
                            RunStateRow(label: "Cached", value: cached.formatted())
                        }
                        if let model = usage.model {
                            RunStateRow(label: "Model", value: model)
                        }
                        if let billing = usage.resolvedBillingType {
                            RunStateRow(label: "Billing", value: billing.replacingOccurrences(of: "_", with: " "))
                        }
                    }
                    if let result = record.resultJson {
                        if let stop = result.stopReason {
                            RunStateRow(label: "Outcome", value: stop)
                        }
                        if result.timeoutFired == true {
                            RunStateRow(label: "Timed out", value: "yes")
                        }
                    }
                }

                Section("Run") {
                    RunStateRow(label: "Agent", value: board.agentById[record.agentId ?? ""]?.name ?? (record.agentId ?? "—"))
                    RunStateRow(label: "Started", value: Format.absolute(record.startedAt))
                    if let finished = record.finishedAt {
                        RunStateRow(label: "Finished", value: Format.absolute(finished))
                    }
                    RunStateRow(label: "Trigger", value: record.invocationSource ?? "—")
                    RunStateRow(label: "Adapter", value: record.adapterType ?? "—")
                    if let bytes = record.logBytes, bytes > 0 {
                        RunStateRow(label: "Log", value: "\(bytes.formatted()) bytes")
                    }
                    if let retry = record.scheduledRetryAt {
                        RunStateRow(label: "Retry at", value: Format.absolute(retry))
                    }
                }

                if !touchedIssues.isEmpty {
                    Section("Issues touched") {
                        ForEach(touchedIssues) { link in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.identifier ?? link.issueId).font(.subheadline.weight(.medium))
                                if let title = link.title {
                                    Text(title).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }

            if let error {
                Section {
                    Text(error).font(.footnote).foregroundColor(.red)
                    Button("Retry") { Task { await load() } }
                }
            }
        }
    }

    // MARK: - Events

    private var eventsTab: some View {
        List {
            if events.isEmpty && !loading {
                Section { Text("This run recorded no events.").font(.footnote).foregroundColor(.secondary) }
            }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(event.eventType ?? "event")
                            .font(.caption.weight(.medium))
                            .foregroundColor(event.level == "error" ? .red : .secondary)
                        Spacer()
                        if let seq = event.seq {
                            Text("#\(seq)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if let message = event.message, !message.isEmpty {
                        Text(message).font(.footnote).textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Log

    private var logTab: some View {
        List {
            let lines = log?.lines ?? []
            if lines.isEmpty {
                Section { Text("No log for this run.").font(.footnote).foregroundColor(.secondary) }
            } else {
                Section {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Last \(lines.count) lines")
                } footer: {
                    Text("The board keeps the run's raw output. Only the most recent bytes are fetched.")
                }
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        loading = true
        error = nil
        let auth = session.credentials
        do {
            // The events and log are fetched alongside the record, but each
            // one owns its own failure: a run whose log has been rotated
            // away is still worth inspecting.
            async let recordLoad = service.run(id: runId, auth: auth)
            async let eventsLoad = service.runEvents(id: runId, auth: auth)
            async let logLoad = service.runLog(id: runId, auth: auth)
            async let issuesLoad = service.runIssues(id: runId, auth: auth)

            record = try await recordLoad
            events = (try? await eventsLoad) ?? []
            log = try? await logLoad
            touchedIssues = (try? await issuesLoad) ?? []
        } catch {
            self.error = OpsFailure.message(error)
        }
        loading = false
    }

}

/// One label/value row in the run detail.
private struct RunStateRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
