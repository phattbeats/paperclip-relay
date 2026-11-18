import SwiftUI

/// The decisions waiting on the board user, shown as cards above the
/// issue list.
///
/// A decision is not an issue. It is a question the board cannot answer
/// for itself, and burying it in a list of rows makes it look like
/// another task. It gets a card of its own, with the answer attached.
struct DecisionCardsView: View {
    let decisions: [Decision]
    let interactions: [PendingInteraction]
    let onResolve: () async -> Void

    @EnvironmentObject private var session: SessionStore

    /// One sheet, not two. SwiftUI only honours the last sheet modifier
    /// attached to a view, so the two possible sheets share one slot.
    private enum Sheet: Identifiable {
        case answering(PendingInteraction)
        case rejecting(PendingInteraction)

        var id: String {
            switch self {
            case .answering(let item): return "answer-\(item.id)"
            case .rejecting(let item): return "reject-\(item.id)"
            }
        }
    }

    @State private var workingID: String?
    @State private var sheet: Sheet?
    @State private var reason = ""

    private let service = BoardService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(decisions) { decision in
                decisionCard(decision)
            }
            ForEach(interactions) { interaction in
                interactionCard(interaction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .sheet(item: $sheet) { item in
            switch item {
            case .answering(let interaction):
                if let issueID = interaction.issueID {
                    InteractionQuestionsSheet(interactionID: interaction.id,
                                              issueID: issueID) {
                        await onResolve()
                    }
                } else {
                    EmptyState(title: "Cannot open",
                               message: "That question is not attached to an issue.")
                }
            case .rejecting(let interaction):
                ReasonSheet(prompt: "Decline with a reason") { text in
                    await reject(interaction, reason: text)
                }
            }
        }
    }

    // MARK: - Decisions

    private func decisionCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Decision")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                Spacer()
                if let created = decision.createdAt {
                    Text(Format.relative(created))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if let title = decision.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let body = decision.body, !body.isEmpty {
                MarkdownView(source: body)
            }
            if let options = decision.options, !options.isEmpty {
                VStack(spacing: 8) {
                    ForEach(options) { option in
                        decisionOption(decision, option)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25)))
    }

    @ViewBuilder
    private func decisionOption(_ decision: Decision, _ option: DecisionOption) -> some View {
        if option.freeText == true {
            VStack(alignment: .leading, spacing: 6) {
                TextField(option.label ?? "Answer", text: binding(for: decision.id, option.id), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button("Send") {
                    Task { await decide(decision, option) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(typedText(for: decision.id, option.id)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workingID != nil)
            }
        } else {
            Button {
                Task { await decide(decision, option) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label ?? option.id)
                            .font(.callout)
                            .foregroundColor(.primary)
                        if let description = option.description, !description.isEmpty {
                            Text(description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer()
                    if workingID == decision.id {
                        ProgressView()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(workingID != nil)
        }
    }

    private func decide(_ decision: Decision, _ option: DecisionOption) async {
        workingID = decision.id
        defer { workingID = nil }
        var inputs: [String: String] = [:]
        if option.freeText == true {
            let answer = typedText(for: decision.id, option.id)
            if !answer.isEmpty { inputs[option.id] = answer }
        }
        do {
            try await service.decide(id: decision.id,
                                     optionId: option.id,
                                     inputValues: inputs,
                                     auth: session.credentials)
            await onResolve()
        } catch {
            // The banner is the app-wide error surface.
            NotificationCenter.default.post(name: .relayBanner, object: BoardStore.message(for: error))
        }
    }

    // MARK: - Interactions

    private func interactionCard(_ interaction: PendingInteraction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Question")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                Spacer()
                if let identifier = interaction.issueIdentifier {
                    Text(identifier)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            if let title = interaction.issueTitle, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let prompt = interaction.title, !prompt.isEmpty {
                Text(prompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(interaction.verbs) { verb in
                    if verb.id == "reject" {
                        Button {
                            Task { await run(verb, interaction) }
                        } label: {
                            Text(verb.label ?? verb.id)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(workingID != nil)
                    } else {
                        Button {
                            Task { await run(verb, interaction) }
                        } label: {
                            Text(verb.label ?? verb.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(workingID != nil)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.25)))
    }

    private func run(_ verb: DecisionVerb, _ interaction: PendingInteraction) async {
        switch verb.id {
        case "respond":
            sheet = .answering(interaction)
        case "accept":
            guard let issueID = interaction.issueID else {
                NotificationCenter.default.post(name: .relayBanner,
                                                object: "That question is not attached to an issue.")
                return
            }
            workingID = interaction.id
            defer { workingID = nil }
            do {
                try await service.acceptInteraction(issueId: issueID,
                                                    interactionId: interaction.id,
                                                    auth: session.credentials)
                await onResolve()
            } catch {
                NotificationCenter.default.post(name: .relayBanner, object: BoardStore.message(for: error))
            }
        case "reject":
            sheet = .rejecting(interaction)
            reason = ""
        default:
            break
        }
    }

    private func reject(_ interaction: PendingInteraction, reason: String) async {
        guard let issueID = interaction.issueID else {
            NotificationCenter.default.post(name: .relayBanner,
                                            object: "That question is not attached to an issue.")
            return
        }
        workingID = interaction.id
        defer { workingID = nil }
        do {
            try await service.rejectInteraction(issueId: issueID,
                                                interactionId: interaction.id,
                                                reason: reason.isEmpty ? nil : reason,
                                                auth: session.credentials)
            await onResolve()
        } catch {
            NotificationCenter.default.post(name: .relayBanner, object: BoardStore.message(for: error))
        }
    }

    // MARK: - Free-text answers

    @State private var typedAnswers: [String: String] = [:]

    private func binding(for decisionID: String, _ optionID: String) -> Binding<String> {
        Binding(
            get: { typedAnswers["\(decisionID):\(optionID)"] ?? "" },
            set: { typedAnswers["\(decisionID):\(optionID)"] = $0 }
        )
    }

    private func typedText(for decisionID: String, _ optionID: String) -> String {
        typedAnswers["\(decisionID):\(optionID)"] ?? ""
    }
}

/// The sheet that answers an agent's questions on an issue thread.
///
/// The interaction carries the questions; the answers go back through
/// `POST /api/issues/{id}/interactions/{interactionId}/respond`, which the
/// board validates against the interaction's own question set.
struct InteractionQuestionsSheet: View {
    let interactionID: String
    let issueID: String
    let onDone: () async -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var interaction: Interaction?
    @State private var loading = true
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var selected: [String: [String]] = [:]
    @State private var typed: [String: String] = [:]
    @State private var custom: [String: String] = [:]
    @State private var summary = ""

    private let service = BoardService()

    var body: some View {
        NavigationView {
            Form {
                if loading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if let interaction {
                    ForEach(interaction.answerableQuestions()) { question in
                        Section {
                            questionBody(question)
                        } header: {
                            Text(question.prompt)
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                    Section("Summary (optional)") {
                        TextField("Summary", text: $summary, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Section {
                        Text(errorMessage ?? "The interaction could not be loaded.")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(sending || interaction == nil || !canSend)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func questionBody(_ question: AnswerableQuestion) -> some View {
        if question.isText {
            TextField("Your answer", text: typedBinding(question.id), axis: .vertical)
                .lineLimit(3...8)
        } else {
            ForEach(question.options) { option in
                Button {
                    toggle(option.id, for: question)
                } label: {
                    HStack {
                        Image(systemName: isSelected(option.id, in: question)
                              ? "checkmark.circle.fill"
                              : "circle")
                            .foregroundColor(isSelected(option.id, in: question) ? Color.accentColor : .secondary)
                        Text(option.label)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            if question.allowsCustomAnswer {
                TextField("Other", text: customBinding(question.id), axis: .vertical)
                    .lineLimit(1...4)
            }
        }
    }

    private var canSend: Bool {
        guard let interaction else { return false }
        for question in interaction.answerableQuestions() {
            if question.isText {
                let text = typed[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if question.isRequired && text.isEmpty { return false }
                continue
            }
            let chosen = selected[question.id] ?? []
            let customText = custom[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if question.isRequired && chosen.isEmpty && customText.isEmpty { return false }
        }
        return true
    }

    private func isSelected(_ optionID: String, in question: AnswerableQuestion) -> Bool {
        (selected[question.id] ?? []).contains(optionID)
    }

    private func toggle(_ optionID: String, for question: AnswerableQuestion) {
        var chosen = selected[question.id] ?? []
        if question.isMultiSelect {
            if let index = chosen.firstIndex(of: optionID) {
                chosen.remove(at: index)
            } else {
                chosen.append(optionID)
            }
        } else {
            chosen = chosen.contains(optionID) ? [] : [optionID]
        }
        selected[question.id] = chosen
        // A single-select answer and a custom answer cannot both be sent.
        if chosen.count == 1 { custom[question.id] = "" }
    }

    private func typedBinding(_ questionID: String) -> Binding<String> {
        Binding(get: { typed[questionID] ?? "" }, set: { typed[questionID] = $0 })
    }

    private func customBinding(_ questionID: String) -> Binding<String> {
        Binding(get: { custom[questionID] ?? "" }, set: { custom[questionID] = $0 })
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            let all = try await service.interactions(issueId: issueID, auth: session.credentials)
            // Only the interaction that was asked for. Falling back to
            // another one on the same issue would put an answer on the
            // board for a question nobody tapped.
            interaction = all.first { $0.id == interactionID }
            if interaction == nil {
                errorMessage = "That question is no longer on the issue."
            }
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func send() async {
        guard let interaction else { return }
        sending = true
        defer { sending = false }
        var answers: [InteractionAnswer] = []
        for question in interaction.answerableQuestions() {
            if question.isText {
                let text = typed[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { continue }
                answers.append(InteractionAnswer(questionID: question.id,
                                                  optionIDs: [],
                                                  otherText: text))
            } else {
                let chosen = selected[question.id] ?? []
                let customText = custom[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !chosen.isEmpty || !customText.isEmpty else { continue }
                answers.append(InteractionAnswer(questionID: question.id,
                                                  optionIDs: chosen,
                                                  otherText: customText.isEmpty ? nil : customText))
            }
        }
        do {
            try await service.respondToInteraction(issueId: issueID,
                                                   interactionId: interaction.id,
                                                   answers: answers,
                                                   summary: summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                       ? nil
                                                       : summary,
                                                   auth: session.credentials)
            dismiss()
            await onDone()
        } catch {
            errorMessage = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A sheet that collects one line of text and hands it back.
struct ReasonSheet: View {
    let prompt: String
    let onSend: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false

    var body: some View {
        NavigationView {
            Form {
                Section(prompt) {
                    TextField("Reason", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Button {
                        working = true
                        Task {
                            await onSend(text)
                            working = false
                            dismiss()
                        }
                    } label: {
                        if working { ProgressView() } else { Text("Send") }
                    }
                    .disabled(working)
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle(prompt)
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

extension Notification.Name {
    /// The app-wide error banner. Views that cannot show an error inline
    /// post here and the root view puts it on screen.
    static let relayBanner = Notification.Name("relay.banner")
}
