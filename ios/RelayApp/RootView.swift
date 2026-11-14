import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    var body: some View {
        Group {
            if session.credentials.isConfigured {
                MainTabs()
            } else {
                SetupView()
            }
        }
        .task {
            guard session.credentials.isConfigured else { return }
            await discoverCompany()
            await board.refreshAll(auth: session.credentials)
        }
    }

    /// Find the company id for this board key, so the user only has to paste
    /// a key and not a UUID.
    private func discoverCompany() async {
        guard session.companyId.isEmpty else { return }
        guard let companies = try? await BoardService().companies(auth: session.credentials),
              !companies.isEmpty else { return }
        let company = companies.first(where: { $0.issuePrefix == "PHA" }) ?? companies[0]
        session.companyId = company.id
    }
}

struct MainTabs: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    @State private var selection: Int = MainTabs.initialTab

    /// Tab order: issues, agents, approvals, settings. A launch argument can
    /// pick the starting tab — that exists for the screenshot run, which
    /// opens the app once per tab.
    private static var initialTab: Int {
        switch SessionStore.launchTab {
        case "agents": return 1
        case "approvals": return 2
        case "settings": return 3
        default: return 0
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            IssuesView()
                .tabItem { Label("Issues", systemImage: "list.bullet.rectangle") }
                .tag(0)

            AgentsView()
                .tabItem { Label("Agents", systemImage: "person.2") }
                .tag(1)

            ApprovalsView()
                .tabItem { Label("Approvals", systemImage: "checkmark.seal") }
                .badge(pendingApprovalCount)
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
    }

    private var pendingApprovalCount: Int {
        board.approvals.filter { $0.status == "pending" }.count
    }
}

// MARK: - Setup

/// First-run screen. Two ways in:
/// - a board API key (`pcp_board_…`), which can be minted with a long
///   expiry and then never touched again;
/// - email + password, which signs in for a 7-day session.
struct SetupView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var companyId = ""
    @State private var token = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Board") {
                    TextField("Server URL", text: $session.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Company ID", text: $companyId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                }

                Section {
                    SecureField("Board API key (pcp_board_…)", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save board key") {
                        session.setBoardToken(token)
                        session.companyId = companyId
                        token = ""
                    }
                    .disabled(token.isEmpty || companyId.isEmpty)
                } header: {
                    Text("Board API key")
                } footer: {
                    Text("Mint one from the board's API keys page. It can be given a multi-year expiry, so the app keeps working without a weekly re-login.")
                }

                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                    Button {
                        Task { await signIn() }
                    } label: {
                        if working {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || working)
                } header: {
                    Text("Or sign in")
                } footer: {
                    Text("Signs in for 7 days, then you sign in again. The board key above lasts longer.")
                }

                if let error {
                    Section {
                        Text(error).foregroundColor(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Paperclip Relay")
        }
    }

    private func signIn() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let service = BoardService()
            let cookie = try await service.signIn(baseURL: session.baseURL, email: email, password: password)
            session.setSessionCookie(cookie)
            session.companyId = companyId
            password = ""
        } catch {
            self.error = (error as? RelayAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
