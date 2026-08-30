import Foundation
import OSLog
import WidgetKit

struct ActivityEntry: TimelineEntry {
    let date: Date
    let configuredPeriod: ActivityPeriod
    let period: ActivityPeriod
    let username: String
    let snapshot: ActivitySnapshot
    var preferences: WidgetViewPreferences = .defaults
}

struct ActivityProvider: AppIntentTimelineProvider {
    typealias Intent = WidtgetConfigurationIntent
    typealias Entry = ActivityEntry

    func placeholder(in context: Context) -> ActivityEntry {
        ActivityEntry(
            date: .now,
            configuredPeriod: .daily,
            period: .daily,
            username: "github",
            snapshot: .loading
        )
    }

    func snapshot(for configuration: WidtgetConfigurationIntent, in context: Context) async -> ActivityEntry {
        entry(for: configuration, context: context, date: .now)
    }

    func timeline(for configuration: WidtgetConfigurationIntent, in context: Context) async -> Timeline<ActivityEntry> {
        let now = Date()
        let entry = entry(for: configuration, context: context, date: now)
        let minutes = SharedPreferences.refreshInterval.minutes
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
            ?? now.addingTimeInterval(TimeInterval(minutes * 60))
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func entry(
        for configuration: WidtgetConfigurationIntent,
        context: Context,
        date: Date
    ) -> ActivityEntry {
        let configuredPeriod = configuration.period
        let family = ActivityWidgetFamily(widgetFamily: context.family)
        let key = SharedPreferences.displayedPeriodKey(
            family: family.rawValue,
            configuredPeriod: configuredPeriod.rawValue
        )
        let period = SharedPreferences.defaults.string(forKey: key)
            .flatMap(ActivityPeriod.init(rawValue:)) ?? configuredPeriod
        let windowMode = SharedPreferences.windowMode
        let content = ActivityDataSource.content(for: period, windowMode: windowMode)
        let modularPreferences = SharedPreferences.modularPreferences
        let layoutFamily = WidgetLayoutFamily(rawValue: family.rawValue) ?? .large
        let resolvedTheme = SharedPreferences.resolvedTheme(for: layoutFamily)

        return ActivityEntry(
            date: date,
            configuredPeriod: configuredPeriod,
            period: period,
            username: content.username,
            snapshot: content.snapshot,
            preferences: WidgetViewPreferences(
                showRepositories: configuration.showRepositories
                    && modularPreferences.enabledPanes.contains(.repositories),
                showActivity: configuration.showActivity
                    && modularPreferences.enabledPanes.contains(.activity),
                showUpdateTime: configuration.showUpdateTime,
                repositoryDetail: configuration.repositoryDetail,
                periodWindowMode: windowMode,
                snakeCommitsPerBlock: SharedPreferences.snekPerBlock(theme: resolvedTheme, family: layoutFamily),
                snakeBlockBasis: SharedPreferences.snekBasis(theme: resolvedTheme, family: layoutFamily),
                paneOrder: modularPreferences.paneOrder,
                enabledPanes: modularPreferences.enabledPanes,
                colorway: modularPreferences.colorway,
                visualTheme: resolvedTheme,
                familyLayouts: modularPreferences.familyLayouts,
                blockColors: modularPreferences.blockColors
            )
        )
    }
}

struct ActivityContent {
    let username: String
    let snapshot: ActivitySnapshot
}

/// The widget reads display-ready snapshots written by the host app. Credentials and GitHub network
/// access intentionally stay out of the extension process.
enum ActivityDataSource {
    private static let logger = Logger(
        subsystem: "com.yjay18.widtget.widget",
        category: "ActivitySnapshotStore"
    )

    static func content(for period: ActivityPeriod, windowMode: PeriodWindowMode) -> ActivityContent {
        do {
            guard let archive = try ActivitySnapshotStore.read() else {
                return ActivityContent(username: "", snapshot: .setupRequired)
            }
            return ActivityContent(
                username: archive.username,
                snapshot: archive.snapshot(for: period.storedPeriod, windowMode: windowMode)
            )
        } catch {
            let nsError = error as NSError
            logger.error(
                "Snapshot read failed: \(nsError.domain, privacy: .public) \(nsError.code) — \(nsError.localizedDescription, privacy: .public)"
            )
            return ActivityContent(
                username: SharedPreferences.defaults.string(
                    forKey: SharedPreferences.Key.githubUsername
                ) ?? "",
                snapshot: ActivitySnapshot(
                    additions: 0,
                    deletions: 0,
                    commits: 0,
                    repositories: [],
                    activity: (0..<7).map { ActivityCell(id: $0, additions: 0, deletions: 0) },
                    updatedAt: .now,
                    state: .error,
                    errorMessage: "Open widtget · \(nsError.code)"
                )
            )
        }
    }
}

extension ActivityPeriod {
    var storedPeriod: StoredActivityPeriod {
        switch self {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        }
    }
}

extension ActivitySnapshot {
    static let setupRequired = ActivitySnapshot(
        additions: 0,
        deletions: 0,
        commits: 0,
        repositories: [],
        activity: (0..<7).map { ActivityCell(id: $0, additions: 0, deletions: 0) },
        updatedAt: .now,
        state: .setupRequired,
        errorMessage: "Connect GitHub"
    )

    static let loading = ActivitySnapshot(
        additions: 0,
        deletions: 0,
        commits: 0,
        repositories: [],
        activity: (0..<14).map { ActivityCell(id: $0, additions: 0, deletions: 0) },
        updatedAt: .now,
        state: .loading
    )

    static let daily = ActivitySnapshot(
        additions: 29_696,
        deletions: 43_332,
        commits: 80,
        repositories: [
            RepositoryActivity(name: "widtget", commits: 72, additions: 29_303, deletions: 39_393),
            RepositoryActivity(name: "pulse-kit", commits: 8, additions: 393, deletions: 3_939)
        ],
        activity: [
            (820, 420), (1_400, 900), (180, 740), (2_900, 1_200), (0, 0), (760, 2_100), (4_200, 1_900),
            (1_100, 3_800), (3_300, 2_100), (580, 900), (5_600, 4_200), (2_200, 7_400), (4_900, 6_500), (1_756, 11_172)
        ].enumerated().map { ActivityCell(id: $0.offset, additions: $0.element.0, deletions: $0.element.1) },
        updatedAt: .now.addingTimeInterval(-8 * 60)
    )

    static let weekly = ActivitySnapshot(
        additions: 118_420,
        deletions: 76_905,
        commits: 214,
        repositories: [
            RepositoryActivity(name: "widtget", commits: 96, additions: 61_204, deletions: 28_440),
            RepositoryActivity(name: "pulse-kit", commits: 52, additions: 25_960, deletions: 31_802),
            RepositoryActivity(name: "swift-tools", commits: 31, additions: 18_070, deletions: 7_100),
            RepositoryActivity(name: "infra-notes", commits: 20, additions: 8_940, deletions: 6_822),
            RepositoryActivity(name: "dotfiles", commits: 9, additions: 3_420, deletions: 2_221),
            RepositoryActivity(name: "tiny-parser", commits: 6, additions: 826, deletions: 520)
        ],
        activity: [
            (12_400, 8_200), (19_720, 4_905), (8_100, 14_200), (24_300, 9_400),
            (16_500, 18_900), (29_600, 13_300), (7_800, 8_000)
        ].enumerated().map { ActivityCell(id: $0.offset, additions: $0.element.0, deletions: $0.element.1) },
        updatedAt: .now.addingTimeInterval(-14 * 60)
    )

    static let noActivity = ActivitySnapshot(
        additions: 0,
        deletions: 0,
        commits: 0,
        repositories: [],
        activity: (0..<7).map { ActivityCell(id: $0, additions: 0, deletions: 0) },
        updatedAt: .now.addingTimeInterval(-4 * 60),
        state: .noActivity
    )

    static let error = ActivitySnapshot(
        additions: 29_696,
        deletions: 43_332,
        commits: 80,
        repositories: daily.repositories,
        activity: daily.activity,
        updatedAt: .now.addingTimeInterval(-2 * 60 * 60),
        state: .error,
        errorMessage: "Couldn’t refresh"
    )
}
