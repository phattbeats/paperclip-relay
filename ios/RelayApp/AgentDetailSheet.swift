import SwiftUI

/// An agent, opened.
///
/// The roster row said the agent existed. This says what it is running,
/// what it has spent, and lets the user stop it, start it again, or move
/// it onto a different model.
struct AgentDetailSheet: View {
    let agent: Agent

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    @State private var configuration: AgentConfiguration?
    @State private var models: [AdapterModel] = []
    @State private var loading = true
    @State private var working = false
    @State private var errorMessage: String?
    @State private var pickingModel = false

    private let service = BoardService()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                            Text(agent.name)
                                .font(.headline)
                            Spacer()
                            Text(agent.status ?? "unknown")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(statusColor)
                        }
                        if let title = agent.title, !title.isEmpty {
                            Text(title)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let reason = agent.pauseReason, !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Run") {
                    detailRow("Model", currentModel ?? "—")
                    detailRow("Adapter", configuration?.adapterType ?? agent.adapterType ?? "—")
                    detailRow("Status", agent.status ?? "unknown")
                    detailRow("Last heartbeat", Format.relative(agent.lastHeartbeatAt))
                    if let role = agent.role, !role.isEmpty {
                        detailRow("Role", role)
                    }
                }

                Section("Spend") {
                    detailRow("This month", spendLabel)
                    if let budget = agent.budgetMonthlyCents, budget > 0 {
                        detailRow("Budget", money(budget))
                    }
                }

                Section {
                    if working {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if isPaused {
                        Button("Resume") {
                            Task { await resume() }
                        }
                    } else {
                        Button("Pause") {
                            Task { await pause() }
                        }
                    }
                } header: {
                    Text("Control")
                } footer: {
                    Text("Pausing holds the agent without removing it from the board.")
                }

                Section("Model") {
                    Button {
                        pickingModel = true
                    } label: {
                        HStack {
                            Text(currentModel ?? "Choose a model")
                                .foregroundColor(currentModel == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(models.isEmpty || working)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $pickingModel) {
            ModelPickerView(models: models,
                            current: currentModel) { model in
                Task { await setModel(model) }
            }
        }
    }

    private var currentModel: String? {
        configuration?.adapterConfig?.model
    }

    private var isPaused: Bool {
        (agent.status == "paused") || (agent.lifecycleState == "paused")
    }

    private var statusColor: Color {
        switch agent.status {
        case "running": return .green
        case "error": return .red
        case "paused": return .orange
        default: return .secondary
        }
    }

    private var spendLabel: String {
        guard let spent = agent.spentMonthlyCents else { return "—" }
        return money(spent)
    }

    private func money(_ cents: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: cents / 100)) ?? "$\(cents / 100)"
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    // MARK: - Loading

    private func load() async {
        loading = true
        errorMessage = nil
        let auth = session.credentials
        do {
            configuration = try await service.agentConfiguration(id: agent.id, auth: auth)
            if let type = configuration?.adapterType ?? agent.adapterType, !type.isEmpty {
                models = (try? await service.adapterModels(type: type, auth: auth)) ?? []
            }
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func pause() async {
        working = true
        defer { working = false }
        do {
            try await service.pauseAgent(id: agent.id, auth: session.credentials)
            await board.refreshAll(auth: session.credentials)
            await load()
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resume() async {
        working = true
        defer { working = false }
        do {
            try await service.resumeAgent(id: agent.id, auth: session.credentials)
            await board.refreshAll(auth: session.credentials)
            await load()
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setModel(_ model: AdapterModel) async {
        pickingModel = false
        working = true
        defer { working = false }
        do {
            try await service.updateAgentModel(id: agent.id,
                                               model: model.id,
                                               auth: session.credentials)
            await load()
            await board.refreshAll(auth: session.credentials)
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// The list of models an adapter can run an agent on.
struct ModelPickerView: View {
    let models: [AdapterModel]
    let current: String?
    let onSelect: (AdapterModel) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(models) { model in
                Button {
                    onSelect(model)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.label ?? model.id)
                                .foregroundColor(.primary)
                            Text(model.id)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if model.id == current {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
