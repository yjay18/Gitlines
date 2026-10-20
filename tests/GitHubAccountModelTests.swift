import Foundation

private enum AccountTestFailure: Error { case failed(String) }
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw AccountTestFailure.failed(message) }
}

// Hold the first identity request until the test releases a 401. No response can
// reach connection persistence, and every request is intercepted locally.
private final class DeferredAccountFailure: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var pending: DeferredAccountFailure?
    private static var requestTotal = 0

    static var requestCount: Int { lock.withLock { requestTotal } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let hold = Self.lock.withLock {
            Self.requestTotal += 1
            // A guard regression must fail the test promptly, never hang on a
            // second held request or allow it to reach credential persistence.
            guard Self.requestTotal == 1 else { return false }
            Self.pending = self
            return true
        }
        guard hold else {
            fail()
            return
        }
    }
    override func stopLoading() {}

    static func waitForRequest() async throws {
        for _ in 0..<500 {
            if requestCount > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AccountTestFailure.failed("Identity request did not start within five seconds")
    }

    static func failRequest() throws {
        let request = lock.withLock { () -> DeferredAccountFailure? in
            defer { pending = nil }
            return pending
        }
        guard let request, let url = request.request.url else {
            throw AccountTestFailure.failed("Expected an intercepted identity request")
        }
        guard url.path == "/user" else {
            throw AccountTestFailure.failed("Only identity validation may be requested")
        }
        request.fail()
    }

    private func fail() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
private struct GitHubAccountModelTests {
    @MainActor static func main() async throws {
        // This flag makes model initialization skip saved preferences. Do not call
        // bootstrap, refresh, sign-in, or disconnect: those access the real Keychain.
        try expect(CommandLine.arguments.contains("--sample-data"), "Run in sample mode")
        let now = Date(timeIntervalSince1970: 1_791_734_400)
        let stale = now.addingTimeInterval(-25 * 86400)
        func due(snapshot: Date?, history: Date?, attempt: Date? = nil, retry: Date? = nil) -> Bool {
            GitHubAccountModel.shouldAutomaticallyRefresh(lastRefresh: snapshot, historyDate: history,
                lastAttempt: attempt, retryAt: retry, now: now, interval: 1800)
        }
        try expect(due(snapshot: now, history: stale), "Fresh widgets cannot hide September dashboard history")
        try expect(due(snapshot: stale, history: now), "Fresh dashboard history cannot hide stale widgets")
        try expect(due(snapshot: now, history: nil), "A missing history cache needs initial sync")
        try expect(!due(snapshot: now, history: now), "Fresh caches must not issue redundant requests")
        try expect(!due(snapshot: stale, history: stale, attempt: now), "Failed attempts wait for the refresh interval")
        try expect(due(snapshot: stale, history: stale, attempt: now.addingTimeInterval(-1800)),
                   "Failed requests are retried after the configured interval")
        try expect(!due(snapshot: stale, history: stale, retry: now.addingTimeInterval(60)),
                   "Activation must not bypass a rate-limit retry")
        try expect(due(snapshot: stale, history: stale, retry: now.addingTimeInterval(-60)),
                   "A new background process may resume after a saved rate limit expires")
        let leaseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: leaseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: leaseDirectory) }
        let leaseURL = leaseDirectory.appendingPathComponent("sync.lock")
        var firstLease = try GitHubHostSyncLease.acquire(at: leaseURL)
        try expect(firstLease != nil, "The first host process can sync")
        let competingLease = try GitHubHostSyncLease.acquire(at: leaseURL)
        try expect(competingLease == nil,
                   "A concurrent scheduled run cannot renew tokens or overwrite host caches")
        firstLease = nil
        let nextLease = try GitHubHostSyncLease.acquire(at: leaseURL)
        try expect(nextLease != nil, "Closing the owner releases the sync lease")
        withExtendedLifetime(nextLease) {}
        print("PASS nonblocking host sync exclusion and release")
        print("PASS independent cache freshness, initial sync, retry throttling and rate-limit cooldown")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeferredAccountFailure.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let model = GitHubAccountModel(service: GitHubActivityService(session: session, branchCacheDefaults: nil))

        model.tokenInput = " \n"
        await model.connect()
        try expect(DeferredAccountFailure.requestCount == 0, "Empty credentials must not make requests")

        model.tokenInput = "ghp_fake_offline_test_only"
        let firstConnect = Task { await model.connect() }
        try await DeferredAccountFailure.waitForRequest()
        try expect(model.phase == .connecting && model.isBusy, "Connection owns the busy state")
        try expect(!model.canConnect, "Duplicate connect is disabled while the first is running")
        await model.connect()
        model.organizationInput = "test-organization"
        model.additionalTokenInput = "ghp_other_fake_offline_test_only"
        model.replacementAccountTokenInput = "ghp_replacement_fake_offline_test_only"
        await model.addOrganization()
        await model.replaceAccountToken()
        await model.removeOrganization(id: UUID())
        model.cancelSignIn()
        try expect(model.phase == .connecting, "Idle sign-in cancellation must not interrupt token connection")
        try expect(DeferredAccountFailure.requestCount == 1, "Concurrent operations must not issue more requests")

        try DeferredAccountFailure.failRequest()
        await firstConnect.value
        try expect(model.phase == .failed && !model.hasStoredToken, "Failed validation cannot save a connection")
        let failureMessage = model.message
        model.cancelSignIn()
        try expect(model.phase == .failed && model.message == failureMessage,
                   "Idle sign-in cancellation must preserve connection failure")
        await model.addOrganization()
        await model.replaceAccountToken()
        await model.removeOrganization(id: UUID())
        try expect(DeferredAccountFailure.requestCount == 1, "Disconnected mutations must not reach credential storage")
        try expect(model.phase == .failed, "Unavailable mutations preserve the last failure")
        print("PASS duplicate connect, concurrent connection mutations and idle sign-in cancellation")
        print("PASS failed validation and disconnected guards without credentials, saved data or live requests")
    }
}
