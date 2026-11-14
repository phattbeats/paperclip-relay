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

    /// Fallback for a device where the Keychain refuses the write — an
    /// unsigned simulator build has no keychain entitlement, and the board
    /// key is then held in memory for the life of the process instead of
    /// being persisted. On a signed device build the Keychain works and
    /// this stays nil.
    private var inMemoryBoardToken: String?
    private var keychainWriteStatus: OSStatus = errSecSuccess

    init() {
        // Credentials and settings can arrive three ways: the environment
        // (used by the screenshot run), the launch arguments, or what the
        // user saved last time. Environment first because `simctl launch`
        // passes the environment through reliably, while the UserDefaults
        // argument domain cannot carry keys containing a period — which is
        // exactly what the persisted keys use.
        let environment = ProcessInfo.processInfo.environment

        baseURL = environment["RELAY_BASE_URL"]
            ?? Self.launchArgument("relayBaseURL")
            ?? UserDefaults.standard.string(forKey: Defaults.baseURL)
            ?? "https://paperclip.phatt.vip"
        companyId = environment["RELAY_COMPANY_ID"]
            ?? Self.launchArgument("relayCompanyId")
            ?? UserDefaults.standard.string(forKey: Defaults.companyId)
            ?? ""

        // A bootstrap file in the app's Documents directory is the third way
        // in. It exists for the screenshot run in CI, which cannot type into
        // the app and cannot rely on the argument domain either. A human
        // never uses it: the file is not created by the app.
        let bootstrap = Self.bootstrapConfig()

        if let launchToken = environment["RELAY_BOARD_TOKEN"]
            ?? Self.launchArgument("relayBoardToken")
            ?? bootstrap?["boardToken"],
           !launchToken.isEmpty,
           Keychain.read(service: service, account: Defaults.boardToken) == nil {
            let status = Keychain.write(launchToken, service: service, account: Defaults.boardToken)
            keychainWriteStatus = status
            if status != errSecSuccess {
                inMemoryBoardToken = launchToken
            }
        }
        if let base = bootstrap?["baseURL"], !base.isEmpty { baseURL = base }
        if let company = bootstrap?["companyId"], !company.isEmpty { companyId = company }
        hasBoardToken = boardToken != nil
        hasSessionCookie = Keychain.read(service: service, account: Defaults.sessionCookie) != nil

        writeLaunchDiagnostic()
    }

    /// Drop a small diagnostic file in Documents so an automated run can see
    /// what the app actually found at launch: whether the key landed in the
    /// Keychain, what the environment carried, and which tab was selected.
    private func writeLaunchDiagnostic() {
        let environment = ProcessInfo.processInfo.environment
        let diagnostic: [String: Any] = [
            "baseURL": baseURL,
            "companyId": companyId,
            "hasBoardToken": hasBoardToken,
            "hasSessionCookie": hasSessionCookie,
            "initialTab": SessionStore.launchTab,
            "environmentKeys": environment.keys.filter { $0.hasPrefix("RELAY_") }.sorted(),
            "environmentHasToken": environment["RELAY_BOARD_TOKEN"] != nil,
            "keychainWriteStatus": Int(keychainWriteStatus),
            "keychainWriteOK": keychainWriteStatus == errSecSuccess,
            "tokenHeldInMemory": inMemoryBoardToken != nil,
            "bootstrapFileFound": SessionStore.bootstrapConfig() != nil,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted]),
              let documents = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: documents.appendingPathComponent("relay-launch.json"))
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
            ?? Self.bootstrapConfig()?["initialTab"]
            ?? ""
    }

    /// Read `relay-config.json` from the app's Documents directory.
    ///
    /// Keys: `baseURL`, `companyId`, `boardToken`, `initialTab`. It is a
    /// bootstrap path for automated runs, not a settings store — the app
    /// never writes it, and a real install never has it.
    private static func bootstrapConfig() -> [String: String]? {
        guard let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let path = documents.appendingPathComponent("relay-config.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var config: [String: String] = [:]
        for (key, value) in object {
            if let text = value as? String { config[key] = text }
        }
        return config
    }

    var boardToken: String? {
        Keychain.read(service: service, account: Defaults.boardToken) ?? inMemoryBoardToken
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
            inMemoryBoardToken = nil
            hasBoardToken = false
        } else {
            let status = Keychain.write(trimmed, service: service, account: Defaults.boardToken)
            keychainWriteStatus = status
            inMemoryBoardToken = status == errSecSuccess ? nil : trimmed
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
    /// Returns the Keychain status so a caller can see a write that did not
    /// stick. A silent failure here looks exactly like "the app forgot my
    /// key", which is a miserable thing to debug on a phone.
    @discardableResult
    static func write(_ value: String, service: String, account: String) -> OSStatus {
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
        return SecItemAdd(insert as CFDictionary, nil)
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
