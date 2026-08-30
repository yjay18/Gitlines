import SwiftUI

enum ActivityIntervalLabelStyle {
    case expanded
    case compact
}

enum ActivityIntervalLabels {
    static func labels(
        period: ActivityPeriod,
        windowMode: PeriodWindowMode,
        referenceDate: Date,
        cellCount: Int,
        style: ActivityIntervalLabelStyle,
        calendar: Calendar = .current
    ) -> [String] {
        guard cellCount > 0 else { return [] }

        let interval = interval(
            period: period,
            windowMode: windowMode,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let cellDuration = interval.duration / Double(cellCount)

        return (0..<cellCount).map { index in
            let start = interval.start.addingTimeInterval(cellDuration * Double(index))
            let end = interval.start.addingTimeInterval(cellDuration * Double(index + 1))

            switch period {
            case .daily:
                return hourLabel(start: start, end: end, style: style, calendar: calendar)
            case .weekly:
                return weekdayLabel(start, style: style)
            case .monthly:
                return weekLabel(index: index, style: style)
            }
        }
    }

    private static func interval(
        period: ActivityPeriod,
        windowMode: PeriodWindowMode,
        referenceDate: Date,
        calendar: Calendar
    ) -> DateInterval {
        switch (period, windowMode) {
        case (.daily, .fixed):
            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)
                ?? start.addingTimeInterval(24 * 60 * 60)
            return DateInterval(start: start, end: end)
        case (.weekly, .fixed):
            let start = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
                ?? calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 7, to: start)
                ?? start.addingTimeInterval(7 * 24 * 60 * 60)
            return DateInterval(start: start, end: end)
        case (.daily, .rolling):
            return DateInterval(
                start: referenceDate.addingTimeInterval(-24 * 60 * 60),
                end: referenceDate
            )
        case (.weekly, .rolling):
            return DateInterval(
                start: referenceDate.addingTimeInterval(-7 * 24 * 60 * 60),
                end: referenceDate
            )
        case (.monthly, .fixed):
            let start = calendar.dateInterval(of: .month, for: referenceDate)?.start
                ?? calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .month, value: 1, to: start)
                ?? start.addingTimeInterval(30 * 24 * 60 * 60)
            return DateInterval(start: start, end: end)
        case (.monthly, .rolling):
            return DateInterval(
                start: referenceDate.addingTimeInterval(-30 * 24 * 60 * 60),
                end: referenceDate
            )
        }
    }

    private static func hourLabel(
        start: Date,
        end: Date,
        style: ActivityIntervalLabelStyle,
        calendar: Calendar
    ) -> String {
        let startHour = calendar.component(.hour, from: start)
        if case .compact = style {
            return startHour.formatted(.number.grouping(.never).precision(.integerLength(2)))
        }

        let endHour = calendar.component(.hour, from: end)
        let startText = startHour.formatted(.number.grouping(.never).precision(.integerLength(2)))
        let endText = endHour.formatted(.number.grouping(.never).precision(.integerLength(2)))
        return "\(startText)–\(endText)"
    }

    private static func weekdayLabel(_ date: Date, style: ActivityIntervalLabelStyle) -> String {
        switch style {
        case .expanded:
            date.formatted(.dateTime.weekday(.abbreviated))
        case .compact:
            date.formatted(.dateTime.weekday(.narrow))
        }
    }

    private static func weekLabel(index: Int, style: ActivityIntervalLabelStyle) -> String {
        switch style {
        case .expanded: "Week \(index + 1)"
        case .compact: "W\(index + 1)"
        }
    }
}

struct ActivityAxisLabels: View {
    let labels: [String]
    var fontSize: CGFloat = 7
    var color = WidtgetPalette.secondaryText

    var body: some View {
        HStack(spacing: 2) {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index])
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ActivityInsights: View {
    let snapshot: ActivitySnapshot
    let labels: [String]
    var compact = false

    private var totalChanged: Int {
        snapshot.additions + snapshot.deletions
    }

    private var netChanged: Int {
        snapshot.additions - snapshot.deletions
    }

    private var averagePerCommit: Int {
        guard snapshot.commits > 0 else { return 0 }
        return Int((Double(totalChanged) / Double(snapshot.commits)).rounded())
    }

    private var peak: (index: Int, cell: ActivityCell)? {
        guard let peak = snapshot.activity.enumerated().max(by: {
            $0.element.totalChanged < $1.element.totalChanged
        }) else { return nil }
        return (index: peak.offset, cell: peak.element)
    }

    private var peakLabel: String {
        guard let peak, peak.cell.totalChanged > 0, labels.indices.contains(peak.index) else {
            return "—"
        }
        return labels[peak.index].uppercased()
    }

    private var peakChanged: Int {
        peak?.cell.totalChanged ?? 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 10) {
            insight(
                title: "NET",
                value: signedCompact(netChanged),
                detail: "LINES",
                color: netColor
            )

            separator

            insight(
                title: "PEAK",
                value: peakLabel,
                detail: peakChanged == 0 ? "NO ACTIVITY" : "\(unsignedCompact(peakChanged)) LINES",
                color: WidtgetPalette.ink
            )

            separator

            insight(
                title: "AVG",
                value: unsignedCompact(averagePerCommit),
                detail: "LINES / COMMIT",
                color: WidtgetPalette.ink
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Net \(netChanged) lines, peak interval \(peakLabel), average \(averagePerCommit) lines per commit"
        )
    }

    private func insight(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            Text(title)
                .font(.system(size: compact ? 6.5 : 7.5, weight: .black, design: .monospaced))
                .tracking(compact ? 0.7 : 0.9)
                .foregroundStyle(WidtgetPalette.ink.opacity(0.62))

            Text(value)
                .font(.system(size: compact ? 12 : 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(.system(size: compact ? 5.5 : 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(WidtgetPalette.ink.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separator: some View {
        Rectangle()
            .fill(WidtgetPalette.ink.opacity(0.72))
            .frame(width: 1, height: compact ? 35 : 42)
    }

    private var netColor: Color {
        if netChanged > 0 { return WidtgetPalette.ink }
        if netChanged < 0 { return WidtgetPalette.orange }
        return WidtgetPalette.ink.opacity(0.62)
    }

    private func signedCompact(_ value: Int) -> String {
        ActivityNumberFormat.compact(value, sign: value < 0 ? "−" : "+")
    }

    private func unsignedCompact(_ value: Int) -> String {
        String(ActivityNumberFormat.compact(value, sign: "+").dropFirst())
    }
}

private enum CommitSnakeMood {
    case sleeping
    case hatched
    case growing
    case thriving
    case setupRequired
    case loading
    case worried

    init(snapshot: ActivitySnapshot) {
        switch snapshot.state {
        case .error:
            self = .worried
        case .setupRequired:
            self = .setupRequired
        case .loading:
            self = .loading
        case .loaded, .noActivity:
            switch snapshot.commits {
            case 0:
                self = .sleeping
            case 1..<5:
                self = .hatched
            case 5..<15:
                self = .growing
            default:
                self = .thriving
            }
        }
    }

    var title: String {
        switch self {
        case .sleeping, .hatched, .setupRequired, .loading, .worried: "smol snek"
        case .growing: "growing snek"
        case .thriving: "snek happy"
        }
    }

    var accent: Color {
        switch self {
        case .worried: WidtgetPalette.coral
        case .sleeping, .setupRequired, .loading: WidtgetPalette.secondaryText
        case .hatched, .growing, .thriving: WidtgetPalette.green
        }
    }
}

struct CommitSnakeView: View {
    let snapshot: ActivitySnapshot
    let commitsPerBlock: Int
    var basis: SnakeBlockBasis = .commits
    var expanded = false

    private var mood: CommitSnakeMood {
        CommitSnakeMood(snapshot: snapshot)
    }

    private var bodySegments: Int {
        CommitSnakeLimits.blocks(
            units: snapshot.snakeUnits(basis),
            per: commitsPerBlock,
            cap: CommitSnakeLimits.visualBlockCount
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CommitSnakeBackdrop(accent: mood.accent)

                if expanded {
                    expandedContent(size: proxy.size)
                } else {
                    HStack(spacing: 8) {
                        snake

                        VStack(alignment: .leading) {
                            Text(mood.title)
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(WidtgetPalette.paper)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mood.title), based on \(snapshot.commits) commits.")
    }

    @ViewBuilder
    private func expandedContent(size: CGSize) -> some View {
        if size.width > size.height * 1.65 {
            HStack(spacing: 14) {
                snake
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                snakeDetails
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                snake
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                snakeDetails
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
        }
    }

    private var snake: some View {
        BlockyCommitSnake(
            mood: mood,
            bodySegments: bodySegments,
            maximumSegments: CommitSnakeLimits.visualBlockCount
        )
    }

    private var snakeDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mood.title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(WidtgetPalette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("\(snapshot.commits) COMMITS")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(mood.accent)

            HStack(spacing: 7) {
                Text("\(bodySegments)/\(CommitSnakeLimits.visualBlockCount) BLOCKS")
                Text("1 = \(commitsPerBlock) \(basis.unitNoun.uppercased())")
            }
            .font(.system(size: 5.8, weight: .black, design: .monospaced))
            .foregroundStyle(WidtgetPalette.paper.opacity(0.58))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
    }
}

private struct CommitSnakeBackdrop: View {
    let accent: Color

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let stars: [(CGFloat, CGFloat)] = [
                (0.05, 0.20), (0.42, 0.12), (0.93, 0.28), (0.72, 0.83)
            ]
            for (index, star) in stars.enumerated() {
                let center = CGPoint(x: size.width * star.0, y: size.height * star.1)
                let color = index.isMultiple(of: 2)
                    ? accent.opacity(0.45)
                    : WidtgetPalette.coral.opacity(0.48)
                let vertical = CGRect(x: center.x - 0.5, y: center.y - 2, width: 1, height: 4)
                let horizontal = CGRect(x: center.x - 2, y: center.y - 0.5, width: 4, height: 1)
                context.fill(Path(vertical), with: .color(color))
                context.fill(Path(horizontal), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BlockyCommitSnake: View {
    let mood: CommitSnakeMood
    let bodySegments: Int
    let maximumSegments: Int

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let maximumSlots = max(maximumSegments + 1, 2)
            let columns = min(10, max(5, Int(ceil(Double(maximumSlots) / 3))))
            let rows = Int(ceil(Double(maximumSlots) / Double(columns)))
            let horizontalGap: CGFloat = 1.4
            let verticalGap: CGFloat = 5
            let inset: CGFloat = 5
            let availableWidth = max(1, size.width - inset * 2)
            let availableHeight = max(1, size.height - inset * 2)
            let block = max(
                3,
                floor(min(
                    (availableWidth - CGFloat(columns - 1) * horizontalGap) / CGFloat(columns),
                    (availableHeight - CGFloat(rows - 1) * verticalGap) / CGFloat(rows)
                ))
            )
            let gridWidth = CGFloat(columns) * block + CGFloat(columns - 1) * horizontalGap
            let gridHeight = CGFloat(rows) * block + CGFloat(rows - 1) * verticalGap
            let origin = CGPoint(
                x: (size.width - gridWidth) / 2,
                y: (size.height - gridHeight) / 2
            )

            func frame(for index: Int) -> CGRect {
                let row = index / columns
                let offset = index % columns
                let column = row.isMultiple(of: 2) ? offset : columns - 1 - offset
                return CGRect(
                    x: origin.x + CGFloat(column) * (block + horizontalGap),
                    y: origin.y + CGFloat(rows - 1 - row) * (block + verticalGap),
                    width: block,
                    height: block
                )
            }

            for index in 0..<maximumSlots {
                let slot = frame(for: index)
                context.fill(
                    Path(roundedRect: slot, cornerRadius: 2),
                    with: .color(WidtgetPalette.neutral.opacity(0.58))
                )
            }

            if bodySegments > 0 {
                for index in 1...bodySegments {
                    let previous = frame(for: index - 1)
                    let current = frame(for: index)
                    let connector: CGRect
                    if abs(previous.midY - current.midY) < 1 {
                        connector = CGRect(
                            x: min(previous.maxX, current.maxX) - horizontalGap,
                            y: previous.midY - max(1, block * 0.22),
                            width: horizontalGap * 2,
                            height: max(2, block * 0.44)
                        )
                    } else {
                        connector = CGRect(
                            x: previous.midX - max(1, block * 0.22),
                            y: min(previous.midY, current.midY),
                            width: max(2, block * 0.44),
                            height: abs(previous.midY - current.midY)
                        )
                    }
                    context.fill(Path(connector), with: .color(bodyColor(index: index - 1)))
                }
            }

            for index in 0..<bodySegments {
                let segment = frame(for: index)
                let isMilestone = (index + 1).isMultiple(of: 5)
                let color = isMilestone ? WidtgetPalette.coral.opacity(0.88) : bodyColor(index: index)
                context.fill(Path(roundedRect: segment, cornerRadius: 2), with: .color(color))
            }

            let headIndex = min(bodySegments, maximumSlots - 1)
            let head = frame(for: headIndex)
            context.fill(Path(roundedRect: head, cornerRadius: 3), with: .color(mood.accent))

            let row = headIndex / columns
            let offset = headIndex % columns
            let facingUp = row > 0 && offset == 0
            let eyeSize = max(1.2, block * 0.13)
            let sleeping = mood == .sleeping
            let eyeColor = Color.black.opacity(0.72)

            let eyeRects: [CGRect]
            if facingUp {
                eyeRects = [0.27, 0.68].map { fraction in
                    CGRect(
                        x: head.minX + block * fraction - eyeSize / 2,
                        y: head.minY + block * 0.22,
                        width: eyeSize,
                        height: sleeping ? 1 : eyeSize
                    )
                }
            } else {
                let facingRight = row.isMultiple(of: 2)
                let x = facingRight ? head.maxX - block * 0.28 : head.minX + block * 0.18
                eyeRects = [0.28, 0.69].map { fraction in
                    CGRect(
                        x: x,
                        y: head.minY + block * fraction - eyeSize / 2,
                        width: eyeSize,
                        height: sleeping ? 1 : eyeSize
                    )
                }
            }
            for eye in eyeRects {
                context.fill(Path(roundedRect: eye, cornerRadius: 0.7), with: .color(eyeColor))
            }

            if mood != .sleeping && mood != .loading && mood != .setupRequired {
                let tongue: CGRect
                if facingUp {
                    tongue = CGRect(
                        x: head.midX - 0.7,
                        y: head.minY - 3,
                        width: 1.4,
                        height: 4
                    )
                } else if row.isMultiple(of: 2) {
                    tongue = CGRect(
                        x: head.maxX - 1,
                        y: head.midY - 0.7,
                        width: 4,
                        height: 1.4
                    )
                } else {
                    tongue = CGRect(
                        x: head.minX - 3,
                        y: head.midY - 0.7,
                        width: 4,
                        height: 1.4
                    )
                }
                context.fill(Path(tongue), with: .color(WidtgetPalette.coral))
            }
        }
        .accessibilityHidden(true)
    }

    private func bodyColor(index: Int) -> Color {
        switch mood {
        case .sleeping, .setupRequired, .loading:
            WidtgetPalette.secondaryText.opacity(0.54 + min(Double(index) * 0.025, 0.2))
        case .worried:
            WidtgetPalette.coral.opacity(0.62 + min(Double(index) * 0.018, 0.24))
        case .hatched, .growing, .thriving:
            WidtgetPalette.green.opacity(0.58 + min(Double(index) * 0.018, 0.34))
        }
    }
}

struct ActivityStrip: View {
    let cells: [ActivityCell]
    var height: CGFloat = 12
    var additionColor = WidtgetPalette.ink
    var deletionColor = WidtgetPalette.orange
    var neutralColor = WidtgetPalette.neutral

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            guard !cells.isEmpty, size.width > 0, size.height > 0 else { return }

            let maximum = CGFloat(max(cells.map(\.totalChanged).max() ?? 0, 1))
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(max(cells.count - 1, 0))
            let barWidth = max(1, (size.width - totalSpacing) / CGFloat(cells.count))

            for (index, cell) in cells.enumerated() {
                let x = CGFloat(index) * (barWidth + spacing)

                if cell.totalChanged == 0 {
                    let baseline = CGRect(
                        x: x,
                        y: max(0, size.height - 3),
                        width: barWidth,
                        height: min(3, size.height)
                    )
                    context.fill(
                        Path(baseline),
                        with: .color(neutralColor)
                    )
                    continue
                }

                let intensity = min(1, CGFloat(cell.totalChanged) / maximum)
                let totalHeight = min(size.height, max(3, size.height * intensity))
                let hasAdditions = cell.additions > 0
                let hasDeletions = cell.deletions > 0
                let segmentSpacing: CGFloat = hasAdditions && hasDeletions ? 1 : 0
                let drawableHeight = max(0, totalHeight - segmentSpacing)
                let additionShare = CGFloat(cell.additions) / CGFloat(cell.totalChanged)
                let additionHeight = hasAdditions ? drawableHeight * additionShare : 0
                let deletionHeight = hasDeletions ? drawableHeight - additionHeight : 0
                let opacity = 0.5 + 0.5 * Double(intensity)
                var bottom = size.height

                if hasDeletions {
                    let deletionRect = CGRect(
                        x: x,
                        y: bottom - deletionHeight,
                        width: barWidth,
                        height: deletionHeight
                    )
                    context.fill(
                        Path(deletionRect),
                        with: .color(deletionColor.opacity(max(0.55, opacity)))
                    )
                    bottom -= deletionHeight + segmentSpacing
                }

                if hasAdditions {
                    let additionRect = CGRect(
                        x: x,
                        y: bottom - additionHeight,
                        width: barWidth,
                        height: additionHeight
                    )
                    context.fill(
                        Path(additionRect),
                        with: .color(additionColor.opacity(max(0.52, opacity)))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity intensity for \(cells.count) intervals")
    }
}

struct ActivityGrid: View {
    let cells: [ActivityCell]
    var labels: [String] = []
    var labelFontSize: CGFloat = 6.5
    var additionColor = WidtgetPalette.ink
    var deletionColor = WidtgetPalette.orange
    var neutralColor = WidtgetPalette.neutral
    var labelColor = WidtgetPalette.secondaryText

    private var columns: [GridItem] {
        let columnCount = max(1, min(cells.count, 7))
        return Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount)
    }

    private var maximum: Double {
        Double(max(cells.map(\.totalChanged).max() ?? 0, 1))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                let intensity = Double(cell.totalChanged) / maximum
                let additionShare = cell.totalChanged == 0 ? 0 : Double(cell.additions) / Double(cell.totalChanged)

                VStack(spacing: labels.indices.contains(index) ? 3 : 0) {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            additionColor
                                .opacity(cell.totalChanged == 0 ? 0 : 0.25 + intensity * 0.75)
                                .frame(width: proxy.size.width * additionShare)
                            deletionColor
                                .opacity(cell.totalChanged == 0 ? 0 : 0.22 + intensity * 0.68)
                        }
                        .background(neutralColor)
                        .overlay {
                            if cell.totalChanged > 0 && Double(cell.totalChanged) == maximum {
                                Rectangle()
                                    .stroke(WidtgetPalette.ink.opacity(0.72), lineWidth: 1)
                            }
                        }
                    }
                    .aspectRatio(1.7, contentMode: .fit)

                    if labels.indices.contains(index) {
                        Text(labels[index])
                            .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(labelColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityLabel("\(cell.additions) additions, \(cell.deletions) deletions")
            }
        }
    }
}
