import Foundation

enum RelayAPIError: LocalizedError {
    case notConfigured
    case unauthorized
    case server(status: Int, message: String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Server URL and a board key are required."
        case .unauthorized:
            return "The server rejected the credentials. Check the board key and try signing in again."
        case .server(let status, let message):
            return "Server error \(status): \(message)"
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

/// Thin client over the Paperclip board REST API.
///
/// Two authentication modes, both board-level (a human acting on the board,
/// not an agent acting on its own behalf):
///
/// 1. **Board API key** (`pcp_board_…`) as a bearer token. Preferred: it can
///    be minted with an expiry years out, so the app keeps working without
///    a weekly re-login.
/// 2. **Email + password sign-in**, which returns a session cookie. The
///    cookie is short-lived (7 days) and, for mutations, the server demands a
///    trusted browser `Origin` header — which this client sends, because a
///    native app talking to the board is still a board actor.
///
/// Writes are the reason this app exists, so both paths were verified
/// against the deployed instance rather than assumed.
final class APIClient {
    static let sessionCookieName = "__Secure-paperclip-default.session_token"

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 90
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String,
                           query: [URLQueryItem] = [],
                           auth: Credentials,
                           as type: T.Type) async throws -> T {
        let data = try await perform("GET", path, query: query, body: nil, auth: auth)
        do {
            return try decode(data)
        } catch let RelayAPIError.server(status, message) {
            // A decoding failure otherwise names neither the endpoint nor
            // the payload that drifted. Keep the route in the visible error
            // so a board schema change can be diagnosed on the phone.
            throw RelayAPIError.server(status: status, message: "\(path): \(message)")
        }
    }

    /// Fetch a resource as bytes rather than JSON — an attachment's content.
    func getRaw(_ path: String, auth: Credentials) async throws -> Data {
        try await perform("GET", path, query: [], body: nil, auth: auth)
    }

    func send<T: Decodable>(_ method: String,
                             _ path: String,
                             query: [URLQueryItem] = [],
                             body: [String: Any]?,
                             auth: Credentials,
                             as type: T.Type) async throws -> T {
        let data = try await perform(method, path, query: query, body: body, auth: auth)
        return try decode(data)
    }

    /// For endpoints whose reply shape we do not need to model.
    @discardableResult
    func send(_ method: String,
              _ path: String,
              query: [URLQueryItem] = [],
              body: [String: Any]?,
              auth: Credentials) async throws -> Data {
        try await perform(method, path, query: query, body: body, auth: auth)
    }

    private func perform(_ method: String,
                         _ path: String,
                         query: [URLQueryItem],
                         body: [String: Any]?,
                         auth: Credentials) async throws -> Data {
        guard let base = URL(string: auth.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme != nil else {
            throw RelayAPIError.notConfigured
        }

        var components = URLComponents(url: base.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw RelayAPIError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The board sits behind a CDN with a browser-integrity rule: a
        // non-browser user agent can be answered with a block page before
        // the request ever reaches Paperclip. The app identifies as an iPhone
        // Safari, which is how a browser tab would reach the same server.
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        if let token = auth.boardToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let cookie = auth.sessionCookie, !cookie.isEmpty {
            request.setValue("\(Self.sessionCookieName)=\(cookie)",
                             forHTTPHeaderField: "Cookie")
        }

        // Board mutations are refused without a trusted browser origin. The
        // trusted origin for a board is its own public URL, so send exactly
        // that — and only on writes, since reads do not care.
        if method != "GET" {
            request.setValue(origin(for: base), forHTTPHeaderField: "Origin")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RelayAPIError.server(status: -1, message: "No HTTP response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw RelayAPIError.unauthorized
            }
            guard (200..<300).contains(http.statusCode) else {
                throw RelayAPIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
            }
            return data
        } catch let error as RelayAPIError {
            throw error
        } catch {
            throw RelayAPIError.transport(error)
        }
    }

    /// `https://paperclip.phatt.vip` -> `https://paperclip.phatt.vip`
    private func origin(for base: URL) -> String {
        guard let scheme = base.scheme, let host = base.host else {
            return base.absoluteString
        }
        if let port = base.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if data.isEmpty {
            throw RelayAPIError.server(status: -1, message: "Empty response body")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RelayAPIError.server(status: -1, message: "Unexpected response shape: \(error.localizedDescription)")
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        for key in ["error", "message"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return object.keys.sorted().joined(separator: ", ")
    }

    /// iPhone Safari user agent, kept in one place so the sign-in request
    /// and the API requests cannot drift apart.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1"

    // MARK: - Sign-in

    /// Exchange email + password for a board session cookie.
    /// Returns the raw cookie value; the caller stores it.
    func signIn(baseURL: String, email: String, password: String) async throws -> String {
        guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RelayAPIError.notConfigured
        }
        let url = base.appendingPathComponent("api/auth/sign-in/email")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
        ])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RelayAPIError.server(status: -1, message: "No HTTP response")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw RelayAPIError.unauthorized
            }
            guard (200..<300).contains(http.statusCode) else {
                throw RelayAPIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
            }
            guard let cookie = Self.sessionCookieValue(from: http) else {
                throw RelayAPIError.server(status: -1, message: "Sign-in succeeded but no session cookie was returned")
            }
            return cookie
        } catch let error as RelayAPIError {
            throw error
        } catch {
            throw RelayAPIError.transport(error)
        }
    }

    /// Pull the session cookie out of the `Set-Cookie` header.
    ///
    /// The cookie name is `__Secure-paperclip-default.session_token`, so it
    /// is looked up by name rather than by position — a `Set-Cookie` header
    /// can carry more than one cookie.
    private static func sessionCookieValue(from response: HTTPURLResponse) -> String? {
        var candidates: [String] = []
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else { continue }
            let lower = name.lowercased()
            if lower == "set-cookie" {
                if let header = value as? String {
                    candidates.append(header)
                } else if let headers = value as? [String] {
                    candidates.append(contentsOf: headers)
                }
            }
        }
        for header in candidates {
            for part in header.split(separator: ";") {
                let piece = part.trimmingCharacters(in: .whitespaces)
                guard piece.hasPrefix("\(sessionCookieName)=") else { continue }
                return String(piece.dropFirst("\(sessionCookieName)=".count))
            }
        }
        return nil
    }
}

/// Credentials for one request.
struct Credentials {
    var baseURL: String
    var companyId: String
    var boardToken: String?
    var sessionCookie: String?

    var isConfigured: Bool {
        let hasToken = boardToken?.isEmpty == false
        let hasCookie = sessionCookie?.isEmpty == false
        return !baseURL.isEmpty && (hasToken || hasCookie)
    }
}
