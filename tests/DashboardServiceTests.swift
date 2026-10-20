import Foundation

private final class HistoryHTTPStub: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var failRepository = false
    static var removeRepository = false
    static var detailRequests = 0
    static var repositoryPages: Set<Int> = []
    static var changesRepositoryCase = false
    static var commitDates = ["abc": "2026-09-09T12:00:00Z"]
    static var rateLimitedDetails: Set<String> = []
    static var detailFailureStatus = 403
    static var retryAfter: String?
    static var missingCommits = false
    static var requestedSince: Set<String> = []
    static var pushedAt = "2026-12-31T12:00:00Z"
    static var featureOnlyCommits: Set<String> = []
    static func reset(fail: Bool = false, remove: Bool = false, changesCase: Bool = false,
                      commits: [String: String] = ["abc": "2026-09-09T12:00:00Z"],
                      rateLimitedDetails: Set<String> = [], status: Int = 403, retryAfter: String? = nil,
                      missingCommits: Bool = false, pushedAt: String = "2026-12-31T12:00:00Z",
                      featureOnlyCommits: Set<String> = []) {
        lock.withLock {
            failRepository = fail; removeRepository = remove; detailRequests = 0; repositoryPages = []
            changesRepositoryCase = changesCase; commitDates = commits
            Self.rateLimitedDetails = rateLimitedDetails; detailFailureStatus = status; Self.retryAfter = retryAfter
            Self.missingCommits = missingCommits
            requestedSince = []
            Self.pushedAt = pushedAt
            Self.featureOnlyCommits = featureOnlyCommits
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path.lowercased()
        var status = 200
        var body: Any = [:]
        var headers: [String: String] = [:]
        let options = Self.lock.withLock {
            (Self.failRepository, Self.removeRepository, Self.changesRepositoryCase, Self.commitDates,
             Self.rateLimitedDetails, Self.detailFailureStatus, Self.retryAfter, Self.missingCommits, Self.pushedAt)
        }
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
            repos[0]["pushed_at"] = options.8
            if options.2 { repos[0]["name"] = "Repo0"; repos[0]["full_name"] = "Tester/Repo0" }
            if options.1 { repos.removeFirst() }
            body = ["repositories": Array(repos.dropFirst((page - 1) * 100).prefix(100))]
        } else if path == "/repos/tester/repo0/branches" {
            if options.0 { status = 403; body = ["message": "Forbidden"] }
            else { body = [["name": "main"], ["name": "feature"]] }
        } else if path == "/repos/tester/repo0/commits" {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let since = query.first { $0.name == "since" }!.value!
            let until = query.first { $0.name == "until" }!.value!
            let branch = query.first { $0.name == "sha" }!.value!
            let featureOnly = Self.lock.withLock { Self.featureOnlyCommits }
            _ = Self.lock.withLock { Self.requestedSince.insert(since) }
            if options.7 { status = 404; body = ["message": "Not Found"] }
            else { body = options.3.filter { $0.value >= since && $0.value <= until
                    && (branch == "feature" || !featureOnly.contains($0.key)) }
                .map { ["sha": $0.key, "commit": ["author": ["date": $0.value]]] } }
        } else if path.hasPrefix("/repos/tester/repo0/commits/") {
            Self.lock.withLock { Self.detailRequests += 1 }
            if options.4.contains(String(path.split(separator: "/").last!)) {
                status = options.5
                headers["X-RateLimit-Remaining"] = options.6 == nil ? "0" : "42"
                headers["X-RateLimit-Reset"] = "1893456000"
                headers["Retry-After"] = options.6
                body = ["message": "Rate limit reached"]
            } else {
                body = ["stats": ["additions": 12, "deletions": 3], "commit": ["message": "Example commit\n\nBody"]]
            }
        } else { status = 500; body = ["message": "Unexpected test request \(path)"] }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor HistoryCheckpoint {
    private var history: DashboardHistory?
    func save(_ value: DashboardHistory) { history = value }
    func read() -> DashboardHistory? { history }
}

@main
struct DashboardServiceTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func main() async throws {
        let raw = try GitHubTokenStore.decodeConnections(Data("  ghp_fixture_only\n".utf8), defaultUsername: "tester")
        expect(raw.count == 1 && raw[0].token == "ghp_fixture_only", "Raw Keychain token migration trims whitespace")
        let tokens = try GitHubTokenStore.decodeConnections(Data("[\"ghp_fixture_only\",\"ghp_fixture_only\"]".utf8), defaultUsername: "tester")
        expect(tokens.count == 1, "Legacy token migration deduplicates credentials")
        for invalid in ["{\"schemaVersion\":99,\"connections\":[]}", "{\"schemaVersion\":2,\"connections\":", "[42]", "ghp fixture"] {
            do {
                _ = try GitHubTokenStore.decodeConnections(Data(invalid.utf8), defaultUsername: "tester")
                fatalError("Corrupt or unsupported secure records must not become raw tokens")
            } catch GitHubTokenStoreError.invalidTokenData {}
        }
        print("PASS offline Keychain archive validation and legacy credential migration")
        // Release regression: each widget period must retain its own cached data,
        // including offline/error states and archives written before monthly support.
        func snapshot(_ count: Int) -> ActivitySnapshot {
            ActivitySnapshot(additions: count, deletions: 0, commits: count,
                             repositories: [], activity: [], updatedAt: Date(timeIntervalSince1970: 100))
        }
        let archive = ActivitySnapshotArchive(username: "tester", daily: snapshot(1), weekly: snapshot(2),
            rollingDaily: snapshot(3), rollingWeekly: snapshot(4), monthly: snapshot(5), rollingMonthly: snapshot(6))
        let roundTrip = try JSONDecoder().decode(ActivitySnapshotArchive.self, from: JSONEncoder().encode(archive))
        let failedArchive = roundTrip.markingRefreshError("Offline")
        for (period, mode, count) in [(StoredActivityPeriod.daily, PeriodWindowMode.fixed, 1),
            (.weekly, .fixed, 2), (.daily, .rolling, 3), (.weekly, .rolling, 4),
            (.monthly, .fixed, 5), (.monthly, .rolling, 6)] {
            expect(roundTrip.snapshot(for: period, windowMode: mode).commits == count, "Preserve every widget window")
            let failed = failedArchive.snapshot(for: period, windowMode: mode)
            expect(failed.state == .error && failed.commits == count, "Offline state retains the correct cached window")
            expect(failed.updatedAt == snapshot(count).updatedAt, "Failure must not advance the data timestamp")
        }
        let legacy = ActivitySnapshotArchive(username: "tester", daily: snapshot(1), weekly: snapshot(2))
        let legacyDecoded = try JSONDecoder().decode(ActivitySnapshotArchive.self, from: JSONEncoder().encode(legacy))
        expect(legacyDecoded.snapshot(for: .monthly, windowMode: .rolling).commits == 2, "Old archives remain readable")
        print("PASS all six widget windows, archive round trip, offline retention and legacy fallback")
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
        let nextRange = DateInterval(start: start, end: range.end.addingTimeInterval(86400))
        let updatedCommits = ["abc": "2026-09-09T12:00:00Z", "late": "2026-09-10T12:00:00Z", "new": "2026-09-11T12:00:00Z"]
        HistoryHTTPStub.reset(commits: updatedCommits, pushedAt: "2026-09-10T23:59:59Z")
        let caughtUp = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: nextRange,
            existing: second, incremental: true) { _, _, _, _ in }
        expect(HistoryHTTPStub.requestedSince == ["2026-09-10T00:00:00Z"], "Automatic sync overlaps the last covered day")
        expect(caughtUp.commits.count == 3, "Catch-up retains older commits and adds new and late-pushed commits")
        expect(caughtUp.coveredCount(in: nextRange) == 101, "Catch-up merges coverage through the actual current date")
        expect(HistoryHTTPStub.detailRequests == 2, "Catch-up fetches only new commit details")
        HistoryHTTPStub.reset(commits: updatedCommits.merging(["oldPush": "2026-09-02T12:00:00Z"]) { old, _ in old })
        let pushed = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: nextRange,
            existing: caughtUp, incremental: true) { _, _, _, _ in }
        expect(HistoryHTTPStub.requestedSince == ["2026-09-01T00:00:00Z"], "New pushes recheck the full window for older authored commits")
        expect(pushed.commits.count == 4 && HistoryHTTPStub.detailRequests == 1,
               "Older commits newly pushed on a branch are added without refetching saved stats")
        var missingCoverage = second
        missingCoverage.coverage.removeValue(forKey: "tester/repo0")
        HistoryHTTPStub.reset()
        _ = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: nextRange,
            existing: missingCoverage, incremental: true) { _, _, _, _ in }
        expect(HistoryHTTPStub.requestedSince == ["2026-09-01T00:00:00Z"], "Newly accessible repositories fetch the whole history window")
        var erroredCoverage = second
        erroredCoverage.coverage["tester/repo0"]?.error = "Previous sync failed"
        HistoryHTTPStub.reset()
        _ = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: nextRange,
            existing: erroredCoverage, incremental: true) { _, _, _, _ in }
        expect(HistoryHTTPStub.requestedSince == ["2026-09-01T00:00:00Z"], "Incomplete repositories receive a full retry")
        HistoryHTTPStub.reset()
        _ = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: nextRange,
            existing: second) { _, _, _, _ in }
        expect(HistoryHTTPStub.requestedSince == ["2026-09-01T00:00:00Z"], "Manual history sync still rechecks the selected full window")
        print("PASS incremental catch-up, late pushes, full backfill for missing/error coverage and explicit resync")
        HistoryHTTPStub.reset(fail: true, changesCase: true)
        let recased = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: second) { _, _, _, _ in }
        expect(recased.commits.count == 1 && recased.commits[0].repository == "Tester/Repo0", "Canonical case changes retain saved repository activity")
        expect(recased.coverage["Tester/Repo0"]?.contains(range) == true, "Canonical case changes retain saved coverage")
        HistoryHTTPStub.reset(fail: true)
        let larger = DateInterval(start: start - 86400, end: range.end)
        let failed = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: larger, existing: second) { _, _, _, _ in }
        expect(failed.coverage["tester/repo0"]?.error != nil, "Surface per-repository permission errors")
        expect(failed.coverage["tester/repo0"]?.contains(larger) == false, "Failed backfill cannot claim coverage")
        expect(failed.commits.count == 1, "Preserve cached activity on a failed request")
        HistoryHTTPStub.reset(remove: true)
        let removed = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: failed) { _, _, _, _ in }
        expect(removed.repositories.count == 100 && removed.commits.isEmpty, "Remove history for repositories no longer accessible")
        HistoryHTTPStub.reset(missingCommits: true)
        let inaccessible = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: nil) { _, _, _, _ in }
        expect(inaccessible.coverage["tester/repo0"]?.error != nil, "A freshly enumerated branch returning 404 requires repository attention")
        expect(inaccessible.coverage["tester/repo0"]?.contains(range) != true, "An access-related 404 cannot claim known zero activity")
        print("PASS paginated discovery, inactive/private/archived repositories, branch deduplication, stats cache, partial failure and revoked access")

        let twoCommits = ["abc": "2026-09-09T12:00:00Z", "def": "2026-09-09T13:00:00Z"]
        let checkpoint = HistoryCheckpoint()
        HistoryHTTPStub.reset(commits: twoCommits, rateLimitedDetails: ["def"])
        do {
            _ = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: nil) {
                history, _, _, _ in await checkpoint.save(history)
            }
            fatalError("Expected rate limit")
        } catch GitHubActivityError.rateLimited {}
        let partial = await checkpoint.read()!
        expect(partial.commits.count == 1, "A rate-limited batch checkpoints successful detail responses")
        expect(partial.coverage["tester/repo0"]?.contains(range) != true, "Partial detail responses cannot claim complete coverage")
        HistoryHTTPStub.reset(commits: twoCommits)
        let resumed = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: partial) { _, _, _, _ in }
        expect(resumed.commits.count == 2 && HistoryHTTPStub.detailRequests == 1, "Resume requests only details missing from the checkpoint")

        for status in [403, 429] {
            HistoryHTTPStub.reset(rateLimitedDetails: ["abc"], status: status, retryAfter: "30")
            do {
                _ = try await service.fetchDashboardHistory(tokens: ["ghu_fake_test_only"], range: range, existing: nil) { _, _, _, _ in }
                fatalError("Expected secondary rate limit")
            } catch GitHubActivityError.rateLimited(let retryAt) {
                expect((retryAt?.timeIntervalSinceNow ?? 0) > 25, "Secondary rate limit respects Retry-After")
            }
        }
        print("PASS rate-limited detail checkpoints, cache reuse on resume and secondary rate limits")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        calendar.firstWeekday = 2
        // Snapshot tests must not read/write the running app's recent-branch preferences.
        let snapshotService = GitHubActivityService(session: URLSession(configuration: config), calendar: calendar, branchCacheDefaults: nil)
        let monthNow = ISO8601DateFormatter().date(from: "2026-09-30T22:00:00Z")!
        HistoryHTTPStub.reset(commits: ["feature": "2026-09-30T12:00:00Z"], featureOnlyCommits: ["feature"])
        let recent = try await snapshotService.fetchSnapshots(token: "ghu_fake_test_only", now: monthNow, scope: .recentBranches)
        expect(recent.daily.commits == 0, "Reproduce the old scan missing a newly active feature branch")
        let widgetRange = DateInterval(start: monthNow.addingTimeInterval(-31 * 86400), end: monthNow)
        let complete = try await snapshotService.fetchDashboardHistory(tokens: ["ghu_fake_test_only"],
            range: widgetRange, existing: nil) { _, _, _, _ in }
        let rebuilt = snapshotService.snapshots(from: complete, now: monthNow)!
        for period in [StoredActivityPeriod.daily, .weekly, .monthly] {
            for mode in [PeriodWindowMode.fixed, .rolling] {
                let snapshot = rebuilt.snapshot(for: period, windowMode: mode)
                expect(snapshot.commits == 1 && snapshot.additions == 12 && snapshot.deletions == 3,
                       "All six widget windows retain commits found on new branches")
                expect(snapshot.activity.reduce(0) { $0 + $1.additions } == 12,
                       "History-backed activity cells match the displayed totals")
            }
        }
        expect(rebuilt.savedAt == monthNow && rebuilt.daily.updatedAt == monthNow,
               "Widget freshness reflects the history cutoff, not the rebuild time")
        var incomplete = complete
        incomplete.coverage.removeValue(forKey: "tester/repo0")
        expect(snapshotService.snapshots(from: incomplete, now: monthNow) == nil,
               "Incomplete history requires a full widget fetch instead of incomplete totals")
        var failedHistory = complete
        failedHistory.coverage["tester/repo0"]?.error = "Offline"
        expect(snapshotService.snapshots(from: failedHistory, now: monthNow) == nil,
               "Repository errors cannot become successful widget data")
        expect(snapshotService.snapshots(from: complete, now: monthNow.addingTimeInterval(1)) == nil,
               "History cannot claim coverage beyond its actual sync cutoff")
        print("PASS new-branch widget activity, all six windows, coverage guards and truthful freshness")
        HistoryHTTPStub.reset(missingCommits: true)
        do {
            _ = try await snapshotService.fetchSnapshots(token: "ghu_fake_test_only", now: monthNow, scope: .recentBranches)
            fatalError("A default-branch 404 must not become a no-activity snapshot")
        } catch GitHubActivityError.notFound {}
        HistoryHTTPStub.reset(commits: ["abc": "2026-09-07T23:00:00Z", "def": "2026-09-28T23:00:00Z", "ghi": "2026-09-07T21:00:00Z"])
        let monthArchive = try await snapshotService.fetchSnapshots(token: "ghu_fake_test_only", now: monthNow)
        expect(monthArchive.monthly?.activity.map(\.additions) == [12, 12, 0, 0, 12], "Month weeks use seven calendar days with a final remainder")
        expect(monthArchive.rollingMonthly?.activity.map(\.additions) == [12, 12, 0, 0, 12], "Rolling month uses four complete weeks and two remaining days")

        let dstNow = ISO8601DateFormatter().date(from: "2026-03-29T22:30:00Z")!
        HistoryHTTPStub.reset(commits: ["abc": "2026-03-29T22:15:00Z"])
        let dstArchive = try await snapshotService.fetchSnapshots(token: "ghu_fake_test_only", now: dstNow)
        expect(dstArchive.daily.activity[11].additions == 12 && dstArchive.weekly.activity[6].additions == 12,
               "DST clock-day buckets match widget hour and weekday labels")
        print("PASS seven-day month buckets, rolling remainder and calendar DST snapshot aggregation")
    }
}
