import SwiftUI
import Foundation

// MARK: - Operator actions
//
// Reading a board from the phone is half of it. The other half is moving
// work: who owns it, what it is tagged with, which project it lands in,
// and whether an agent should pick it up now. These sheets write through
// the board's own issue endpoints and then re-read the issue, so the phone
// shows what the board accepted rather than what the phone hoped for.

// MARK: Assignee

struct IssueAssigneeSheet: View {
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    let currentAgentId: String?
    let onSelect: (String?) async -> Void

    @State private var working = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        Task { await apply(nil) }
                    } label: {
                        AssigneeRow(name: "Unassigned", isCurrent: currentAgentId == nil)
                    }
                    .disabled(working)
                }

                Section("Agents") {
                    ForEach(board.agents) { agent in
                        Button {
                            Task { await apply(agent.id) }
                        } label: {
                            AssigneeRow(name: agent.name, isCurrent: agent.id == currentAgentId)
                        }
                        .disabled(working)
                    }
                }
            }
            .navigationTitle("Assignee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func apply(_ agentId: String?) async {
        working = true
        defer { working = false }
        await onSelect(agentId)
        dismiss()
    }
}

private struct AssigneeRow: View {
    let name: String
    let isCurrent: Bool

    var body: some View {
        HStack {
            Text(name).foregroundColor(.primary)
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark").foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: Labels

struct IssueLabelsSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let currentLabelIds: [String]
    let onSave: ([String]) async -> Void

    @State private var labels: [CompanyLabel] = []
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            List {
                if loading {
                    Section { ProgressView("Reading labels…") }
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundColor(.red) }
                }
                Section("Company labels") {
                    ForEach(labels) { label in
                        Button {
                            toggle(label.id)
                        } label: {
                            LabelRow(title: label.name ?? "label", color: label.color, isSelected: selected.contains(label.id))
                        }
                        .disabled(saving)
                    }
                    if labels.isEmpty && !loading {
                        Text("This company has no labels yet.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            labels = try await BoardService().companyLabels(auth: session.credentials)
            selected = Set(currentLabelIds)
            error = nil
        } catch let loadError {
            error = OpsFailure.message(loadError)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        await onSave(Array(selected))
        dismiss()
    }
}

private struct LabelRow: View {
    let title: String
    let color: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: color ?? "#888888"))
                .frame(width: 10, height: 10)
            Text(title).foregroundColor(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: Project

struct IssueProjectSheet: View {
    @EnvironmentObject private var board: BoardStore
    @Environment(\.dismiss) private var dismiss

    let currentProjectId: String?
    let onSelect: (String?) async -> Void

    @State private var working = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        Task { await apply(nil) }
                    } label: {
                        AssigneeRow(name: "No project", isCurrent: currentProjectId == nil)
                    }
                    .disabled(working)
                }

                Section("Projects") {
                    ForEach(board.projects) { project in
                        Button {
                            Task { await apply(project.id) }
                        } label: {
                            AssigneeRow(name: project.name, isCurrent: project.id == currentProjectId)
                        }
                        .disabled(working)
                    }
                }
            }
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func apply(_ projectId: String?) async {
        working = true
        defer { working = false }
        await onSelect(projectId)
        dismiss()
    }
}

// MARK: Shared colour helper

extension Color {
    /// The board stores label colours as `#RRGGBB`.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
