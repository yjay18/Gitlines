import Foundation

// These are public registration identifiers, never an app secret or user credential.
enum GitHubSignInConfiguration {
    static let clientID = "Iv23lidq3HCV4tq6ZUrW"
    static let appSlug = "gitlines-desktop"

    static var installationURL: URL? {
        guard !appSlug.isEmpty else { return nil }
        return URL(string: "https://github.com/apps/\(appSlug)/installations/new")
    }
}

// Stored only inside the host app's existing Keychain connection record.
struct GitHubOAuthSession: Codable, Sendable {
    let clientID: String
    let refreshToken: String
    let expiresAt: Date
    let refreshExpiresAt: Date
}

struct GitHubSignInCredentials: Sendable {
    let accessToken: String
    let session: GitHubOAuthSession
}

struct GitHubDeviceAuthorization: Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    let interval: TimeInterval
}

enum GitHubSignInError: LocalizedError, Equatable {
    case notConfigured
    case denied
    case expired
    case signInAgain
    case invalidResponse
    case unavailable
    case noRepositories

    var errorDescription: String? {
        switch self {
        case .notConfigured: "GitHub sign-in is not configured in this build."
        case .denied: "Sign-in was declined on GitHub. Your existing connection is unchanged."
        case .expired: "This sign-in code expired. Start Sign in with GitHub again."
        case .signInAgain: "Your GitHub authorization expired or was revoked. Sign in with GitHub again."
        case .invalidResponse: "GitHub returned an unexpected sign-in response. Please try again."
        case .unavailable: "GitHub sign-in is temporarily unavailable. Please try again."
        case .noRepositories: "Choose repositories for Gitlines on GitHub, then sign in again. Organization access may need an owner's approval."
        }
    }
}

struct GitHubSignInService: Sendable {
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        session: URLSession = GitHubSignInService.makeSession(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.session = session
        self.now = now
        self.sleep = sleep
    }

    func begin(clientID: String) async throws -> GitHubDeviceAuthorization {
        guard !clientID.isEmpty else { throw GitHubSignInError.notConfigured }
        let reply: DeviceReply = try await post("/login/device/code", fields: ["client_id": clientID])
        guard let code = reply.device_code, !code.isEmpty,
              let userCode = reply.user_code, !userCode.isEmpty,
              reply.verification_uri == "https://github.com/login/device",
              let seconds = reply.expires_in, seconds > 0, seconds <= 900,
              let interval = reply.interval, interval >= 1, interval <= seconds else {
            if reply.error == "device_flow_disabled" || reply.error == "incorrect_client_credentials" {
                throw GitHubSignInError.notConfigured
            }
            throw GitHubSignInError.invalidResponse
        }
        return GitHubDeviceAuthorization(
            deviceCode: code, userCode: userCode,
            verificationURL: URL(string: "https://github.com/login/device")!,
            expiresAt: now().addingTimeInterval(seconds), interval: interval
        )
    }

    func authorize(_ device: GitHubDeviceAuthorization, clientID: String) async throws -> GitHubSignInCredentials {
        var interval = device.interval
        while now() < device.expiresAt {
            try Task.checkCancellation()
            try await sleep(interval)
            try Task.checkCancellation()
            guard now() < device.expiresAt else { throw GitHubSignInError.expired }
            let reply: TokenReply = try await post("/login/oauth/access_token", fields: [
                "client_id": clientID,
                "device_code": device.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            switch reply.error {
            case "authorization_pending": continue
            case "slow_down":
                interval = max(interval + 5, min(reply.interval ?? 0, 900))
            case "access_denied": throw GitHubSignInError.denied
            case "expired_token", "token_expired": throw GitHubSignInError.expired
            case .some: throw GitHubSignInError.unavailable
            case .none: return try credentials(reply, clientID: clientID)
            }
        }
        throw GitHubSignInError.expired
    }

    func refresh(_ saved: GitHubOAuthSession) async throws -> GitHubSignInCredentials {
        guard saved.refreshExpiresAt > now() else { throw GitHubSignInError.signInAgain }
        let reply: TokenReply = try await post("/login/oauth/access_token", fields: [
            "client_id": saved.clientID,
            "refresh_token": saved.refreshToken,
            "grant_type": "refresh_token"
        ])
        guard reply.error == nil else { throw GitHubSignInError.signInAgain }
        return try credentials(reply, clientID: saved.clientID)
    }

    private func credentials(_ reply: TokenReply, clientID: String) throws -> GitHubSignInCredentials {
        guard let access = reply.access_token, access.hasPrefix("ghu_"),
              reply.token_type?.lowercased() == "bearer",
              let refresh = reply.refresh_token, refresh.hasPrefix("ghr_"),
              let expires = reply.expires_in, expires > 0,
              let refreshExpires = reply.refresh_token_expires_in, refreshExpires > 0 else {
            throw GitHubSignInError.invalidResponse
        }
        return GitHubSignInCredentials(accessToken: access, session: GitHubOAuthSession(
            clientID: clientID, refreshToken: refresh,
            expiresAt: now().addingTimeInterval(expires),
            refreshExpiresAt: now().addingTimeInterval(refreshExpires)
        ))
    }

    private func post<Response: Decodable>(_ path: String, fields: [String: String]) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://github.com\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Gitlines/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode), response.url == request.url else {
            throw GitHubSignInError.unavailable
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw GitHubSignInError.invalidResponse
        }
        return decoded
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: NoSignInRedirects(), delegateQueue: nil)
    }
}

private final class NoSignInRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct DeviceReply: Decodable {
    let device_code: String?
    let user_code: String?
    let verification_uri: String?
    let expires_in: TimeInterval?
    let interval: TimeInterval?
    let error: String?
}

private struct TokenReply: Decodable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: TimeInterval?
    let refresh_token_expires_in: TimeInterval?
    let token_type: String?
    let error: String?
    let interval: TimeInterval?
}
