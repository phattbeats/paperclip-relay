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
        baseURL = UserDefaults.standard.string(forKey: Defaults.baseURL) ?? "https://paperclip.phatt.vip"
        companyId = UserDefaults.standard.string(forKey: Defaults.companyId) ?? ""
        // A board key can also arrive on the launch arguments (the argument
        // domain is visible through UserDefaults). That path exists so an
        // automated run can open the app already signed in — nothing else
        // sets it, and a human always types the key into Settings.
        if let launchToken = UserDefaults.standard.string(forKey: Defaults.boardToken),
           !launchToken.isEmpty,
           Keychain.read(service: service, account: Defaults.boardToken) == nil {
            Keychain.write(launchToken, service: service, account: Defaults.boardToken)
        }
        hasBoardToken = Keychain.read(service: service, account: Defaults.boardToken) != nil
        hasSessionCookie = Keychain.read(service: service, account: Defaults.sessionCookie) != nil
    }

    /// Which tab to open on launch. Used by the screenshot run; a human
    /// always starts on the first tab.
    static var launchTab: String {
        UserDefaults.standard.string(forKey: "relay.initialTab") ?? ""
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
