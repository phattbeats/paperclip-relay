import SwiftUI
import Combine
import UIKit

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var board: BoardStore

    /// The board's mark, drawn while the board loads.
    @State private var splashVisible = true

    var body: some View {
        ZStack {
            Group {
                if session.credentials.isConfigured {
                    MainTabs()
                } else {
                    SetupView()
                }
            }

            if splashVisible {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .overlay {
                        PaperclipSplashView()
                            .padding(.bottom, 60)
                    }
                    .transition(.opacity)
                    .zIndex(2)
            }

        }
        .task {
            guard session.credentials.isConfigured else { return }
            await discoverCompany()
            await board.refreshAll(auth: session.credentials)
        }
        .task { await handOffFromSplash() }
        // The banner is drawn by each screen as a safe-area inset, so it has
        // its own space and never covers the navigation bar or the controls
        // underneath it. See RelayBannerView.
        .task {
            // The screenshot run asks for a banner on launch so the capture
            // shows the toast in place. A human never gets one.
            if let banner = SessionStore.launchBanner, board.banner == nil {
                board.banner = banner
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .relayBanner)) { note in
            if let message = note.object as? String {
                board.banner = message
            }
        }
        .animation(.easeOut(duration: 0.25), value: board.banner)
    }

    /// Keep the board hidden for one complete mark cycle.  That guarantees
    /// the launch state begins at the path's first keyframe and visibly hands
    /// off only after the draw/hold/erase sequence has completed; network
    /// speed must not skip the animation.
    private func handOffFromSplash() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            splashVisible = false
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

    @State private var selection: String = MainTabs.initialTab

    /// Which tab to open on launch. A launch argument can pick the
    /// starting tab — that exists for the screenshot run, which opens the
    /// app once per tab. A human always starts on the first tab.
    private static var initialTab: String {
        switch SessionStore.launchTab {
        case "inbox": return "inbox"
        case "agents": return "agents"
        case "approvals": return "approvals"
        case "settings": return "settings"
        default: return "issues"
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            IssuesView()
                .tabItem { Label("Issues", systemImage: "list.bullet.rectangle") }
                .tag("issues")

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(inboxBadge)
                .tag("inbox")

            AgentsView()
                .tabItem { Label("Agents", systemImage: "person.2") }
                .tag("agents")

            ApprovalsView()
                .tabItem { Label("Approvals", systemImage: "checkmark.seal") }
                .badge(pendingApprovalCount)
                .tag("approvals")

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag("settings")
        }
    }

    /// The number of things waiting on the board user, as the board itself
    /// counts them.
    private var inboxBadge: Int {
        board.attention?.deskBadgeCount ?? 0
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

                Section("Board API key") {
                    SecureField("Board API key (pcp_board_…)", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save board key") {
                        session.setBoardToken(token)
                        session.companyId = companyId
                        token = ""
                    }
                    .disabled(token.isEmpty || companyId.isEmpty)
                }

                Section("Or sign in") {
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
