import AppIntents
import WidgetKit

enum ActivityPeriod: String, AppEnum, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static let caseDisplayRepresentations: [ActivityPeriod: DisplayRepresentation] = [
        .daily: "Daily",
        .weekly: "Weekly",
        .monthly: "Monthly"
    ]

    var displayName: String { rawValue.uppercased() }

    // The widget's period pill cycles through the three periods in order.
    var toggled: ActivityPeriod {
        switch self {
        case .daily: .weekly
        case .weekly: .monthly
        case .monthly: .daily
        }
    }
}

enum ActivityWidgetFamily: String, AppEnum, CaseIterable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget size")
    static let caseDisplayRepresentations: [ActivityWidgetFamily: DisplayRepresentation] = [
        .small: "Small",
        .medium: "Medium",
        .large: "Large",
        .extraLarge: "Extra Large"
    ]

    init(widgetFamily: WidgetFamily) {
        switch widgetFamily {
        case .systemSmall:
            self = .small
        case .systemMedium:
            self = .medium
        case .systemExtraLarge:
            self = .extraLarge
        default:
            self = .large
        }
    }
}

extension RepositoryDetail: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Repository detail")
    static let caseDisplayRepresentations: [RepositoryDetail: DisplayRepresentation] = [
        .focused: "Focused",
        .expanded: "More rows"
    ]
}

extension PeriodWindowMode: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Activity window")
    static let caseDisplayRepresentations: [PeriodWindowMode: DisplayRepresentation] = [
        .fixed: "Calendar",
        .rolling: "Rolling"
    ]
}

struct WidtgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Activity period"
    static let description = IntentDescription("Choose daily, weekly, or monthly code activity.")

    @Parameter(title: "Period", default: .daily)
    var period: ActivityPeriod

    @Parameter(title: "Show repositories", default: true)
    var showRepositories: Bool

    @Parameter(title: "Show activity", default: true)
    var showActivity: Bool

    @Parameter(title: "Show update time", default: true)
    var showUpdateTime: Bool

    @Parameter(title: "Repository detail", default: .expanded)
    var repositoryDetail: RepositoryDetail

    init() {
        period = .daily
        showRepositories = true
        showActivity = true
        showUpdateTime = true
        repositoryDetail = .expanded
    }

    init(period: ActivityPeriod) {
        self.init()
        self.period = period
    }
}

struct SetActivityPeriodIntent: AppIntent {
    static let title: LocalizedStringResource = "Change activity period"
    static let description = IntentDescription("Switch a Gitlines widget between daily, weekly, and monthly GitHub activity.")
    static let openAppWhenRun = false

    @Parameter(title: "Period")
    var period: ActivityPeriod

    @Parameter(title: "Widget size")
    var family: ActivityWidgetFamily

    @Parameter(title: "Configured period")
    var configuredPeriod: ActivityPeriod

    init() {
        period = .daily
        family = .medium
        configuredPeriod = .daily
    }

    init(period: ActivityPeriod, family: ActivityWidgetFamily, configuredPeriod: ActivityPeriod) {
        self.period = period
        self.family = family
        self.configuredPeriod = configuredPeriod
    }

    func perform() async throws -> some IntentResult {
        let key = SharedPreferences.displayedPeriodKey(
            family: family.rawValue,
            configuredPeriod: configuredPeriod.rawValue
        )
        SharedPreferences.defaults.set(period.rawValue, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: WidtgetWidgetKind.value)
        return .result()
    }
}
