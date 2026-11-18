import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    @State private var companyIdDraft = ""
    @State private var tokenDraft = ""
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var keys: [BoardAPIKey] = []
    @State private var message: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Connection") {
                    TextField("Server URL", text: $session.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Company ID", text: $companyIdDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                    Button("Save") {
                        session.companyId = companyIdDraft
                        message = "Saved"
                    }
                    LabeledRow(label: "Board key", value: session.hasBoardToken ? "stored" : "none")
                    LabeledRow(label: "Session", value: session.hasSessionCookie ? "active" : "none")
                    Button("Reload board") {
                        Task { await board.refreshAll(auth: session.credentials) }
                    }
                }

                Section {
                    SecureField("New board key (pcp_board_…)", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Replace board key") {
                        session.setBoardToken(tokenDraft)
                        tokenDraft = ""
                        message = "Board key saved to the Keychain"
                    }
                    .disabled(tokenDraft.isEmpty)
                    Button("Sign in (email + password)") {
                        Task { await signIn() }
                    }
                    .disabled(email.isEmpty || password.isEmpty || working)
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                    Button("Sign out", role: .destructive) {
                        session.clearCredentials()
                        password = ""
                        message = "Credentials cleared"
                    }
                } header: {
                    Text("Credentials")
                }

                if !keys.isEmpty {
                    Section("Board keys on the server") {
                        ForEach(keys) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.name).font(.subheadline)
                                Text("expires \(Format.absolute(key.expiresAt))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let message {
                    Section {
                        Text(message).font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section("About") {
                    LabeledRow(label: "Version", value: Bundle.main.appVersion)
                    LabeledRow(label: "Target", value: "iOS 16.0+")
                }
            }
            .navigationTitle("Settings")
            .task {
                companyIdDraft = session.companyId
                await loadKeys()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadKeys() async {
        guard session.credentials.isConfigured else { return }
        keys = (try? await BoardService().boardAPIKeys(auth: session.credentials)) ?? []
    }

    private func signIn() async {
        working = true
        defer { working = false }
        do {
            let cookie = try await BoardService().signIn(baseURL: session.baseURL, email: email, password: password)
            session.setSessionCookie(cookie)
            password = ""
            message = "Signed in"
            await board.refreshAll(auth: session.credentials)
        } catch {
            message = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
