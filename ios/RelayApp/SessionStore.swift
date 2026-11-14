import Foundation
import Security

/// Where the server URL, company id and credentials live.
///
/// The board token is a bearer credential for a live board, so it goes in
/// the Keychain, never in `UserDefaults` and never in a plist. The
/// non-secret settings ride in `UserDefaults` because they are not
/// sensitive and the user should not re-type the server URL on every launch.
final class SessionStore: ObservableObject {
    private enum Defaults {
        static let baseURL = "relay.baseURL"
        static let companyId = "relay.companyId"
        static let boardToken = "relay.boardToken"
        static let sessionCookie = "relay.sessionCookie"
    }

    private let service = "tech.phatt.papercliprelay"

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Defaults.baseURL) }
    }

    @Published var companyId: String {
        didSet { UserDefaults.standard.set(companyId, forKey: Defaults.companyId) }
    }

    @Published private(set) var hasBoardToken: Bool = false
    @Published private(set) var hasSessionCookie: Bool = false

    init() {
        // Credentials and settings can arrive three ways: the environment
        // (used by the screenshot run), the launch arguments, or what the
        // user saved last time. Environment first because `simctl launch`
        // passes the environment through reliably, while the UserDefaults
        // argument domain cannot carry keys containing a period — which is
        // exactly what the persisted keys use.
        let environment = ProcessInfo.processInfo.environment

        baseURL = environment["RELAY_BASE_URL"]
            ?? launchArgument("relayBaseURL")
            ?? UserDefaults.standard.string(forKey: Defaults.baseURL)
            ?? "https://paperclip.phatt.vip"
        companyId = environment["RELAY_COMPANY_ID"]
            ?? launchArgument("relayCompanyId")
            ?? UserDefaults.standard.string(forKey: Defaults.companyId)
            ?? ""

        if let launchToken = environment["RELAY_BOARD_TOKEN"] ?? launchArgument("relayBoardToken"),
           !launchToken.isEmpty,
           Keychain.read(service: service, account: Defaults.boardToken) == nil {
            Keychain.write(launchToken, service: service, account: Defaults.boardToken)
        }
        hasBoardToken = Keychain.read(service: service, account: Defaults.boardToken) != nil
        hasSessionCookie = Keychain.read(service: service, account: Defaults.sessionCookie) != nil
    }

    /// A launch argument in the argument domain. The key has to be free of
    /// periods; the argument domain silently drops the ones that are not.
    private static func launchArgument(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    /// Which tab to open on launch. Used by the screenshot run; a human
    /// always starts on the first tab.
    static var launchTab: String {
        ProcessInfo.processInfo.environment["RELAY_INITIAL_TAB"]
            ?? UserDefaults.standard.string(forKey: "relayInitialTab")
            ?? ""
    }

    var boardToken: String? {
        Keychain.read(service: service, account: Defaults.boardToken)
    }

    var sessionCookie: String? {
        Keychain.read(service: service, account: Defaults.sessionCookie)
    }

    var credentials: Credentials {
        Credentials(baseURL: baseURL,
                    companyId: companyId,
                    boardToken: boardToken,
                    sessionCookie: sessionCookie)
    }

    func setBoardToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: service, account: Defaults.boardToken)
            hasBoardToken = false
        } else {
            Keychain.write(trimmed, service: service, account: Defaults.boardToken)
            hasBoardToken = true
        }
    }

    func setSessionCookie(_ cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: service, account: Defaults.sessionCookie)
            hasSessionCookie = false
        } else {
            Keychain.write(trimmed, service: service, account: Defaults.sessionCookie)
            hasSessionCookie = true
        }
    }

    func clearCredentials() {
        Keychain.delete(service: service, account: Defaults.boardToken)
        Keychain.delete(service: service, account: Defaults.sessionCookie)
        hasBoardToken = false
        hasSessionCookie = false
    }
}

/// Minimal Keychain wrapper for `kSecClassGenericPassword` items.
enum Keychain {
    static func write(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
