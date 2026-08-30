import SwiftUI

enum DashboardPalette {
    static let ink = Color(red: 0.035, green: 0.047, blue: 0.063)
    static let panel = Color(red: 0.070, green: 0.087, blue: 0.108)
    static let lifted = Color(red: 0.092, green: 0.112, blue: 0.138)
    static let line = Color.white.opacity(0.09)
    static let text = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let muted = Color(red: 0.52, green: 0.57, blue: 0.64)
    static let green = Color(red: 0.22, green: 0.80, blue: 0.46)
    static let coral = Color(red: 0.95, green: 0.38, blue: 0.40)
}

struct AnalyticsDashboardView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var github: GitHubAccountModel
    @Binding var period: ActivityPeriod
    @Binding var windowMode: PeriodWindowMode
    let openConnections: () -> Void

    @State private var revealed = false

    var body: some View {
        ZStack {
            DashboardBackdrop()

            if let archive = github.activityArchive {
                dashboard(archive: archive)
            } else {
                emptyState
            }
        }
        .foregroundStyle(palette.text)
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
                revealed = true
            }
        }
        .onChange(of: github.activityArchive?.savedAt) { _, _ in
            revealed = false
            withAnimation(.spring(response: 0.72, dampingFraction: 0.82).delay(0.05)) {
                revealed = true
            }
        }
        .onChange(of: period) { _, _ in
            revealed = false
            withAnimation(.spring(response: 0.72, dampingFraction: 0.82).delay(0.05)) {
                revealed = true
            }
        }
    }

    private func dashboard(archive: ActivitySnapshotArchive) -> some View {
        let snapshot = archive.snapshot(for: period.storedPeriod, windowMode: windowMode)
        let analytics = DashboardAnalytics(snapshot: snapshot, period: period, windowMode: windowMode)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dashboardHeader(archive: archive)

                HStack(spacing: 12) {
                    NumberCard(
                        label: "COMMITS",
                        value: snapshot.commits,
                        suffix: analytics.spanLabel,
                        color: palette.text,
                        revealed: revealed
                    )
                    NumberCard(
                        label: "LINES IN",
                        value: snapshot.additions,
                        prefix: "+",
                        suffix: "additions",
                        color: palette.green,
                        revealed: revealed
                    )
                    NumberCard(
                        label: "LINES OUT",
                        value: snapshot.deletions,
                        prefix: "−",
                        suffix: "deletions",
                        color: palette.coral,
                        revealed: revealed
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    PulseCard(analytics: analytics, revealed: revealed)
                        .frame(maxWidth: .infinity)
                    ChangeShapeCard(analytics: analytics, revealed: revealed)
                        .frame(width: 220)
                }

                ReviewCard(review: analytics.review, revealed: revealed)

                RepositoryLedgerCard(analytics: analytics, revealed: revealed)
            }
            .padding(24)
        }
    }

    private var spanTitle: String {
        let label = period.spanLabel(windowMode: windowMode)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private func dashboardHeader(archive: ActivitySnapshotArchive) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(period.displayName) SIGNAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(palette.green)

                Text(github.username.isEmpty ? "Your activity" : "@\(github.username)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))

                Text(spanTitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 8) {
                    Picker("Dashboard period", selection: $period) {
                        ForEach(ActivityPeriod.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 168)

                    Picker("Dashboard window", selection: $windowMode) {
                        Text("Calendar").tag(PeriodWindowMode.fixed)
                        Text("Rolling").tag(PeriodWindowMode.rolling)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 132)

                    Button {
                        Task { await github.refresh(scope: .allBranches) }
                    } label: {
                        HStack(spacing: 7) {
                            if github.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(palette.green)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(github.isBusy ? "REFRESHING" : "REFRESH ALL")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(palette.lifted, in: Capsule())
                        .overlay { Capsule().stroke(palette.line, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(github.isBusy)
                }

                Text("Saved \(archive.savedAt, style: .relative)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.muted)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(palette.line, lineWidth: 1)
                    }
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(palette.green)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 7) {
                Text("No signal yet")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                Text("Connect GitHub once. Gitlines will build the dashboard from the same display-ready snapshots used by the widget.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button("OPEN CONNECTIONS", action: openConnections)
                .buttonStyle(DashboardCapsuleButtonStyle(palette: palette))
        }
        .padding(40)
    }
}

struct BlockworkAnalyticsDashboardView: View {
    @ObservedObject var github: GitHubAccountModel
    @Binding var period: ActivityPeriod
    @Binding var windowMode: PeriodWindowMode
    let openConnections: () -> Void

    private let ink = Color(red: 0.063, green: 0.067, blue: 0.059)
    private let paper = Color(red: 0.937, green: 0.898, blue: 0.804)
    private let orange = Color(red: 0.953, green: 0.357, blue: 0.173)
    private let lime = Color(red: 0.725, green: 0.863, blue: 0.235)
    private let sky = Color(red: 0.412, green: 0.729, blue: 0.859)
    private let field = Color(red: 0.62, green: 0.18, blue: 0.32)

    var body: some View {
        Group {
            if let archive = github.activityArchive {
                dashboard(archive)
            } else {
                emptyState
            }
        }
        .background(field)
    }

    private func dashboard(_ archive: ActivitySnapshotArchive) -> some View {
        let snapshot = archive.snapshot(for: period.storedPeriod, windowMode: windowMode)
        let analytics = DashboardAnalytics(snapshot: snapshot, period: period, windowMode: windowMode)

        return ScrollView {
            VStack(spacing: 4) {
                header(archive)

                HStack(spacing: 4) {
                    metricTile("COMMITS", snapshot.commits.formatted(), detail: analytics.spanLabel.uppercased(), fill: lime)
                    metricTile("LINES MADE", ActivityNumberFormat.exact(snapshot.additions, sign: "+"), detail: "ADDITIONS", fill: orange)
                    metricTile("LINES REMOVED", ActivityNumberFormat.exact(snapshot.deletions, sign: "−"), detail: "DELETIONS", fill: ink, light: true)
                }
                .frame(height: 138)

                HStack(alignment: .top, spacing: 4) {
                    activityTile(analytics)
                        .frame(maxWidth: .infinity)
                    reviewTile(analytics.review)
                        .frame(width: 260)
                }

                repositoryTile(snapshot)
            }
            .padding(20)
        }
    }

    private func header(_ archive: ActivitySnapshotArchive) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(period.displayName) OUTPUT / BLOCKWORK")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(orange)
                Text(github.username.isEmpty ? "Your activity" : "@\(github.username)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(-1.2)
            }

            Spacer()

            Picker("Dashboard period", selection: $period) {
                ForEach(ActivityPeriod.allCases, id: \.self) { option in
                    Text(option.rawValue.capitalized).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 168)

            Picker("Dashboard window", selection: $windowMode) {
                Text("Calendar").tag(PeriodWindowMode.fixed)
                Text("Rolling").tag(PeriodWindowMode.rolling)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 132)

            Button {
                Task { await github.refresh(scope: .allBranches) }
            } label: {
                Label(github.isBusy ? "REFRESHING" : "REFRESH", systemImage: "arrow.clockwise")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .foregroundStyle(ink)
                    .background(lime)
            }
            .buttonStyle(.plain)
            .disabled(github.isBusy)

            Text("SAVED \(archive.savedAt, style: .relative)")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(paper.opacity(0.58))
        }
        .padding(18)
        .foregroundStyle(paper)
        .background(ink)
    }

    private func metricTile(
        _ label: String,
        _ value: String,
        detail: String,
        fill: Color,
        light: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.8)
                .opacity(0.7)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 31, weight: .black, design: .rounded))
                .tracking(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .contentTransition(.numericText())
                .foregroundStyle(light ? orange : ink)
            Text(detail)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .opacity(0.62)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(light ? paper : ink)
        .background(fill)
    }

    private func activityTile(_ analytics: DashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                blockLabel("ACTIVITY / \(analytics.snapshot.activity.count) INTERVALS")
                Spacer()
                Text("PEAK · \(analytics.peak?.label.uppercased() ?? "—")")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
            }

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(analytics.snapshot.activity.enumerated()), id: \.element.id) { index, cell in
                    VStack(spacing: 5) {
                        GeometryReader { proxy in
                            let ratio = CGFloat(cell.totalChanged) / CGFloat(analytics.maximumActivity)
                            VStack {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .fill(ink)
                                    .frame(height: max(3, proxy.size.height * ratio))
                            }
                        }
                        Text(analytics.axisLabels.indices.contains(index)
                             ? analytics.axisLabels[index].uppercased()
                             : "\(index + 1)")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 170)

            HStack(spacing: 0) {
                blockStat("\(analytics.activeIntervals)/\(analytics.snapshot.activity.count)", "ACTIVE")
                blockStat(analytics.averagePerCommit.formatted(), "AVG / COMMIT")
                blockStat(
                    ActivityNumberFormat.compact(
                        analytics.netChanged,
                        sign: analytics.netChanged < 0 ? "−" : "+"
                    ),
                    "NET"
                )
            }
            .background(lime)
        }
        .padding(16)
        .foregroundStyle(ink)
        .background(sky)
    }

    private func reviewTile(_ review: DashboardAnalytics.Review) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            blockLabel(review.eyebrow)
            Text(review.title)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .tracking(-0.7)
            Text(review.summary)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineSpacing(3)
                .foregroundStyle(ink.opacity(0.68))
            Spacer(minLength: 0)
            Text("DETERMINISTIC / \(period.displayName)")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .padding(7)
                .background(orange)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(ink)
        .background(paper)
    }

    private func repositoryTile(_ snapshot: ActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                blockLabel("REPOSITORY LEDGER")
                Spacer()
                Text("\(snapshot.repositories.count) TOTAL")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
            }
            .padding(15)
            .background(lime)

            ForEach(snapshot.repositories.prefix(6)) { repository in
                HStack(spacing: 12) {
                    Text(repository.name)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    Spacer()
                    Text("\(repository.commits)c")
                    Text(ActivityNumberFormat.compact(repository.additions, sign: "+"))
                    Text(ActivityNumberFormat.compact(repository.deletions, sign: "−"))
                        .foregroundStyle(orange)
                }
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .padding(.horizontal, 15)
                .frame(height: 38)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ink).frame(height: 2)
                }
            }
        }
        .foregroundStyle(ink)
        .background(paper)
    }

    private func blockStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
            Text(label)
                .font(.system(size: 6.5, weight: .black, design: .monospaced))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(ink).frame(width: 2)
        }
    }

    private func blockLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("NO OUTPUT YET")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1)
            Text("Connect GitHub to assemble the dashboard.")
                .font(.system(size: 27, weight: .black, design: .rounded))
            Button("OPEN CONNECTIONS", action: openConnections)
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(ink)
                .background(lime)
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(paper)
        .background(ink)
    }
}

private struct NumberCard: View {
    @Environment(\.themePalette) private var palette
    let label: String
    let value: Int
    var prefix = ""
    let suffix: String
    let color: Color
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardLabel(label)
            Spacer(minLength: 0)
            Text(revealed ? "\(prefix)\(value.formatted())" : "\(prefix)0")
                .font(.system(size: 31, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .contentTransition(.numericText())
            Text(suffix)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .dashboardSurface()
    }
}

private struct PulseCard: View {
    @Environment(\.themePalette) private var palette
    let analytics: DashboardAnalytics
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                DashboardLabel("ACTIVITY PULSE")
                Spacer()
                if let peak = analytics.peak {
                    Text("PEAK · \(peak.label.uppercased())")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.muted)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(analytics.snapshot.activity.enumerated()), id: \.element.id) { index, cell in
                    VStack(spacing: 7) {
                        GeometryReader { proxy in
                            let totalRatio = CGFloat(cell.totalChanged) / CGFloat(analytics.maximumActivity)
                            let additionRatio = cell.totalChanged == 0
                                ? 0
                                : CGFloat(cell.additions) / CGFloat(cell.totalChanged)
                            let deletionRatio = max(0, 1 - additionRatio)
                            let available = proxy.size.height * max(totalRatio, cell.totalChanged == 0 ? 0.025 : 0.06)

                            VStack(spacing: 2) {
                                Spacer(minLength: 0)
                                if cell.totalChanged == 0 {
                                    Capsule()
                                        .fill(palette.line)
                                        .frame(height: 3)
                                } else {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(palette.green.opacity(0.92))
                                        .frame(height: max(2, available * additionRatio))
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(palette.coral.opacity(0.88))
                                        .frame(height: max(2, available * deletionRatio))
                                }
                            }
                            .scaleEffect(y: revealed ? 1 : 0.02, anchor: .bottom)
                            .animation(
                                .spring(response: 0.62, dampingFraction: 0.78)
                                    .delay(Double(index) * 0.045),
                                value: revealed
                            )
                        }

                        Text(analytics.axisLabels.indices.contains(index)
                             ? analytics.axisLabels[index].uppercased()
                             : "\(index + 1)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 164)

            HStack(spacing: 18) {
                PulseStat(label: "ACTIVE", value: "\(analytics.activeIntervals)/\(analytics.snapshot.activity.count)", detail: "intervals")
                PulseStat(label: "AVERAGE", value: analytics.averagePerCommit.formatted(), detail: "lines / commit")
                PulseStat(label: "NET", value: signedCompact(analytics.netChanged), detail: "lines")
            }
        }
        .padding(18)
        .dashboardSurface()
    }

    private func signedCompact(_ value: Int) -> String {
        ActivityNumberFormat.compact(value, sign: value < 0 ? "−" : "+")
    }
}

private struct ChangeShapeCard: View {
    @Environment(\.themePalette) private var palette
    let analytics: DashboardAnalytics
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DashboardLabel("CHANGE SHAPE")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(analytics.percentage(1 - analytics.deletionShare))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.green)
                    Text("IN")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(palette.muted)
                }

                Text("/")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(palette.line)

                VStack(alignment: .leading, spacing: 1) {
                    Text(analytics.percentage(analytics.deletionShare))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.coral)
                    Text("OUT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(palette.muted)
                }
            }

            GeometryReader { proxy in
                let additionShare = CGFloat(1 - analytics.deletionShare)
                let availableWidth = max(0, proxy.size.width - 3)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.green)
                        .frame(width: revealed ? availableWidth * additionShare : 3)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.coral)
                        .frame(maxWidth: .infinity)
                }
                .animation(.spring(response: 0.82, dampingFraction: 0.8), value: revealed)
                .overlay {
                    Canvas { context, size in
                        stride(from: CGFloat(12), to: size.width, by: 18).forEach { x in
                            var path = Path()
                            path.move(to: CGPoint(x: x - 4, y: size.height))
                            path.addLine(to: CGPoint(x: x + 4, y: 0))
                            context.stroke(path, with: .color(palette.ink.opacity(0.22)), lineWidth: 1)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(height: 52)

            VStack(spacing: 8) {
                ShapeLegend(color: palette.green, label: "Added", value: analytics.snapshot.additions)
                ShapeLegend(color: palette.coral, label: "Deleted", value: analytics.snapshot.deletions)
            }

            Spacer(minLength: 0)

            Text("Describes the mix of changed lines—not code quality or productivity.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(minHeight: 263)
        .dashboardSurface()
    }
}

private struct ReviewCard: View {
    @Environment(\.themePalette) private var palette
    let review: DashboardAnalytics.Review
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                DashboardLabel(review.eyebrow)
                Spacer()
                Text("DETERMINISTIC · SNAPSHOT BASED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(palette.muted.opacity(0.7))
            }

            Text(review.title)
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.text)
                .offset(y: revealed ? 0 : 8)
                .opacity(revealed ? 1 : 0)

            Text(review.summary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(palette.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: revealed ? 0 : 8)
                .opacity(revealed ? 1 : 0)

            if !review.notes.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(review.notes.enumerated()), id: \.element.id) { index, note in
                        ReviewNoteView(note: note)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 12)
                            .animation(.easeOut(duration: 0.42).delay(0.16 + Double(index) * 0.08), value: revealed)
                    }
                }
            }
        }
        .padding(20)
        .background {
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.panel)
                Rectangle()
                    .fill(palette.green.opacity(0.8))
                    .frame(width: 4)
                    .padding(.vertical, 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        }
    }
}

private struct RepositoryLedgerCard: View {
    @Environment(\.themePalette) private var palette
    let analytics: DashboardAnalytics
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DashboardLabel("REPOSITORY LEDGER")
                Spacer()
                Text("RANKED BY LINE MOVEMENT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(palette.muted.opacity(0.7))
            }

            if analytics.snapshot.repositories.isEmpty {
                Text("No active repositories in this window.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.muted)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(analytics.snapshot.repositories.prefix(6).enumerated()), id: \.element.id) { index, repository in
                    RepositoryLedgerRow(
                        rank: index + 1,
                        repository: repository,
                        maximum: max(analytics.leadingRepository?.totalChanged ?? 0, 1),
                        revealed: revealed,
                        delay: Double(index) * 0.05
                    )
                }
            }
        }
        .padding(18)
        .dashboardSurface()
    }
}

private struct RepositoryLedgerRow: View {
    @Environment(\.themePalette) private var palette
    let rank: Int
    let repository: RepositoryActivity
    let maximum: Int
    let revealed: Bool
    let delay: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(rank.formatted(.number.precision(.integerLength(2))))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.muted)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(repository.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("\(repository.commits)c")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.muted)
                    Spacer()
                    Text(ActivityNumberFormat.compact(repository.additions, sign: "+"))
                        .foregroundStyle(palette.green)
                    Text(ActivityNumberFormat.compact(repository.deletions, sign: "−"))
                        .foregroundStyle(palette.coral)
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))

                GeometryReader { proxy in
                    let ratio = CGFloat(repository.totalChanged) / CGFloat(maximum)
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.line)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [palette.green, palette.green.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: revealed ? proxy.size.width * ratio : 3)
                            .animation(.spring(response: 0.7, dampingFraction: 0.84).delay(delay), value: revealed)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ReviewNoteView: View {
    @Environment(\.themePalette) private var palette
    let note: DashboardAnalytics.Review.Note

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(noteColor)
            Text(note.value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(note.detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(palette.lifted.opacity(0.64), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var noteColor: Color {
        switch note.tone {
        case .green: palette.green
        case .coral: palette.coral
        case .neutral: palette.muted
        }
    }
}

private struct PulseStat: View {
    @Environment(\.themePalette) private var palette
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DashboardLabel(label)
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShapeLegend: View {
    @Environment(\.themePalette) private var palette
    let color: Color
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.muted)
            Spacer()
            Text(value.formatted())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
    }
}

private struct DashboardLabel: View {
    @Environment(\.themePalette) private var palette
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.25)
            .foregroundStyle(palette.muted)
    }
}

private struct DashboardBackdrop: View {
    @Environment(\.themePalette) private var palette
    var body: some View {
        palette.ink
            .overlay {
                Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                    let spacing: CGFloat = 34
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(path, with: .color(palette.green.opacity(0.025)), lineWidth: 1)
                        x += spacing
                    }
                }
            }
            .ignoresSafeArea()
    }
}

private struct DashboardSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var palette
    func body(content: Content) -> some View {
        content
            .background(palette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            }
    }
}

private struct DashboardCapsuleButtonStyle: ButtonStyle {
    let palette: ThemePalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(palette.green.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private extension View {
    func dashboardSurface() -> some View {
        modifier(DashboardSurfaceModifier())
    }
}
