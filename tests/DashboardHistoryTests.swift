import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@main
struct DashboardHistoryTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        calendar.firstWeekday = 2
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        let now = date("2026-09-10T14:00:00Z")
        func range(_ unit: DashboardRangeUnit, _ anchor: Date? = nil, rolling: Bool = false) -> DashboardDateRange {
            .make(unit: unit, rolling: rolling, anchor: anchor ?? now, now: now,
                  customStart: date("2026-08-02T12:00:00Z"), customEnd: date("2026-08-05T12:00:00Z"), calendar: calendar)
        }
        let weekly = range(.weekly)
        check(weekly.current.start == date("2026-09-06T23:00:00Z"), "Week starts on local Monday")
        check(weekly.current.duration == weekly.previous.duration, "Current week compares equivalent elapsed time")
        let august = range(.monthly, date("2026-08-15T12:00:00Z"))
        check(august.current.end == date("2026-08-31T23:00:00Z"), "Historical month is complete")
        check(august.previous.start == date("2026-06-30T23:00:00Z"), "Previous calendar month begins July 1")
        check(august.previous.end == august.current.start, "Previous month ends at current start")
        let custom = range(.custom)
        check(custom.current.duration == 4 * 86400, "Custom end day is inclusive")
        check(custom.previous.end == custom.current.start, "Custom comparison immediately precedes range")
        check(range(.weekly, rolling: true).current.duration == 7 * 86400, "Rolling week")
        let dst = DashboardDateRange.make(unit: .daily, rolling: false, anchor: date("2026-03-29T12:00:00Z"), now: now,
                                         customStart: now, customEnd: now, calendar: calendar)
        check(dst.current.duration == 23 * 3600, "Calendar day follows DST, not a fixed 24 hours")
        let rollingDST = DashboardDateRange.make(unit: .daily, rolling: true, anchor: date("2026-03-29T12:00:00Z"), now: now,
                                                customStart: now, customEnd: now, calendar: calendar)
        check(rollingDST.current.duration == 24 * 3600, "Rolling daily remains exactly 24 hours across DST")
        let february = range(.monthly, date("2026-02-15T12:00:00Z"))
        check(february.current.duration == 28 * 86400, "February uses calendar boundaries")
        check(DashboardTotals.change(3, from: 0) == "New activity", "No infinite percentage from zero")
        check(DashboardTotals.change(0, from: 0) == "No change", "Zero baseline")

        var coverage = DashboardCoverage()
        let a = DateInterval(start: now, duration: 100)
        let b = DateInterval(start: now + 200, duration: 100)
        coverage.record(a, at: now); coverage.record(b, at: now)
        check(!coverage.contains(DateInterval(start: now, duration: 300)), "A gap must not be reported as synced")
        coverage.record(DateInterval(start: now + 100, duration: 100), at: now)
        check(coverage.contains(DateInterval(start: now, duration: 300)), "Adjacent coverage merges")
        coverage.error = "Offline"
        coverage.record(a, at: now)
        check(coverage.error == nil, "A successful retry clears repository error")

        let one = DashboardCommit(repository: "a/shared", sha: "abc", date: now, message: "First", additions: 4, deletions: 2)
        let sameSHAOtherRepo = DashboardCommit(repository: "b/shared", sha: "abc", date: now, message: "Other", additions: 9, deletions: 1)
        let after = DashboardCommit(repository: "a/shared", sha: "def", date: now + 100, message: "Boundary", additions: 1, deletions: 0)
        var history = DashboardHistory(username: "tester")
        history.commits = [one, sameSHAOtherRepo, after]
        history.replaceCommits(for: "a/shared", in: a, with: [one, one])
        check(history.commits.count == 3, "Deduplicate branches without collapsing matching SHAs across repos")
        check(history.commits(in: a).count == 2, "End boundary is exclusive")
        check(history.commits(in: a, repositories: ["b/shared"]).count == 1, "Repository selection matches full owner/name")
        history.replaceCommits(for: "a/shared", in: a, with: [])
        check(!history.commits.contains { $0.id == one.id }, "Resync removes commits no longer reachable in that window")
        check(history.commits.contains { $0.id == after.id }, "Resync preserves out-of-window history")
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(DashboardHistory.self, from: data)
        check(decoded.commits == history.commits, "History cache round trip")
        let text = String(decoding: data, as: UTF8.self)
        check(!text.contains("token"), "Display cache contains no token fields")
        print("PASS calendar and rolling windows, equal elapsed comparisons, custom dates, DST, coverage gaps, retry, deduplication, filters and cache round trip")
    }
}
