import Foundation

struct DashboardRepository: Codable, Identifiable, Hashable, Sendable {
    let id: String // owner/name, never just the short name
    let isPrivate: Bool
    let isArchived: Bool
    let pushedAt: Date?
    var owner: String { String(id.split(separator: "/").first ?? "") }
    var name: String { String(id.split(separator: "/").last ?? "") }
    var url: URL { URL(string: "https://github.com/\(id)")! }
}

struct DashboardCommit: Codable, Identifiable, Hashable, Sendable {
    let repository: String
    let sha: String
    let date: Date
    let message: String
    let additions: Int
    let deletions: Int
    var id: String { "\(repository.lowercased()):\(sha.lowercased())" }
    var url: URL { URL(string: "https://github.com/\(repository)/commit/\(sha)")! }
}

struct DashboardCoverage: Codable, Sendable {
    var intervals: [DateInterval] = []
    var syncedAt: Date?
    var error: String?

    func contains(_ range: DateInterval) -> Bool {
        intervals.contains { $0.start <= range.start && $0.end >= range.end }
    }

    mutating func record(_ range: DateInterval, at date: Date) {
        var merged: [DateInterval] = []
        for item in (intervals + [range]).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, item.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, item.end))
            } else { merged.append(item) }
        }
        intervals = merged
        syncedAt = date
        error = nil
    }
}

struct DashboardHistory: Codable, Sendable {
    var version = 1
    var username: String
    var repositories: [DashboardRepository] = []
    var commits: [DashboardCommit] = []
    var coverage: [String: DashboardCoverage] = [:]
    var catalogUpdatedAt: Date?
    var asOf: Date?

    func commits(in range: DateInterval, repositories selected: Set<String> = []) -> [DashboardCommit] {
        commits.filter { $0.date >= range.start && $0.date < range.end && (selected.isEmpty || selected.contains($0.repository)) }
    }

    func coveredCount(in range: DateInterval, repositories selected: Set<String> = []) -> Int {
        repositories.filter { selected.isEmpty || selected.contains($0.id) }
            .filter { coverage[$0.id]?.contains(range) == true }.count
    }

    mutating func replaceCommits(for repository: String, in range: DateInterval, with values: [DashboardCommit]) {
        commits.removeAll { $0.repository == repository && $0.date >= range.start && $0.date < range.end }
        var unique = Dictionary(commits.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for value in values { unique[value.id] = value }
        commits = unique.values.sorted { $0.date > $1.date }
    }
}

enum DashboardHistoryStore {
    static func url() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            .appendingPathComponent("com.yjay18.widtget", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("dashboard-history.json")
    }
    static func read() throws -> DashboardHistory? {
        let path = try url()
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let history = try JSONDecoder().decode(DashboardHistory.self, from: Data(contentsOf: path))
        guard history.version == 1 else { return nil }
        return history
    }
    static func write(_ history: DashboardHistory) throws {
        try JSONEncoder().encode(history).write(to: url(), options: .atomic)
    }
    static func remove() throws {
        let path = try url()
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
}

enum DashboardRangeUnit: String, CaseIterable, Identifiable {
    case daily, weekly, monthly, custom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var component: Calendar.Component {
        switch self { case .daily, .custom: .day; case .weekly: .weekOfYear; case .monthly: .month }
    }
}

struct DashboardDateRange {
    let current: DateInterval
    let previous: DateInterval

    static func make(unit: DashboardRangeUnit, rolling: Bool, anchor: Date, now: Date,
                     customStart: Date, customEnd: Date, calendar: Calendar = .current) -> Self {
        let start: Date
        let end: Date
        let priorStart: Date
        let priorEnd: Date
        if unit == .custom {
            start = min(calendar.startOfDay(for: customStart), now)
            end = max(start, min(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd))!, now))
            let days = max(1, calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: customEnd)).day! + 1)
            priorStart = calendar.date(byAdding: .day, value: -days, to: start)!
            priorEnd = min(start, priorStart.addingTimeInterval(end.timeIntervalSince(start)))
        } else if rolling {
            end = min(anchor, now)
            let days = unit == .daily ? 1 : unit == .weekly ? 7 : 30
            start = end.addingTimeInterval(-Double(days) * 86400)
            priorEnd = start
            priorStart = start.addingTimeInterval(-Double(days) * 86400)
        } else {
            let interval = calendar.dateInterval(of: unit.component, for: min(anchor, now))!
            start = interval.start
            end = min(interval.end, now)
            priorStart = calendar.date(byAdding: unit.component, value: -1, to: start)!
            // Compare the same elapsed portion of an unfinished calendar period.
            priorEnd = end < interval.end ? min(start, priorStart.addingTimeInterval(end.timeIntervalSince(start))) : start
        }
        return Self(current: DateInterval(start: start, end: end), previous: DateInterval(start: priorStart, end: priorEnd))
    }
}

struct DashboardTotals {
    let commits: Int
    let additions: Int
    let deletions: Int
    let activeDays: Int
    let repositories: Int
    init(_ values: [DashboardCommit], calendar: Calendar = .current) {
        commits = values.count
        additions = values.reduce(0) { $0 + $1.additions }
        deletions = values.reduce(0) { $0 + $1.deletions }
        activeDays = Set(values.map { calendar.startOfDay(for: $0.date) }).count
        repositories = Set(values.map(\.repository)).count
    }
    static func change(_ value: Int, from previous: Int) -> String {
        if previous == 0 { return value == 0 ? "No change" : "New activity" }
        let percent = Double(value - previous) / Double(previous) * 100
        return String(format: "%+.0f%%", percent)
    }
}
