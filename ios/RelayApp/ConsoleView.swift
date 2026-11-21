import SwiftUI

/// The phone's company cockpit. It deliberately answers the operator's
/// questions (health, spend, work, automations) instead of cloning every
/// editor from the web app.
struct ConsoleView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    @State private var dashboard: CompanyDashboard?
    @State private var goals: [CompanyGoal] = []
    @State private var routines: [CompanyRoutine] = []
    @State private var activity: [CompanyActivity] = []
    @State private var organization: [CompanyOrgNode] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showSearch = false
    @State private var showNewIssue = false
    @State private var showSettings = false
    @State private var selectedRoutine: CompanyRoutine?

    var body: some View {
        NavigationView {
            Group {
                if loading && dashboard == nil {
                    ProgressView("Loading company pulse…")
                } else {
                    List {
                        if let dashboard {
                            Section("Company pulse") {
                                HStack(spacing: 12) {
                                    ConsoleMetric(value: "\(dashboard.agents.running)", label: "running", tint: .green)
                                    ConsoleMetric(value: "\(dashboard.agents.error)", label: "errors", tint: dashboard.agents.error > 0 ? .red : .secondary)
                                    ConsoleMetric(value: "\(dashboard.tasks.blocked)", label: "blocked", tint: dashboard.tasks.blocked > 0 ? .orange : .secondary)
                                }
                                HStack(spacing: 12) {
                                    ConsoleMetric(value: "\(dashboard.tasks.open)", label: "open", tint: .blue)
                                    ConsoleMetric(value: currency(dashboard.costs.monthSpendCents), label: "month spend", tint: .purple)
                                    ConsoleMetric(value: "\(dashboard.pendingApprovals)", label: "approvals", tint: .teal)
                                }

                                if let latest = dashboard.runActivity.last {
                                    LabeledContent("Latest runs") {
                                        Text("\(latest.succeeded) succeeded · \(latest.failed) failed")
                                            .foregroundColor(latest.failed > 0 ? .orange : .secondary)
                                    }
                                }
                            }
                        }

                        if !goals.isEmpty {
                            Section("Active goals") {
                                ForEach(goals.filter { $0.status != "done" }.prefix(4)) { goal in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(goal.title).font(.subheadline).lineLimit(2)
                                        Text(goal.status?.capitalized ?? "Active")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }

                        if !organization.isEmpty {
                            Section("Organization") {
                                ForEach(organization) { node in
                                    OrgNodeRow(node: node, depth: 0)
                                }
                            }
                        }

                        if !routines.isEmpty {
                            Section {
                                ForEach(routines.filter { $0.status != "archived" }.prefix(5)) { routine in
                                    Button { selectedRoutine = routine } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(routine.title).foregroundColor(.primary).lineLimit(1)
                                                Text(routine.status?.capitalized ?? "Active")
                                                    .font(.caption).foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("Routines")
                                    Spacer()
                                    Text("Automations").textCase(nil).font(.caption).foregroundColor(.secondary)
                                }
                            } footer: {
                                Text("Manual runs require confirmation. Scheduling controls are reversible.")
                            }
                        }

                        if !activity.isEmpty {
                            Section("Recent activity") {
                                ForEach(activity.prefix(5)) { event in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(activityTitle(event)).font(.subheadline)
                                        Text(Format.relative(event.createdAt))
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }

                        if let error {
                            Section {
                                Text(error).font(.footnote).foregroundColor(.red)
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Company")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search company")
                    Button { showNewIssue = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New issue")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .task { await load() }
            .sheet(isPresented: $showSearch) { CompanySearchView() }
            .sheet(isPresented: $showNewIssue) { NewCompanyIssueView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $selectedRoutine) { routine in
                RoutineDetailView(routine: routine, onChanged: { Task { await load() } })
            }
            .relayBannerInset()
        }
        .navigationViewStyle(.stack)
    }

    private func load() async {
        guard session.credentials.isConfigured else { return }
        loading = true
        defer { loading = false }
        do {
            async let dashboardLoad = BoardService().dashboard(auth: session.credentials)
            async let goalsLoad = BoardService().goals(auth: session.credentials)
            async let routinesLoad = BoardService().routines(auth: session.credentials)
            async let activityLoad = BoardService().activity(auth: session.credentials)
            async let organizationLoad = BoardService().organization(auth: session.credentials)
            (dashboard, goals, routines, activity, organization) = try await (dashboardLoad, goalsLoad, routinesLoad, activityLoad, organizationLoad)
            error = nil
        } catch let loadError {
            error = BoardStore.message(for: loadError)
        }
    }

    private func currency(_ cents: Double?) -> String {
        guard let cents else { return "—" }
        return (cents / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func activityTitle(_ event: CompanyActivity) -> String {
        let actor = event.actorName ?? event.actorType ?? "Board"
        let action = event.action?.replacingOccurrences(of: ".", with: " ") ?? "updated work"
        return "\(actor) · \(action)"
    }
}

private struct OrgNodeRow: View {
    let node: CompanyOrgNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: node.status == "running" ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundColor(node.status == "running" ? .green : .secondary)
                Text(node.name)
                Spacer()
                Text(node.role?.capitalized ?? "Agent")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.leading, CGFloat(depth) * 16)
            ForEach(node.reports) { child in
                OrgNodeRow(node: child, depth: depth + 1)
            }
        }
    }
}

private struct ConsoleMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundColor(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RoutineDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    let routine: CompanyRoutine
    let onChanged: () -> Void
    @State private var confirmRun = false
    @State private var working = false

    var body: some View {
        NavigationView {
            List {
                Section("Routine") {
                    Text(routine.title)
                    LabeledContent("Status", value: routine.status?.capitalized ?? "Unknown")
                    if let last = routine.lastTriggeredAt {
                        LabeledContent("Last triggered", value: Format.relative(last))
                    }
                }
                Section("Schedule") {
                    ForEach(routine.triggers ?? []) { trigger in
                        Toggle(isOn: Binding(
                            get: { trigger.enabled },
                            set: { enabled in Task { await setTrigger(trigger, enabled: enabled) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trigger.label ?? trigger.kind)
                                Text(trigger.cronExpression ?? trigger.kind)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .disabled(working)
                    }
                }
                Section {
                    Button("Run now", role: .destructive) { confirmRun = true }
                        .disabled(working)
                } footer: {
                    Text("This can create work and spend tokens. It always asks before running.")
                }
            }
            .navigationTitle("Routine")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Run \(routine.title)?", isPresented: $confirmRun) {
                Button("Run routine", role: .destructive) { Task { await run() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This creates real work and may spend model tokens.") }
        }
        .navigationViewStyle(.stack)
    }

    private func run() async {
        working = true
        defer { working = false }
        do {
            try await BoardService().runRoutine(id: routine.id, auth: session.credentials)
            board.bannerIsError = false
            board.banner = "Routine started."
            onChanged()
            dismiss()
        } catch {
            board.bannerIsError = true
            board.banner = BoardStore.message(for: error)
        }
    }

    private func setTrigger(_ trigger: CompanyRoutine.Trigger, enabled: Bool) async {
        working = true
        defer { working = false }
        do {
            try await BoardService().setRoutineTrigger(id: trigger.id, enabled: enabled, auth: session.credentials)
            board.bannerIsError = false
            board.banner = enabled ? "Routine schedule enabled." : "Routine schedule paused."
            onChanged()
        } catch {
            board.bannerIsError = true
            board.banner = BoardStore.message(for: error)
        }
    }
}

private struct CompanySearchView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CompanySearchResponse.Result] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            List {
                if searching { ProgressView("Searching…") }
                if let error { Text(error).foregroundColor(.red).font(.footnote) }
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title ?? result.type.capitalized).font(.headline)
                        if let snippet = result.snippet { Text(snippet).font(.subheadline).foregroundColor(.secondary).lineLimit(3) }
                        Text(result.type.capitalized).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Search company")
            .searchable(text: $query, prompt: "Issues, comments, documents")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; return }
        searching = true
        defer { searching = false }
        do {
            results = try await BoardService().search(auth: session.credentials, query: text).results
            error = nil
        } catch let searchError { error = BoardStore.message(for: searchError) }
    }
}

private struct NewCompanyIssueView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var priority = "medium"
    @State private var assignee = ""
    @State private var working = false

    var body: some View {
        NavigationView {
            Form {
                Section("Work") {
                    TextField("Title", text: $title)
                    TextEditor(text: $description).frame(minHeight: 120)
                }
                Section("Routing") {
                    Picker("Priority", selection: $priority) {
                        ForEach(["low", "medium", "high", "critical"], id: \.self) { Text($0.capitalized) }
                    }
                    Picker("Assignee", selection: $assignee) {
                        Text("Unassigned").tag("")
                        ForEach(board.agents) { agent in Text(agent.name).tag(agent.id) }
                    }
                }
            }
            .navigationTitle("New issue")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(working ? "Saving…" : "Create") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func create() async {
        working = true
        defer { working = false }
        do {
            let issue = try await BoardService().createIssue(title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: description, priority: priority, assigneeAgentId: assignee.isEmpty ? nil : assignee, auth: session.credentials)
            board.bannerIsError = false
            board.banner = "Created \(issue.identifier ?? "issue")."
            dismiss()
        } catch {
            board.bannerIsError = true
            board.banner = BoardStore.message(for: error)
        }
    }
}
