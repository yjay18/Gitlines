import SwiftUI
import WidgetKit

// Derived metrics shared by the fixed themes so each view reuses one derivation
// instead of recomputing net / average / peak inline.
extension ActivitySnapshot {
    var net: Int { additions - deletions }

    var averagePerCommit: Int {
        guard commits > 0 else { return 0 }
        return Int((Double(additions + deletions) / Double(commits)).rounded())
    }

    var activeIntervals: Int {
        activity.filter { $0.totalChanged > 0 }.count
    }

    var peakIndex: Int? {
        activity.enumerated().max { $0.element.totalChanged < $1.element.totalChanged }?.offset
    }

    // The quantity one snek block counts, per the chosen basis.
    func snakeUnits(_ basis: SnakeBlockBasis) -> Int {
        switch basis {
        case .commits: commits
        case .additions: additions
        case .deletions: deletions
        case .net: abs(net)
        }
    }
}

extension ActivityEntry {
    // Weekday / hour labels for this entry's period, aligned to the activity cells.
    func intervalLabels(style: ActivityIntervalLabelStyle = .compact) -> [String] {
        ActivityIntervalLabels.labels(
            period: period,
            windowMode: preferences.periodWindowMode,
            referenceDate: date,
            cellCount: snapshot.activity.count,
            style: style
        )
    }

    var peakLabel: String {
        guard let index = snapshot.peakIndex else { return "—" }
        let labels = intervalLabels()
        return labels.indices.contains(index) ? labels[index] : "—"
    }

    var rhythmCaption: String { period.rhythmCaption }

    // Title for the per-interval ledger (Broadsheet's day book).
    var ledgerCaption: String {
        period == .monthly ? "The week book" : "The day book"
    }

    var spanLabel: String { period.spanLabel(windowMode: preferences.periodWindowMode) }
}

// Shared period phrasing for widgets and the host dashboard.
extension ActivityPeriod {
    // Period-aware caption for the activity chart, so a monthly view doesn't read
    // "seven day rhythm" over week buckets.
    var rhythmCaption: String {
        switch self {
        case .daily: "hourly rhythm"
        case .weekly: "seven day rhythm"
        case .monthly: "weekly rhythm"
        }
    }

    // Human phrase for the active window, e.g. "this month" or "last 30 days".
    func spanLabel(windowMode: PeriodWindowMode) -> String {
        switch (self, windowMode) {
        case (.daily, .fixed): "today"
        case (.daily, .rolling): "last 24 hours"
        case (.weekly, .fixed): "this week"
        case (.weekly, .rolling): "last 7 days"
        case (.monthly, .fixed): "this month"
        case (.monthly, .rolling): "last 30 days"
        }
    }
}

// The commit-snek pet, themeable so any fixed theme can drop it into the roomy
// large / extra-large layouts. Length tracks commits with the same block formula
// the Blockwork snek pane uses. Wrap it in a `.frame(maxHeight: .infinity)` to fill
// leftover vertical space.
struct CommitPetView: View {
    let units: Int
    let perBlock: Int
    let unitNoun: String
    let commits: Int
    let net: Int
    let bodyColor: Color
    let headColor: Color
    let foodColor: Color
    let trackColor: Color
    let textColor: Color
    var mono: Bool = false
    var caption: String? = nil
    var rows: Int = 1

    private var segments: Int {
        CommitSnakeLimits.blocks(units: units, per: perBlock, cap: CommitSnakeLimits.visualBlockCount)
    }

    private var perRow: Int {
        (CommitSnakeLimits.visualBlockCount + rows - 1) / rows
    }

    private var mood: String {
        if commits == 0 { "asleep" }
        else if segments >= 16 { "stuffed" }
        else if net < 0 { "slimming" }
        else { "happy" }
    }

    private var design: Font.Design { mono ? .monospaced : .rounded }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            HStack {
                Text(caption ?? "snek \(mood)")
                    .font(.system(size: 11, weight: .semibold, design: design)).foregroundStyle(textColor)
                Spacer()
                Text("\(commits) commits")
                    .font(.system(size: 9, weight: .medium, design: design)).foregroundStyle(textColor.opacity(0.6))
            }
            VStack(spacing: 3) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<perRow, id: \.self) { column in
                            cellView(index: row * perRow + column)
                        }
                    }
                }
            }
            Text("1 block = \(perBlock) \(unitNoun)")
                .font(.system(size: 8, weight: .medium, design: design)).foregroundStyle(textColor.opacity(0.5))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func cellView(index: Int) -> some View {
        let fill = index < CommitSnakeLimits.visualBlockCount ? cell(index) : Color.clear
        let isHead = segments > 0 && index == segments - 1
        let base = RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fill)
            .overlay { if isHead { headEye } }
        if rows == 1 {
            base.frame(height: 12).frame(maxWidth: .infinity)
        } else {
            base.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
        }
    }

    // Two dark eyes so the head clearly reads as a face, not just a brighter block.
    private var headEye: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let d = max(2, s * 0.3)
            HStack(spacing: d * 0.7) {
                Circle().fill(Color.black.opacity(0.72)).frame(width: d, height: d)
                Circle().fill(Color.black.opacity(0.72)).frame(width: d, height: d)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    private func cell(_ index: Int) -> Color {
        if index == segments && segments < CommitSnakeLimits.visualBlockCount { return foodColor }
        if index == segments - 1 { return headColor }
        if index < segments { return bodyColor }
        return trackColor
    }
}

extension WidgetVisualTheme {
    // Base colour painted behind the widget content and into the bleed margin.
    var containerBackgroundColor: Color {
        switch self {
        case .defaultTheme: Color(red: 0.035, green: 0.047, blue: 0.063)
        case .blockwork: Color(red: 0.937, green: 0.898, blue: 0.804)
        case .glasshouse: Color(red: 0.110, green: 0.114, blue: 0.129)
        case .phosphor: Color(red: 0.024, green: 0.035, blue: 0.039)
        case .broadsheet: Color(red: 0.914, green: 0.894, blue: 0.835)
        case .arcade: Color(red: 0.059, green: 0.220, blue: 0.059)
        }
    }
}
