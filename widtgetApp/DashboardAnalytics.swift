import Foundation

struct DashboardAnalytics {
    struct PeakInterval {
        let index: Int
        let label: String
        let changed: Int
    }

    struct Review {
        enum Tone {
            case green
            case coral
            case neutral
        }

        struct Note: Identifiable {
            let id: String
            let label: String
            let value: String
            let detail: String
            let tone: Tone
        }

        let eyebrow: String
        let title: String
        let summary: String
        let notes: [Note]
    }

    let snapshot: ActivitySnapshot
    let period: ActivityPeriod
    let windowMode: PeriodWindowMode

    var totalChanged: Int {
        snapshot.additions + snapshot.deletions
    }

    var netChanged: Int {
        snapshot.additions - snapshot.deletions
    }

    var averagePerCommit: Int {
        guard snapshot.commits > 0 else { return 0 }
        return Int((Double(totalChanged) / Double(snapshot.commits)).rounded())
    }

    var deletionShare: Double {
        guard totalChanged > 0 else { return 0 }
        return Double(snapshot.deletions) / Double(totalChanged)
    }

    var activeIntervals: Int {
        snapshot.activity.filter { $0.totalChanged > 0 }.count
    }

    var maximumActivity: Int {
        max(snapshot.activity.map(\.totalChanged).max() ?? 0, 1)
    }

    var leadingRepository: RepositoryActivity? {
        snapshot.repositories.first
    }

    var leadingRepositoryShare: Double {
        guard let leadingRepository, totalChanged > 0 else { return 0 }
        return Double(leadingRepository.totalChanged) / Double(totalChanged)
    }

    var peak: PeakInterval? {
        guard let result = snapshot.activity.enumerated().max(by: {
            $0.element.totalChanged < $1.element.totalChanged
        }), result.element.totalChanged > 0 else { return nil }

        return PeakInterval(
            index: result.offset,
            label: intervalLabels.indices.contains(result.offset)
                ? intervalLabels[result.offset]
                : "Interval \(result.offset + 1)",
            changed: result.element.totalChanged
        )
    }

    // Full labels ("Mon", "Week 2", "08–10") for peaks and compact ones ("M", "W2",
    // "08") for chart axes, from the same helper every widget theme uses.
    var intervalLabels: [String] { labels(style: .expanded) }
    var axisLabels: [String] { labels(style: .compact) }

    private func labels(style: ActivityIntervalLabelStyle) -> [String] {
        ActivityIntervalLabels.labels(
            period: period,
            windowMode: windowMode,
            referenceDate: snapshot.updatedAt,
            cellCount: snapshot.activity.count,
            style: style
        )
    }

    // "today", "this week", "last 30 days" — matches the widgets' span phrasing.
    var spanLabel: String {
        period.spanLabel(windowMode: windowMode)
    }

    // "day" / "week" / "month" for prose; period.rawValue is the adjective.
    private var periodNoun: String {
        switch period {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        }
    }

    private var eyebrowPrefix: String {
        "\(period.displayName) REVIEW"
    }

    var review: Review {
        switch snapshot.state {
        case .setupRequired:
            return Review(
                eyebrow: "\(eyebrowPrefix) · WAITING",
                title: "Connect GitHub to begin the story.",
                summary: "Once connected, widtget will turn the saved \(period.rawValue) snapshot into a concise, deterministic review.",
                notes: []
            )
        case .loading:
            return Review(
                eyebrow: "\(eyebrowPrefix) · FETCHING",
                title: "The \(periodNoun) is being assembled.",
                summary: "Repository totals and activity rhythm will appear after the current refresh finishes.",
                notes: []
            )
        case .error:
            return Review(
                eyebrow: "\(eyebrowPrefix) · CACHED",
                title: "The last saved \(periodNoun) is still here.",
                summary: snapshot.errorMessage ?? "The latest refresh failed, so these analytics may be stale.",
                notes: loadedNotes
            )
        case .noActivity:
            return Review(
                eyebrow: "\(eyebrowPrefix) · QUIET",
                title: "A quiet \(periodNoun) in the selected window.",
                summary: "No commits were found across the connected repositories. The dashboard will keep the window ready for the next refresh.",
                notes: []
            )
        case .loaded:
            return Review(
                eyebrow: "\(eyebrowPrefix) · \(windowMode == .fixed ? "CALENDAR" : "ROLLING")",
                title: loadedTitle,
                summary: loadedSummary,
                notes: loadedNotes
            )
        }
    }

    // Two-thirds of the intervals active reads as steady (5 of 7 for a week).
    private var steadyThreshold: Int {
        max((snapshot.activity.count * 2 + 2) / 3, 1)
    }

    private var loadedTitle: String {
        if snapshot.commits >= 50 && activeIntervals >= steadyThreshold {
            return "A high-motion \(periodNoun) with a steady pulse."
        }
        if snapshot.repositories.count == 1, let repository = leadingRepository {
            return "\(repository.name) held the whole \(periodNoun)."
        }
        if activeIntervals >= steadyThreshold {
            return "A steady \(period.rhythmCaption)."
        }
        if leadingRepositoryShare >= 0.7, let repository = leadingRepository {
            return "The \(periodNoun) converged on \(repository.name)."
        }
        return "A concentrated \(periodNoun) across \(max(snapshot.repositories.count, 1)) repositories."
    }

    private var loadedSummary: String {
        let commitWord = snapshot.commits == 1 ? "commit" : "commits"
        let repositoryWord = snapshot.repositories.count == 1 ? "repository" : "repositories"
        let direction: String
        if netChanged > 0 {
            direction = "The net footprint grew by \(compact(netChanged)) lines."
        } else if netChanged < 0 {
            direction = "The net footprint contracted by \(compact(abs(netChanged))) lines."
        } else {
            direction = "Additions and deletions finished in balance."
        }

        return "\(snapshot.commits.formatted()) \(commitWord) moved \(compact(totalChanged)) lines across \(snapshot.repositories.count.formatted()) \(repositoryWord). \(direction)"
    }

    private var loadedNotes: [Review.Note] {
        var notes: [Review.Note] = []

        if let repository = leadingRepository {
            notes.append(
                Review.Note(
                    id: "focus",
                    label: "FOCUS",
                    value: repository.name,
                    detail: "\(percentage(leadingRepositoryShare)) of \(period.rawValue) line movement · \(repository.commits) commits",
                    tone: .green
                )
            )
        }

        if let peak {
            notes.append(
                Review.Note(
                    id: "rhythm",
                    label: "PEAK",
                    value: peak.label,
                    detail: "\(compact(peak.changed)) lines · active in \(activeIntervals)/\(snapshot.activity.count) intervals",
                    tone: .neutral
                )
            )
        }

        let balanceDetail: String
        let balanceTone: Review.Tone
        if deletionShare >= 0.6 {
            balanceDetail = "Deletion-heavy movement; this describes change shape, not code quality."
            balanceTone = .coral
        } else if deletionShare <= 0.25 {
            balanceDetail = "Addition-led movement across the selected \(period.rawValue) window."
            balanceTone = .green
        } else {
            balanceDetail = "Additions and deletions both had a visible share of the \(periodNoun)."
            balanceTone = .neutral
        }
        notes.append(
            Review.Note(
                id: "shape",
                label: "CHANGE SHAPE",
                value: "\(percentage(1 - deletionShare)) add / \(percentage(deletionShare)) delete",
                detail: balanceDetail,
                tone: balanceTone
            )
        )

        return notes
    }

    func compact(_ value: Int) -> String {
        let sign: Character = value < 0 ? "−" : "+"
        return String(ActivityNumberFormat.compact(value, sign: sign).dropFirst())
    }

    func percentage(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}
