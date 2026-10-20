import Foundation

// One bucket definition for the host's aggregation and every widget's labels.
// Calendar windows follow local clock/day boundaries; rolling windows cover an
// exact elapsed duration. Months always expose five seven-day cells (W1–W5),
// with the fifth cell holding the remainder, or staying empty in a 28-day month.
enum ActivityBucketLayout {
    static func cellCount(for period: StoredActivityPeriod) -> Int {
        switch period {
        case .daily: 12
        case .weekly: 7
        case .monthly: 5
        }
    }

    static func interval(
        for period: StoredActivityPeriod,
        windowMode: PeriodWindowMode,
        anchor: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        if windowMode == .rolling {
            let days: Int
            switch period {
            case .daily: days = 1
            case .weekly: days = 7
            case .monthly: days = 30
            }
            return DateInterval(start: anchor.addingTimeInterval(-Double(days) * 86_400), end: anchor)
        }

        let component: Calendar.Component
        switch period {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        }
        if let interval = calendar.dateInterval(of: component, for: anchor) { return interval }

        let start = calendar.startOfDay(for: anchor)
        let days = period == .daily ? 1 : (period == .weekly ? 7 : 30)
        let end = calendar.date(byAdding: .day, value: days, to: start)
            ?? start.addingTimeInterval(Double(days) * 86_400)
        return DateInterval(start: start, end: end)
    }

    static func starts(
        for period: StoredActivityPeriod,
        windowMode: PeriodWindowMode,
        anchor: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let start = interval(for: period, windowMode: windowMode, anchor: anchor, calendar: calendar).start
        let count = cellCount(for: period)
        return (0..<count).map { index in
            if windowMode == .rolling {
                let seconds = period == .daily ? 7_200 : (period == .weekly ? 86_400 : 7 * 86_400)
                return start.addingTimeInterval(Double(index * seconds))
            }
            if period == .daily {
                return calendar.date(bySettingHour: index * 2, minute: 0, second: 0, of: start)
                    ?? start.addingTimeInterval(Double(index) * 7_200)
            }
            let days = period == .weekly ? index : index * 7
            return calendar.date(byAdding: .day, value: days, to: start)
                ?? start.addingTimeInterval(Double(days) * 86_400)
        }
    }
}

enum ActivityLoadState: String, Codable, Sendable {
    case setupRequired
    case loading
    case loaded
    case noActivity
    case error
}

struct RepositoryActivity: Identifiable, Hashable, Codable, Sendable {
    let name: String
    let commits: Int
    let additions: Int
    let deletions: Int

    var id: String { name }
    var totalChanged: Int { additions + deletions }
}

struct ActivityCell: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let additions: Int
    let deletions: Int

    var totalChanged: Int { additions + deletions }
}

struct ActivitySnapshot: Hashable, Codable, Sendable {
    let additions: Int
    let deletions: Int
    let commits: Int
    let repositories: [RepositoryActivity]
    let activity: [ActivityCell]
    let updatedAt: Date
    let state: ActivityLoadState
    let errorMessage: String?

    static func empty(
        for period: StoredActivityPeriod,
        state: ActivityLoadState,
        updatedAt: Date = .now,
        errorMessage: String? = nil
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            additions: 0, deletions: 0, commits: 0, repositories: [],
            activity: (0..<ActivityBucketLayout.cellCount(for: period)).map {
                ActivityCell(id: $0, additions: 0, deletions: 0)
            },
            updatedAt: updatedAt, state: state, errorMessage: errorMessage
        )
    }

    init(
        additions: Int,
        deletions: Int,
        commits: Int,
        repositories: [RepositoryActivity],
        activity: [ActivityCell],
        updatedAt: Date,
        state: ActivityLoadState = .loaded,
        errorMessage: String? = nil
    ) {
        self.additions = additions
        self.deletions = deletions
        self.commits = commits
        self.repositories = repositories.sorted {
            if $0.totalChanged != $1.totalChanged {
                return $0.totalChanged > $1.totalChanged
            }
            if $0.commits != $1.commits {
                return $0.commits > $1.commits
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        self.activity = activity
        self.updatedAt = updatedAt
        self.state = state
        self.errorMessage = errorMessage
    }

    func visibleRepositories(limit: Int) -> ArraySlice<RepositoryActivity> {
        repositories.prefix(limit)
    }

    func hiddenRepositoryCount(limit: Int) -> Int {
        max(0, repositories.count - limit)
    }

    var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > 60 * 60
    }

    func markingRefreshError(_ message: String) -> ActivitySnapshot {
        ActivitySnapshot(
            additions: additions,
            deletions: deletions,
            commits: commits,
            repositories: repositories,
            activity: activity,
            updatedAt: updatedAt,
            state: .error,
            errorMessage: message
        )
    }
}

enum ActivityNumberFormat {
    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func exact(_ value: Int, sign: Character) -> String {
        let formatted = groupedFormatter.string(from: NSNumber(value: abs(value))) ?? String(abs(value))
        return "\(sign)\(formatted)"
    }

    static func compact(_ value: Int, sign: Character) -> String {
        let magnitude = Double(abs(value))
        let suffix: String
        let scaled: Double

        switch magnitude {
        case 1_000_000...:
            suffix = "M"
            scaled = magnitude / 1_000_000
        case 1_000...:
            suffix = "k"
            scaled = magnitude / 1_000
        default:
            return exact(value, sign: sign)
        }

        let decimals = scaled < 10 && scaled.rounded() != scaled ? 1 : 0
        return "\(sign)\(scaled.formatted(.number.precision(.fractionLength(decimals))))\(suffix)"
    }
}
