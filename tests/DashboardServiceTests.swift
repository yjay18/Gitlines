import Foundation

private final class HistoryHTTPStub: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var failRepository = false
    static var removeRepository = false
    static var detailRequests = 0
    static var repositoryPages: Set<Int> = []
    static func reset(fail: Bool = false, remove: Bool = false) {
        lock.withLock { failRepository = fail; removeRepository = remove; detailRequests = 0; repositoryPages = [] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        var status = 200
        var body: Any = [:]
        let options = Self.lock.withLock { (Self.failRepository, Self.removeRepository) }
        if path == "/user" { body = ["login": "tester"] }
        else if path == "/user/installations" { body = ["installations": [["id": 1]]] }
        else if path == "/user/installations/1/repositories" {
            let page = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!)!
            _ = Self.lock.withLock { Self.repositoryPages.insert(page) }
            var repos: [[String: Any]] = (0..<101).map { index in
                ["name": "repo\(index)", "full_name": "tester/repo\(index)", "private": index == 0,
                 "archived": index == 0, "default_branch": "main", "size": 0]
            }
            repos[0]["size"] = 10
            repos[0]["pushed_at"] = "2026-09-10T12:00:00Z"
            if options.1 { repos.removeFirst() }
            body = ["repositories": Array(repos.dropFirst((page - 1) * 100).prefix(100))]
        } else if path == "/repos/tester/repo0/branches" {
            if options.0 { status = 403; body = ["message": "Forbidden"] }
            else { body = [["name": "main"], ["name": "feature"]] }
        } else if path == "/repos/tester/repo0/commits" {
            body = [["sha": "abc", "commit": ["author": ["date": "2026-09-09T12:00:00Z"]]]]
        } else if path == "/repos/tester/repo0/commits/abc" {
            Self.lock.withLock { Self.detailRequests += 1 }
            body = ["stats": ["additions": 12, "deletions": 3], "commit": ["message": "Example commit\n\nBody"]]
        } else { status = 500; body = ["message": "Unexpected test request \(path)"] }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct DashboardServiceTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HistoryHTTPStub.self]
        let service = GitHubActivityService(session: URLSession(configuration: config))
        let start = ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!
        let range = DateInterval(start: start, duration: 10 * 86400)
        HistoryHTTPStub.reset()
        let first = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: nil) { _, _, _, _ in }
        expect(first.repositories.count == 101, "Discover every repository page, including inactive repositories")
        expect(HistoryHTTPStub.repositoryPages == [1, 2], "Fetch repository page two")
        expect(first.commits.count == 1, "Deduplicate a commit found on two branches")
        expect(first.commits[0].message == "Example commit", "Store commit subject and native GitHub link data")
        expect(first.repositories[0].isArchived && first.repositories[0].isPrivate, "Preserve repository filters")
        expect(first.coveredCount(in: range) == 101, "Empty repositories have known zero activity")
        expect(HistoryHTTPStub.detailRequests == 1, "Fetch one detail per unique commit")
        HistoryHTTPStub.reset()
        let second = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: first) { _, _, _, _ in }
        expect(HistoryHTTPStub.detailRequests == 0, "Reuse immutable commit statistics on repeat sync")
        HistoryHTTPStub.reset(fail: true)
        let larger = DateInterval(start: start - 86400, end: range.end)
        let failed = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: larger, existing: second) { _, _, _, _ in }
        expect(failed.coverage["tester/repo0"]?.error != nil, "Surface per-repository permission errors")
        expect(failed.coverage["tester/repo0"]?.contains(larger) == false, "Failed backfill cannot claim coverage")
        expect(failed.commits.count == 1, "Preserve cached activity on a failed request")
        HistoryHTTPStub.reset(remove: true)
        let removed = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: failed) { _, _, _, _ in }
        expect(removed.repositories.count == 100 && removed.commits.isEmpty, "Remove history for repositories no longer accessible")
        print("PASS paginated discovery, inactive/private/archived repositories, branch deduplication, stats cache, partial failure and revoked access")
    }
}
