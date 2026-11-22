import SwiftUI

// MARK: - Spend
//
// The board already attributes every dollar to an agent, a project, a
// provider and a rate window. This pane is that attribution, live, on the
// phone — plus the one write that matters: the monthly ceiling.

struct CompanySpendView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    @State private var summary: SpendSummary?
    @State private var byAgent: [SpendByAgent] = []
    @State private var byProject: [SpendByProject] = []
    @State private var byProvider: [SpendByProvider] = []
    @State private var windows: [WindowSpend] = []
    @State private var budgets: BudgetsOverview?
    @State private var error: String?
    @State private var loading = false
    @State private var showBudget = false

    var body: some View {
        List {
            if let summary {
                Section("This month") {
                    HStack(spacing: 12) {
                        OpsMetric(value: OpsFormat.money(summary.spendCents), label: "spend", tint: .purple)
                        OpsMetric(value: OpsFormat.money(summary.budgetCents), label: "budget", tint: .blue)
                        OpsMetric(value: summary.utilizationPercent.map { "\(Int($0))%" } ?? "—", label: "used", tint: .teal)
                    }
                    if summary.pricingComplete == false {
                        Label {
                            Text("Pricing incomplete — \(summary.unpricedEventCount ?? 0) unpriced, \(summary.unknownBillingEventCount ?? 0) unknown-billing events.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        }
                        .font(.footnote)
                    }
                    LabeledContent("Billed events", value: "\(summary.eventCount ?? 0)")
                    LabeledContent("Pending runs", value: "\(summary.pendingRunCount ?? 0)")
                }
            }

            if let policies = budgets?.policies, !policies.isEmpty {
                Section("Budget policies") {
                    ForEach(policies) { policy in
                        BudgetPolicyRow(policy: policy)
                    }
                }
            }

            if !byAgent.isEmpty {
                Section("By agent") {
                    ForEach(byAgent.sorted { ($0.costCents ?? 0) > ($1.costCents ?? 0) }) { row in
                        OpsCostRow(
                            title: row.agentName ?? "Unknown agent",
                            subtitle: [
                                row.agentStatus?.capitalized,
                                row.eventCount.map { "\($0) events" },
                                row.unpricedEventCount.map { $0 > 0 ? "\($0) unpriced" : nil }
                            ].compactMap { $0 }.joined(separator: " · "),
                            costCents: row.costCents,
                            tokens: (row.inputTokens ?? 0) + (row.cachedInputTokens ?? 0) + (row.outputTokens ?? 0)
                        )
                    }
                }
            }

            if !byProject.isEmpty {
                Section("By project") {
                    ForEach(byProject.sorted { ($0.costCents ?? 0) > ($1.costCents ?? 0) }) { row in
                        OpsCostRow(
                            title: row.title,
                            subtitle: row.eventCount.map { "\($0) events" } ?? "",
                            costCents: row.costCents,
                            tokens: (row.inputTokens ?? 0) + (row.cachedInputTokens ?? 0) + (row.outputTokens ?? 0)
                        )
                    }
                }
            }

            if !byProvider.isEmpty {
                Section("By provider and model") {
                    ForEach(byProvider.sorted { ($0.costCents ?? 0) > ($1.costCents ?? 0) }) { row in
                        OpsCostRow(
                            title: row.model ?? row.provider ?? "Unknown",
                            subtitle: [row.provider, row.biller, row.billingType]
                                .compactMap { $0 }
                                .joined(separator: " · "),
                            costCents: row.costCents,
                            tokens: (row.inputTokens ?? 0) + (row.cachedInputTokens ?? 0) + (row.outputTokens ?? 0)
                        )
                    }
                }
            }

            if !windows.isEmpty {
                Section("Rate windows") {
                    ForEach(windows) { row in
                        OpsCostRow(
                            title: "\(row.provider ?? "provider") · \(row.window ?? "window")",
                            subtitle: row.windowHours.map { "\($0)h window" } ?? "",
                            costCents: row.costCents,
                            tokens: (row.inputTokens ?? 0) + (row.cachedInputTokens ?? 0) + (row.outputTokens ?? 0)
                        )
                    }
                }
            }

            Section {
                Button { showBudget = true } label: {
                    Label("Set monthly budget", systemImage: "gauge.with.dots.needle.33percent")
                }
            } footer: {
                Text("The monthly ceiling is company policy. It blocks spending that would pass it.")
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundColor(.red) }
            }
        }
        .overlay {
            if loading && summary == nil {
                ProgressView("Reading the ledger…")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showBudget) {
            MonthlyBudgetView(currentCents: summary?.budgetCents ?? 0) { cents in
                await applyBudget(cents)
            }
        }
    }

    private func load() async {
        guard session.credentials.isConfigured else { return }
        loading = true
        defer { loading = false }
        let auth = session.credentials

        async let summaryResult: Result<SpendSummary, Error> = Self.capture { try await BoardService().spendSummary(auth: auth) }
        async let agentResult: Result<[SpendByAgent], Error> = Self.capture { try await BoardService().spendByAgent(auth: auth) }
        async let projectResult: Result<[SpendByProject], Error> = Self.capture { try await BoardService().spendByProject(auth: auth) }
        async let providerResult: Result<[SpendByProvider], Error> = Self.capture { try await BoardService().spendByProvider(auth: auth) }
        async let windowResult: Result<[WindowSpend], Error> = Self.capture { try await BoardService().spendWindows(auth: auth) }
        async let budgetResult: Result<BudgetsOverview, Error> = Self.capture { try await BoardService().budgets(auth: auth) }

        let loadedSummary = await summaryResult
        let loadedAgents = await agentResult
        let loadedProjects = await projectResult
        let loadedProviders = await providerResult
        let loadedWindows = await windowResult
        let loadedBudgets = await budgetResult

        var failures: [String] = []
        if case .success(let value) = loadedSummary { summary = value }
        if case .failure(let failure) = loadedSummary { failures.append("spend: \(BoardStore.message(for: failure))") }
        if case .success(let value) = loadedAgents { byAgent = value }
        if case .success(let value) = loadedProjects { byProject = value }
        if case .success(let value) = loadedProviders { byProvider = value }
        if case .success(let value) = loadedWindows { windows = value }
        if case .success(let value) = loadedBudgets { budgets = value }

        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private func applyBudget(_ cents: Int) async {
        do {
            try await BoardService().setMonthlyBudget(cents: cents, auth: session.credentials)
            board.bannerIsError = false
            board.banner = "Monthly budget set to \(OpsFormat.money(Double(cents)))."
            await load()
        } catch {
            board.bannerIsError = true
            board.banner = BoardStore.message(for: error)
        }
    }

    /// One endpoint failing must not blank the whole pane, so each call is
    /// captured on its own and the failures are reported together.
    private static func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}

private struct BudgetPolicyRow: View {
    let policy: BudgetsOverview.Policy

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(policy.scopeName ?? "Policy").font(.subheadline).lineLimit(1)
                Spacer()
                Text("\(OpsFormat.money(policy.observedAmount)) / \(OpsFormat.money(policy.amount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let amount = policy.amount, amount > 0 {
                ProgressView(value: min(policy.observedAmount ?? 0, amount), total: amount)
                    .tint((policy.observedAmount ?? 0) >= amount ? .red : .green)
            }
            Text([policy.scopeType?.capitalized, policy.metric, policy.windowKind]
                .compactMap { $0 }
                .joined(separator: " · "))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct OpsCostRow: View {
    let title: String
    let subtitle: String
    let costCents: Double?
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).lineLimit(1)
                Spacer()
                Text(OpsFormat.money(costCents)).font(.subheadline.monospacedDigit())
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            if tokens > 0 {
                Text("\(OpsFormat.compactNumber(tokens)) tokens")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - People

struct CompanyPeopleView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var members: CompanyMembers?
    @State private var error: String?
    @State private var loading = false
    @State private var selectedMember: CompanyMembers.Member?

    var body: some View {
        List {
            if let access = members?.access {
                Section("Your access") {
                    LabeledContent("Your role", value: access.currentUserRole?.capitalized ?? "—")
                    LabeledContent("Can manage members", value: access.canManageMembers == true ? "Yes" : "No")
                    LabeledContent("Can invite users", value: access.canInviteUsers == true ? "Yes" : "No")
                    LabeledContent("Join requests", value: access.canApproveJoinRequests == true ? "Can approve" : "No")
                }
            }

            if let list = members?.members, !list.isEmpty {
                Section("Members") {
                    ForEach(list) { member in
                        Button { selectedMember = member } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(member.user?.name ?? member.user?.email ?? "Member")
                                        .foregroundColor(.primary)
                                    Text([
                                        member.user?.email,
                                        member.membershipRole?.capitalized,
                                        member.status?.capitalized
                                    ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let grants = member.grants, !grants.isEmpty {
                                    Text("\(grants.count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                }
                                Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundColor(.red) }
            }
        }
        .overlay {
            if loading && members == nil {
                ProgressView("Reading the roster…")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $selectedMember) { member in
            MemberDetailView(member: member, onChanged: { Task { await load() } })
        }
    }

    private func load() async {
        guard session.credentials.isConfigured else { return }
        loading = true
        defer { loading = false }
        do {
            members = try await BoardService().members(auth: session.credentials)
            error = nil
        } catch let loadError {
            error = BoardStore.message(for: loadError)
        }
    }
}

private struct MemberDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    let member: CompanyMembers.Member
    let onChanged: () -> Void

    @State private var working = false
    @State private var showRolePicker = false

    private let roles = ["owner", "admin", "operator", "viewer"]

    var body: some View {
        NavigationView {
            List {
                Section("Person") {
                    LabeledContent("Name", value: member.user?.name ?? "—")
                    LabeledContent("Email", value: member.user?.email ?? "—")
                    LabeledContent("Type", value: member.principalType?.capitalized ?? "—")
                    LabeledContent("Status", value: member.status?.capitalized ?? "—")
                    if let created = member.createdAt {
                        LabeledContent("Member since", value: Format.absolute(created))
                    }
                }

                Section("Role") {
                    LabeledContent("Current role", value: member.membershipRole?.capitalized ?? "Unknown")
                    Button("Change role…") { showRolePicker = true }
                        .disabled(working)
                }

                if let grants = member.grants, !grants.isEmpty {
                    Section {
                        ForEach(grants) { grant in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(grant.permissionKey ?? "permission")
                                    .font(.subheadline)
                                if let created = grant.createdAt {
                                    Text("granted \(Format.relative(created))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Permissions")
                    } footer: {
                        Text("Permission keys are granted by the board. The phone reads them; it does not hand them out.")
                    }
                }
            }
            .navigationTitle(member.user?.name ?? "Member")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Change role", isPresented: $showRolePicker, titleVisibility: .visible) {
                ForEach(roles, id: \.self) { role in
                    Button(role.capitalized) { Task { await changeRole(to: role) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(member.user?.name ?? "This member") is currently \(member.membershipRole ?? "unset"). This changes what they can do on the board right now.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func changeRole(to role: String) async {
        working = true
        defer { working = false }
        do {
            try await BoardService().updateMemberRole(memberId: member.id, role: role, auth: session.credentials)
            board.bannerIsError = false
            board.banner = "Role set to \(role)."
            onChanged()
            dismiss()
        } catch {
            board.bannerIsError = true
            board.banner = BoardStore.message(for: error)
        }
    }
}

// MARK: - Timeline

struct CompanyTimelineView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var timeline: CompanyTimeline?
    @State private var mode = "runs"
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            Section {
                Picker("Timeline", selection: $mode) {
                    Text("Runs").tag("runs")
                    Text("Events").tag("events")
                }
                .pickerStyle(.segmented)
            }

            if mode == "runs" {
                let spans = (timeline?.spans ?? []).sorted { ($0.start ?? "") > ($1.start ?? "") }
                if spans.isEmpty && !loading {
                    Section { Text("No runs in this window.").font(.footnote).foregroundColor(.secondary) }
                }
                ForEach(spans.prefix(80)) { span in
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if let identifier = span.issueIdentifier {
                                    Text(identifier)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.blue)
                                }
                                if let status = span.status {
                                    Text(status.capitalized)
                                        .font(.caption2)
                                        .foregroundColor(OpsStatus.tint(status))
                                }
                                Spacer()
                                Text(OpsFormat.duration(start: span.start, end: span.end))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            if let title = span.issueTitle {
                                Text(title).font(.subheadline).lineLimit(2)
                            }
                            HStack(spacing: 6) {
                                Text(actorName(span.actorId))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let source = span.invocationSource {
                                    Text(source).font(.caption2).foregroundColor(.secondary)
                                }
                                if let attempt = span.continuationAttempt, attempt > 0 {
                                    Text("attempt \(attempt + 1)").font(.caption2).foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                let events = (timeline?.events ?? []).sorted { ($0.at ?? "") > ($1.at ?? "") }
                if events.isEmpty && !loading {
                    Section { Text("No events in this window.").font(.footnote).foregroundColor(.secondary) }
                }
                ForEach(events.prefix(120)) { event in
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.kind?.capitalized ?? "Event")
                                    .font(.subheadline)
                                Text(actorName(event.actorId))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(Format.relative(event.at))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if let pagination = timeline?.pagination {
                Section {
                    LabeledContent("Issues in window", value: "\(pagination.totalIssues ?? 0)")
                    if pagination.hasMore == true {
                        Text("More history exists beyond this window.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundColor(.red) }
            }
        }
        .overlay {
            if loading && timeline == nil {
                ProgressView("Reading the timeline…")
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func actorName(_ id: String?) -> String {
        guard let id else { return "Board" }
        if let actor = (timeline?.actors ?? []).first(where: { $0.id == id }) {
            return actor.name ?? actor.type ?? "Board"
        }
        return id
    }

    private func load() async {
        guard session.credentials.isConfigured else { return }
        loading = true
        defer { loading = false }
        do {
            timeline = try await BoardService().timeline(auth: session.credentials)
            error = nil
        } catch let loadError {
            error = BoardStore.message(for: loadError)
        }
    }
}

// MARK: - Health

struct CompanyHealthView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var dashboard: CompanyDashboard?
    @State private var observability: ObservabilityStatus?
    @State private var quota: [QuotaReport] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if let dashboard {
                Section("Agents") {
                    HStack(spacing: 12) {
                        OpsMetric(value: "\(dashboard.agents.active)", label: "active", tint: .green)
                        OpsMetric(value: "\(dashboard.agents.running)", label: "running", tint: .blue)
                        OpsMetric(value: "\(dashboard.agents.paused)", label: "paused", tint: .orange)
                        OpsMetric(value: "\(dashboard.agents.error)", label: "errors", tint: dashboard.agents.error > 0 ? .red : .secondary)
                    }
                }

                Section("Work") {
                    HStack(spacing: 12) {
                        OpsMetric(value: "\(dashboard.tasks.open)", label: "open", tint: .blue)
                        OpsMetric(value: "\(dashboard.tasks.inProgress)", label: "active", tint: .green)
                        OpsMetric(value: "\(dashboard.tasks.blocked)", label: "blocked", tint: dashboard.tasks.blocked > 0 ? .orange : .secondary)
                    }
                }

                Section("Runs per day") {
                    RunActivityBars(days: Array(dashboard.runActivity.suffix(14)))
                    if let latest = dashboard.runActivity.last {
                        LabeledContent("Latest day") {
                            Text("\(latest.succeeded) succeeded · \(latest.failed) failed")
                                .foregroundColor(latest.failed > 0 ? .orange : .secondary)
                        }
                    }
                    if let latest = dashboard.runActivity.last, let codes = latest.failedByErrorCode, !codes.isEmpty {
                        ForEach(codes.sorted(by: { $0.key < $1.key }), id: \.key) { code, count in
                            LabeledContent(code, value: "\(count)")
                                .font(.footnote)
                        }
                    }
                }

                Section("Budget guards") {
                    LabeledContent("Active incidents", value: "\(dashboard.budgets?.activeIncidents ?? 0)")
                    LabeledContent("Paused agents", value: "\(dashboard.budgets?.pausedAgents ?? 0)")
                    LabeledContent("Paused projects", value: "\(dashboard.budgets?.pausedProjects ?? 0)")
                    LabeledContent("Pending approvals", value: "\(dashboard.budgets?.pendingApprovals ?? 0)")
                }
            }

            Section("Observability") {
                LabeledContent("Configured", value: observability?.configured == true ? "Yes" : "No")
                LabeledContent("Enabled", value: observability?.enabled == true ? "Yes" : "No")
                LabeledContent("Provider", value: observability?.provider?.capitalized ?? "—")
                if let test = observability?.lastTest {
                    LabeledContent("Last test", value: test.status?.capitalized ?? "—")
                }
            }

            if !quota.isEmpty {
                Section {
                    ForEach(quota) { report in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(report.accountLabel ?? report.provider ?? "Account")
                                    .font(.subheadline)
                                Spacer()
                                if report.ok == false {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                            ForEach(report.windows ?? []) { window in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(window.label ?? "Window").font(.caption)
                                        Spacer()
                                        if let percent = window.usedPercent {
                                            Text("\(Int(percent))%").font(.caption2.monospacedDigit())
                                        } else if let value = window.valueLabel {
                                            Text(value).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    if let percent = window.usedPercent {
                                        ProgressView(value: min(percent, 100), total: 100)
                                            .tint(percent >= 90 ? .red : (percent >= 70 ? .orange : .green))
                                    }
                                    if let resets = window.resetsAt {
                                        Text("resets \(Format.relative(resets))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Subscription limits")
                } footer: {
                    Text("Quota windows come from the provider accounts the board is connected to.")
                }
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundColor(.red) }
            }
        }
        .overlay {
            if loading && dashboard == nil {
                ProgressView("Reading health…")
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard session.credentials.isConfigured else { return }
        loading = true
        defer { loading = false }
        let auth = session.credentials

        async let dashboardResult: Result<CompanyDashboard, Error> = Self.capture { try await BoardService().dashboard(auth: auth) }
        async let observabilityResult: Result<ObservabilityStatus, Error> = Self.capture { try await BoardService().observability(auth: auth) }
        async let quotaResult: Result<[QuotaReport], Error> = Self.capture { try await BoardService().quotaWindows(auth: auth) }

        let loadedDashboard = await dashboardResult
        let loadedObservability = await observabilityResult
        let loadedQuota = await quotaResult

        var failures: [String] = []
        if case .success(let value) = loadedDashboard { dashboard = value }
        if case .failure(let failure) = loadedDashboard { failures.append("dashboard: \(BoardStore.message(for: failure))") }
        if case .success(let value) = loadedObservability { observability = value }
        if case .success(let value) = loadedQuota { quota = value }

        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private static func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Budget editor

private struct MonthlyBudgetView: View {
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    let currentCents: Double?
    let onSave: (Int) async -> Void

    @State private var dollars = ""
    @State private var working = false
    @State private var confirm = false

    var body: some View {
        NavigationView {
            Form {
                Section("Monthly ceiling") {
                    TextField("0", text: $dollars)
                        .keyboardType(.decimalPad)
                    if let current = currentCents, current > 0 {
                        LabeledContent("Current", value: OpsFormat.money(current))
                    }
                }
                Section {
                    Button(working ? "Saving…" : "Save ceiling") { confirm = true }
                        .disabled(working || parsedCents == nil)
                } footer: {
                    Text("This is company spend policy. It takes effect on the board immediately and can stop work that would exceed it.")
                }
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
            }
            .alert("Set the monthly ceiling?", isPresented: $confirm) {
                Button("Set ceiling") { Task { await save() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The company will refuse spending past this amount until the month rolls over.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var parsedCents: Int? {
        let cleaned = dollars.trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private func save() async {
        guard let cents = parsedCents else { return }
        working = true
        defer { working = false }
        await onSave(cents)
        dismiss()
    }
}

// MARK: - Shared pieces

struct OpsMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RunActivityBars: View {
    let days: [CompanyDashboard.RunActivity]

    var body: some View {
        let peak = max(days.map { $0.total }.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(days) { day in
                HStack(alignment: .bottom, spacing: 1) {
                    Rectangle()
                        .fill(Color.green.opacity(0.65))
                        .frame(width: 4, height: bar(day.succeeded, peak: peak))
                    Rectangle()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: 4, height: bar(day.failed, peak: peak))
                }
            }
        }
        .frame(height: 56, alignment: .bottom)
        .padding(.vertical, 2)
    }

    private func bar(_ value: Int, peak: Int) -> CGFloat {
        guard value > 0 else { return 1 }
        return max(2, CGFloat(value) / CGFloat(peak) * 52)
    }
}

enum OpsStatus {
    static func tint(_ status: String) -> Color {
        switch status.lowercased() {
        case "succeeded", "completed", "success": return .green
        case "failed", "error": return .red
        case "cancelled", "canceled": return .secondary
        case "running", "in_progress": return .blue
        case "queued", "pending": return .orange
        default: return .secondary
        }
    }
}
