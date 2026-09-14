import Foundation

private enum TestFailure: Error { case failed(String) }
private func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw TestFailure.failed(message) }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    private var intervals: [TimeInterval] = []
    func now() -> Date { lock.withLock { date } }
    func advance(_ interval: TimeInterval) { lock.withLock { intervals.append(interval); date += interval } }
    var sleeps: [TimeInterval] { lock.withLock { intervals } }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var replies: [(Int, String)] = []
    static var requests: [URLRequest] = []
    static func reset(_ values: [(Int, String)]) { lock.withLock { replies = values; requests = [] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply: (Int, String)? = Self.lock.withLock {
            Self.requests.append(request)
            return Self.replies.isEmpty ? nil : Self.replies.removeFirst()
        }
        guard let reply else {
            client?.urlProtocol(self, didFailWithError: TestFailure.failed("Unexpected HTTP request"))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct GitHubSignInTests {
    static let deviceReply = """
    {"device_code":"test-device","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
    """
    static let tokenReply = """
    {"access_token":"ghu_test_access","refresh_token":"ghr_test_refresh","token_type":"bearer","expires_in":28800,"refresh_token_expires_in":15897600}
    """
    static func client(_ clock: TestClock) -> GitHubSignInService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return GitHubSignInService(session: URLSession(configuration: config), now: { clock.now() }, sleep: { clock.advance($0) })
    }
    static func device(_ clock: TestClock, lifetime: TimeInterval = 900) -> GitHubDeviceAuthorization {
        GitHubDeviceAuthorization(deviceCode: "test-device", userCode: "ABCD-1234",
            verificationURL: URL(string: "https://github.com/login/device")!, expiresAt: clock.now() + lifetime, interval: 5)
    }
    static func expectError(_ expected: GitHubSignInError, _ action: () async throws -> Void) async throws {
        do { try await action(); throw TestFailure.failed("Expected \(expected)") }
        catch let error as GitHubSignInError { try expect(error == expected, "Wrong sign-in error") }
    }
    static func main() async throws {
        let clock = TestClock()
        let service = client(clock)
        StubProtocol.reset([(200, deviceReply)])
        let start = try await service.begin(clientID: "public-client-id")
        try expect(start.userCode == "ABCD-1234" && start.interval == 5, "Device challenge parsing")
        try expect(start.expiresAt == clock.now() + 900, "Device expiry")
        try expect(StubProtocol.requests.first?.url?.absoluteString == "https://github.com/login/device/code", "Fixed HTTPS endpoint")
        try expect(StubProtocol.requests.first?.httpMethod == "POST", "POST required")
        print("PASS device challenge and fixed HTTPS endpoint")

        StubProtocol.reset([])
        try await expectError(.notConfigured) { _ = try await service.begin(clientID: "") }
        try expect(StubProtocol.requests.isEmpty, "Missing client must not call network")
        print("PASS missing configuration")

        for malformed in [
            deviceReply.replacingOccurrences(of: "https://github.com/login/device", with: "https://example.invalid/phishing"),
            deviceReply.replacingOccurrences(of: "\"interval\":5", with: "\"interval\":0"),
            deviceReply.replacingOccurrences(of: "\"expires_in\":900", with: "\"expires_in\":0")
        ] {
            StubProtocol.reset([(200, malformed)])
            try await expectError(.invalidResponse) { _ = try await service.begin(clientID: "test") }
        }
        print("PASS verification origin, interval, and expiry validation")

        StubProtocol.reset([(200, "{\"error\":\"authorization_pending\"}"),
                            (200, "{\"error\":\"slow_down\",\"interval\":10}"), (200, tokenReply)])
        let credentials = try await service.authorize(device(clock), clientID: "public-client-id")
        try expect(clock.sleeps == [5, 5, 10], "Must respect pending and slow_down intervals")
        try expect(credentials.session.expiresAt == clock.now() + 28800, "Access expiry preserved")
        try expect(credentials.session.clientID == "public-client-id", "Refresh client preserved")
        print("PASS pending, slow_down, and credential expiry")

        for (error, expected) in [("access_denied", GitHubSignInError.denied),
                                  ("expired_token", .expired), ("incorrect_device_code", .unavailable)] {
            StubProtocol.reset([(200, "{\"error\":\"\(error)\"}")])
            try await expectError(expected) { _ = try await service.authorize(device(clock), clientID: "test") }
        }
        print("PASS denial, expiry, and terminal errors")

        StubProtocol.reset([])
        try await expectError(.expired) { _ = try await service.authorize(device(clock, lifetime: 1), clientID: "test") }
        try expect(StubProtocol.requests.isEmpty, "Must not poll after challenge expiry")
        print("PASS no poll after expiry")

        StubProtocol.reset([(200, tokenReply.replacingOccurrences(of: "ghr_test_refresh", with: ""))])
        try await expectError(.invalidResponse) { _ = try await service.authorize(device(clock), clientID: "test") }
        print("PASS incomplete expiring credentials rejected")

        StubProtocol.reset([(200, tokenReply.replacingOccurrences(of: "ghr_test_refresh", with: "ghr_rotated"))])
        let rotated = try await service.refresh(credentials.session)
        try expect(rotated.session.refreshToken == "ghr_rotated", "Refresh token rotation")
        let roundTrip = try JSONDecoder().decode(GitHubOAuthSession.self, from: JSONEncoder().encode(rotated.session))
        try expect(roundTrip.expiresAt == rotated.session.expiresAt, "Secure record date roundtrip")
        print("PASS renewal and credential metadata roundtrip")

        StubProtocol.reset([(200, "{\"error\":\"bad_refresh_token\"}")])
        try await expectError(.signInAgain) { _ = try await service.refresh(credentials.session) }
        StubProtocol.reset([])
        let expired = GitHubOAuthSession(clientID: "test", refreshToken: "ghr_expired", expiresAt: clock.now(), refreshExpiresAt: clock.now() - 1)
        try await expectError(.signInAgain) { _ = try await service.refresh(expired) }
        try expect(StubProtocol.requests.isEmpty, "Expired refresh token must not call network")
        print("PASS revoked and expired refresh tokens require sign-in")

        StubProtocol.reset([(503, "unavailable")])
        try await expectError(.unavailable) { _ = try await service.begin(clientID: "test") }
        StubProtocol.reset([(200, "not JSON")])
        try await expectError(.invalidResponse) { _ = try await service.begin(clientID: "test") }
        print("PASS HTTP and malformed response handling")

        StubProtocol.reset([])
        let cancelClient = GitHubSignInService(session: URLSession(configuration: .ephemeral), now: { clock.now() }, sleep: { _ in throw CancellationError() })
        do { _ = try await cancelClient.authorize(device(clock), clientID: "test"); throw TestFailure.failed("Cancellation must stop polling") }
        catch is CancellationError {}
        print("PASS cancellation stops polling")
        print("All GitHub sign-in checks passed.")
    }
}
