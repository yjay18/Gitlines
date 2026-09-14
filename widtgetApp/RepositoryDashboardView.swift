import SwiftUI
import Charts

struct RepositoryDashboardView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var github: GitHubAccountModel
    @Binding var period: ActivityPeriod
    @Binding var windowMode: PeriodWindowMode
    let openConnections: () -> Void

    @State private var tab = "Overview"
    @State private var custom = false
    @State private var anchor = Date()
    @State private var isPresent = true
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: .now)!
    @State private var customEnd = Date()
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var owner = "All owners"
    @State private var visibility = "All visibility"
    @State private var activity = "All activity"
    @State private var archiveFilter = "All repositories"
    @State private var sort = "Commits"
    @State private var favouritesOnly = false
    @State private var metric = "Commits"
    @State private var detail: DashboardRepository?
    @State private var selectedDay: Date?
    @State private var attemptedInitialSync = false
    @AppStorage("dashboard.favouriteRepositories") private var favouriteJSON = "[]"

    private var history: DashboardHistory { github.dashboardHistory ?? DashboardHistory(username: github.username) }
    private var unit: DashboardRangeUnit { custom ? .custom : DashboardRangeUnit(rawValue: period.rawValue) ?? .weekly }
    private var now: Date { history.asOf ?? .now }
    private var range: DashboardDateRange {
        DashboardDateRange.make(unit: unit, rolling: windowMode == .rolling, anchor: isPresent ? now : anchor, now: now,
                                customStart: customStart, customEnd: customEnd)
    }
    private var values: [DashboardCommit] { history.commits(in: range.current, repositories: selected) }
    private var previous: [DashboardCommit] { history.commits(in: range.previous, repositories: selected) }
    private var repositoryCount: Int { selected.isEmpty ? history.repositories.count : selected.count }
    private var covered: Bool { repositoryCount > 0 && history.coveredCount(in: range.current, repositories: selected) == repositoryCount }
    private var comparisonCovered: Bool { covered && history.coveredCount(in: range.previous, repositories: selected) == repositoryCount }
    private var favourites: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(favouriteJSON.utf8))) ?? [])
    }
    private var totalsByRepository: [String: DashboardTotals] {
        Dictionary(grouping: history.commits(in: range.current), by: \.repository).mapValues { DashboardTotals($0) }
    }
    private var filteredRepositories: [DashboardRepository] {
        let totals = totalsByRepository
        return history.repositories.filter { repo in
            let count = totals[repo.id]?.commits ?? 0
            let known = history.coverage[repo.id]?.contains(range.current) == true
            return (search.isEmpty || repo.id.localizedCaseInsensitiveContains(search))
                && (owner == "All owners" || repo.owner == owner)
                && (visibility == "All visibility" || (visibility == "Private") == repo.isPrivate)
                && (archiveFilter == "All repositories" || (archiveFilter == "Archived") == repo.isArchived)
                && (!favouritesOnly || favourites.contains(repo.id))
                && (activity == "All activity" || (activity == "Active" && count > 0)
                    || (activity == "Inactive" && count == 0 && known) || (activity == "Not fully synced" && !known))
        }.sorted { lhs, rhs in
            let l = totals[lhs.id], r = totals[rhs.id]
            switch sort {
            case "Commits": if l?.commits ?? 0 != r?.commits ?? 0 { return l?.commits ?? 0 > r?.commits ?? 0 }
            case "Changed lines":
                let lc = (l?.additions ?? 0) + (l?.deletions ?? 0), rc = (r?.additions ?? 0) + (r?.deletions ?? 0)
                if lc != rc { return lc > rc }
            case "Last activity": if lhs.pushedAt != rhs.pushedAt { return lhs.pushedAt ?? .distantPast > rhs.pushedAt ?? .distantPast }
            default: break
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dateControls
                coverageCard
                if github.hasStoredToken {
                    scopeControls
                    Picker("Dashboard view", selection: $tab) {
                        ForEach(["Overview", "Repositories", "Activity"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    if tab == "Overview" { overview }
                    if tab == "Repositories" { repositoryExplorer }
                    if tab == "Activity" { activityExplorer }
                } else {
                    Text("Connect GitHub to explore your repositories and activity.")
                    Button("Open Connections", action: openConnections).buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .background(palette.ink)
        .foregroundStyle(palette.text)
        .font(.system(size: 12, design: palette.fontDesign))
        .tint(palette.green)
        .sheet(item: $detail) { repository in
            RepositoryDetailView(repository: repository, history: history, range: range.current)
                .environment(\.themePalette, palette)
        }
        .task { startInitialSyncIfReady() }
        .onChange(of: github.hasStoredToken) { _, connected in if connected { startInitialSyncIfReady() } }
        .onChange(of: github.isBusy) { _, busy in if !busy { startInitialSyncIfReady() } }
        .onChange(of: history.repositories.map(\.id)) { _, ids in selected.formIntersection(ids) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR GITHUB ACTIVITY").font(.system(size: 10, weight: .bold, design: palette.fontDesign)).tracking(2)
                    .foregroundStyle(palette.green)
                Text("@\(github.username)").font(.system(size: 28, weight: .heavy, design: palette.fontDesign))
                Text(github.dashboardHistory == nil ? "Repository catalog not synced yet · your commits across all branches"
                     : "\(history.repositories.count) accessible repositories · your commits across all branches")
                    .foregroundStyle(palette.muted)
            }
            Spacer(minLength: 12)
            if github.isSyncingHistory {
                Button("Stop sync") { github.cancelHistorySync() }
            } else {
                Button("Sync history", systemImage: "arrow.clockwise") { sync() }
                    .disabled(github.isBusy || !github.hasStoredToken || invalidCustomRange)
            }
        }
    }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { periodPicker; windowPicker; customToggle }
                VStack(alignment: .leading) { periodPicker; HStack { windowPicker; customToggle } }
            }
            if custom {
                HStack {
                    DatePicker("From", selection: $customStart, in: ...Date(), displayedComponents: .date)
                    DatePicker("Through", selection: $customEnd, in: ...Date(), displayedComponents: .date)
                }
                if invalidCustomRange { Text("Choose an end date on or after the start date.").foregroundStyle(palette.coral) }
            } else {
                HStack {
                    Button { navigate(-1) } label: { Image(systemName: "chevron.left") }.help("Previous period")
                    Text(range.current.start.formatted(date: .abbreviated, time: .omitted) + " – " + range.current.end.addingTimeInterval(-0.001).formatted(date: .abbreviated, time: .omitted))
                        .fontWeight(.semibold)
                    Button { navigate(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(isPresent).help("Next period")
                    Spacer()
                    Button("Today") { anchor = .now; isPresent = true }
                }
            }
            Text("Comparison: \(range.previous.start.formatted(date: .abbreviated, time: .shortened)) – \(range.previous.end.formatted(date: .abbreviated, time: .shortened)). Current periods compare the same elapsed portion.")
                .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }.dashboardPanel(palette)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(ActivityPeriod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 220).disabled(custom)
    }
    private var windowPicker: some View {
        Picker("Window", selection: $windowMode) {
            Text("Calendar").tag(PeriodWindowMode.fixed); Text("Rolling").tag(PeriodWindowMode.rolling)
        }.labelsHidden().pickerStyle(.segmented).frame(width: 160).disabled(custom)
    }
    private var customToggle: some View { Toggle("Custom dates", isOn: $custom).toggleStyle(.checkbox) }
    private var invalidCustomRange: Bool { custom && Calendar.current.startOfDay(for: customEnd) < Calendar.current.startOfDay(for: customStart) }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: covered ? "checkmark.circle" : "clock.arrow.circlepath")
                Text("\(history.coveredCount(in: range.current, repositories: selected)) / \(repositoryCount) repositories synced for this period")
                    .fontWeight(.semibold)
                Spacer()
                Button("Manage access", action: openConnections)
            }
            if let updated = history.catalogUpdatedAt {
                Text("Repository list updated \(updated, style: .relative) ago. Activity through \(now.formatted(date: .abbreviated, time: .shortened)).")
                    .foregroundStyle(palette.muted)
            }
            if !covered {
                Text("Totals show fetched activity only. Unsynced repositories are not counted as inactive. Sync history to fill the selected period, comparison and calendar.")
                    .foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            if github.isSyncingHistory {
                ProgressView(value: Double(github.historyCompleted), total: Double(max(github.historyTotal, 1)))
            }
            if !github.historyProgress.isEmpty { Text(github.historyProgress).foregroundStyle(palette.muted) }
            if let error = github.historyError { Text(error).foregroundStyle(palette.coral) }
            if let retry = github.historyRetryAt {
                HStack {
                    Text("Automatic retry at \(retry.formatted(date: .omitted, time: .shortened))").foregroundStyle(palette.muted)
                    Spacer()
                    Button("Cancel automatic retry") { github.cancelHistorySync() }
                }
            }
        }.dashboardPanel(palette)
    }

    private var scopeControls: some View {
        HStack {
            Text(selected.isEmpty ? "All repositories" : "\(selected.count) selected repositories")
                .fontWeight(.semibold)
            Spacer()
            if !selected.isEmpty { Button("Clear selection") { selected = [] } }
            Button("Choose repositories") { tab = "Repositories" }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !covered, values.isEmpty, !custom, isPresent, selected.isEmpty, let archive = github.activityArchive {
                savedSnapshotSummary(archive)
            } else {
                DashboardStatsView(values: values, previous: previous, comparable: comparisonCovered, complete: covered)
                DashboardActivityChart(commits: values, range: range.current, metric: $metric)
            }
            if !selected.isEmpty { comparisonTable }
            HStack {
                Text("Repositories in this period").font(.system(size: 17, weight: .bold, design: palette.fontDesign))
                Spacer()
                Button("Explore all \(history.repositories.count)") { tab = "Repositories" }
            }
            Text("Select repositories in the explorer to compare their activity and see combined totals.")
                .foregroundStyle(palette.muted)
            ForEach(history.repositories.filter { selected.isEmpty || selected.contains($0.id) }
                .sorted { (totalsByRepository[$0.id]?.commits ?? 0) > (totalsByRepository[$1.id]?.commits ?? 0) }.prefix(5)) { repo in
                repositoryRow(repo)
            }
            activityExplorer
        }
    }

    private func savedSnapshotSummary(_ archive: ActivitySnapshotArchive) -> some View {
        let snapshot = archive.snapshot(for: period.storedPeriod, windowMode: windowMode)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last saved widget snapshot").font(.system(size: 17, weight: .bold, design: palette.fontDesign))
            Text("Saved \(archive.savedAt.formatted(date: .abbreviated, time: .shortened)). The full history and repository catalog will appear after sync.")
                .foregroundStyle(palette.muted)
            HStack(spacing: 20) {
                VStack(alignment: .leading) { Text("COMMITS").font(.caption); Text(snapshot.commits.formatted()).font(.title.bold()) }
                VStack(alignment: .leading) { Text("ADDITIONS").font(.caption); Text(snapshot.additions.formatted()).font(.title.bold()).foregroundStyle(palette.green) }
                VStack(alignment: .leading) { Text("DELETIONS").font(.caption); Text(snapshot.deletions.formatted()).font(.title.bold()).foregroundStyle(palette.coral) }
            }
            ForEach(snapshot.repositories) { repo in
                HStack { Text(repo.name); Spacer(); Text("\(repo.commits) commits · +\(repo.additions) −\(repo.deletions)").monospacedDigit() }
            }
        }.dashboardPanel(palette)
    }

    private var comparisonTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Repository comparison").font(.system(size: 17, weight: .bold, design: palette.fontDesign))
            Text("Repository · commits · additions · deletions · share of selected commits")
                .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
            ForEach(history.repositories.filter { selected.contains($0.id) }) { repo in
                let totals = DashboardTotals(values.filter { $0.repository == repo.id })
                HStack {
                    Button(repo.id) { detail = repo }.buttonStyle(.plain).lineLimit(1)
                    Spacer()
                    Text("\(totals.commits) · +\(totals.additions) · −\(totals.deletions) · \(values.isEmpty ? 0 : totals.commits * 100 / values.count)%")
                        .monospacedDigit()
                }
            }
            if !covered { Text("Comparison uses partial data.").foregroundStyle(palette.coral) }
        }.dashboardPanel(palette)
    }

    private var repositoryExplorer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search all repositories by name or owner", text: $search).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 10) {
                Picker("Owner", selection: $owner) {
                    Text("All owners").tag("All owners")
                    ForEach(Array(Set(history.repositories.map(\.owner))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                filterPicker("Visibility", selection: $visibility, values: ["All visibility", "Public", "Private"])
                filterPicker("Activity", selection: $activity, values: ["All activity", "Active", "Inactive", "Not fully synced"])
                filterPicker("Status", selection: $archiveFilter, values: ["All repositories", "Unarchived", "Archived"])
                filterPicker("Sort", selection: $sort, values: ["Commits", "Changed lines", "Last activity", "Name"])
                Toggle("Favourites only", isOn: $favouritesOnly).toggleStyle(.checkbox)
            }
            HStack {
                Text("\(filteredRepositories.count) of \(history.repositories.count) repositories").foregroundStyle(palette.muted)
                Spacer()
                Button("Select results") { selected.formUnion(filteredRepositories.map(\.id)) }
                Button("Reset filters") { search = ""; owner = "All owners"; visibility = "All visibility"; activity = "All activity"; archiveFilter = "All repositories"; favouritesOnly = false }
            }
            LazyVStack(spacing: 8) {
                ForEach(filteredRepositories) { repo in repositoryRow(repo) }
            }
            if filteredRepositories.isEmpty {
                Text(history.repositories.isEmpty ? "The repository list will appear as soon as sync discovers your accessible repositories." : "No repositories match these filters.")
                    .foregroundStyle(palette.muted).padding(.vertical, 20)
            }
            if !selected.isEmpty { comparisonTable }
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) { ForEach(values, id: \.self) { Text($0).tag($0) } }
    }

    private func repositoryRow(_ repo: DashboardRepository) -> some View {
        let totals = totalsByRepository[repo.id] ?? DashboardTotals([])
        let coverage = history.coverage[repo.id]
        let known = coverage?.contains(range.current) == true
        return HStack(spacing: 10) {
            Toggle("Compare \(repo.id)", isOn: Binding(get: { selected.contains(repo.id) }, set: { value in
                if value { selected.insert(repo.id) } else { selected.remove(repo.id) }
            })).labelsHidden().toggleStyle(.checkbox)
            Button { toggleFavourite(repo.id) } label: {
                Image(systemName: favourites.contains(repo.id) ? "star.fill" : "star")
            }.buttonStyle(.plain).help("Favourite \(repo.id)").accessibilityLabel("Favourite \(repo.id)")
            Button { detail = repo } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(repo.id).fontWeight(.semibold).lineLimit(1).help(repo.id)
                    Text("\(repo.isPrivate ? "Private" : "Public")\(repo.isArchived ? " · Archived" : "") · \(known ? (totals.commits == 0 ? "No activity" : "Synced") : "Not fully synced")")
                        .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
                    if let pushed = repo.pushedAt {
                        Text("Last repository push \(pushed.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
                    }
                    if let error = coverage?.error { Text(error).font(.caption).foregroundStyle(palette.coral).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(alignment: .trailing, spacing: 5) {
                Text(known || totals.commits > 0 ? "\(totals.commits) commits\(known ? "" : " observed")" : "—")
                Text(known || totals.commits > 0 ? "+\(totals.additions)  −\(totals.deletions)" : "Not synced")
                    .foregroundStyle(palette.muted)
            }.monospacedDigit().font(.system(size: 11, design: palette.fontDesign))
        }.dashboardPanel(palette)
    }

    private var activityExplorer: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardHeatmap(history: history, selected: selected, end: range.current.end, selectedDay: $selectedDay)
            if let day = selectedDay {
                let interval = DateInterval(start: day, end: min(Calendar.current.date(byAdding: .day, value: 1, to: day)!, now))
                let dayCommits = history.commits(in: interval, repositories: selected)
                HStack {
                    Text(day.formatted(date: .complete, time: .omitted)).fontWeight(.bold)
                    Spacer()
                    Button("Clear day") { selectedDay = nil }
                }
                Text("\(dayCommits.count) fetched commits across \(Set(dayCommits.map(\.repository)).count) repositories")
                    .foregroundStyle(palette.muted)
                DashboardCommitList(commits: dayCommits)
            } else {
                Text("Commits in the selected period").font(.system(size: 17, weight: .bold, design: palette.fontDesign))
                DashboardCommitList(commits: values)
            }
        }
    }

    private func toggleFavourite(_ id: String) {
        var next = favourites
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        if let data = try? JSONEncoder().encode(next.sorted()), let json = String(data: data, encoding: .utf8) { favouriteJSON = json }
    }
    private func navigate(_ direction: Int) {
        if windowMode == .rolling {
            let days = unit == .daily ? 1 : unit == .weekly ? 7 : 30
            anchor = min((isPresent ? now : anchor).addingTimeInterval(Double(days * direction) * 86400), now)
        } else {
            // Use the period start so Jan 31 -> Feb does not drift or skip a month.
            anchor = min(Calendar.current.date(byAdding: unit.component, value: direction, to: range.current.start)!, now)
        }
        isPresent = windowMode == .rolling ? anchor >= now
            : Calendar.current.dateInterval(of: unit.component, for: anchor)?.contains(now) == true
        selectedDay = nil
    }
    private func sync() {
        guard !invalidCustomRange else { return }
        let freshNow = Date()
        let selectedRange = DashboardDateRange.make(unit: unit, rolling: windowMode == .rolling, anchor: isPresent ? freshNow : anchor,
            now: freshNow, customStart: customStart, customEnd: customEnd)
        let heatmapStart = Calendar.current.date(byAdding: .day, value: -91, to: selectedRange.current.end)!
        github.syncDashboardHistory(range: DateInterval(start: min(selectedRange.previous.start, heatmapStart), end: freshNow))
    }
    private func startInitialSyncIfReady() {
        guard !attemptedInitialSync, github.hasStoredToken, !github.isBusy else { return }
        attemptedInitialSync = true
        if github.dashboardHistory == nil { sync() }
    }
}

private extension View {
    func dashboardPanel(_ palette: ThemePalette) -> some View {
        self.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.panel, in: RoundedRectangle(cornerRadius: palette.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.line, lineWidth: 1) }
    }
}

private struct DashboardStatsView: View {
    @Environment(\.themePalette) private var palette
    let values: [DashboardCommit]
    let previous: [DashboardCommit]
    let comparable: Bool
    let complete: Bool
    var body: some View {
        let totals = DashboardTotals(values), prior = DashboardTotals(previous)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 12) {
            stat("COMMITS", totals.commits, prior.commits, palette.text)
            stat("ADDITIONS", totals.additions, prior.additions, palette.green)
            stat("DELETIONS", totals.deletions, prior.deletions, palette.coral)
            stat("ACTIVE DAYS", totals.activeDays, prior.activeDays, palette.text)
            stat("REPOSITORIES", totals.repositories, prior.repositories, palette.text)
        }
    }
    private func stat(_ title: String, _ value: Int, _ prior: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .bold, design: palette.fontDesign)).foregroundStyle(palette.muted)
            Text(value.formatted()).font(.system(size: 28, weight: .heavy, design: palette.fontDesign)).foregroundStyle(color)
            Text(comparable ? "\(DashboardTotals.change(value, from: prior)) · previous \(prior)" : "\(complete ? "Comparison not synced" : "Partial data")")
                .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
        }.dashboardPanel(palette)
    }
}

private struct DashboardActivityChart: View {
    @Environment(\.themePalette) private var palette
    let commits: [DashboardCommit]
    let range: DateInterval
    @Binding var metric: String
    @State private var selectedDate: Date?
    private var component: Calendar.Component { range.duration > 366 * 86400 ? .month : range.duration > 90 * 86400 ? .weekOfYear : .day }
    private var buckets: [(date: Date, value: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: commits) { calendar.dateInterval(of: component, for: $0.date)!.start }
        var result: [(Date, Int)] = []
        var date = calendar.dateInterval(of: component, for: range.start)!.start
        while date < range.end {
            let entries = grouped[date] ?? []
            result.append((date, metric == "Commits" ? entries.count : entries.reduce(0) { $0 + $1.additions + $1.deletions }))
            date = calendar.date(byAdding: component, value: 1, to: date)!
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity trend").font(.system(size: 17, weight: .bold, design: palette.fontDesign))
                Spacer()
                Picker("Chart metric", selection: $metric) { Text("Commits").tag("Commits"); Text("Changed lines").tag("Changed lines") }
                    .labelsHidden().frame(width: 160)
            }
            Chart {
                ForEach(buckets, id: \.date) { bucket in
                    BarMark(x: .value("Date", bucket.date, unit: component), y: .value(metric, bucket.value))
                        .foregroundStyle(palette.green)
                }
                if let selectedDate, let bucket = buckets.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }) {
                    RuleMark(x: .value("Date", bucket.date)).foregroundStyle(palette.text)
                        .annotation(position: .top) { Text("\(bucket.date.formatted(date: .abbreviated, time: .omitted)): \(bucket.value) \(metric.lowercased())").font(.caption).padding(6).background(palette.lifted) }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine().foregroundStyle(palette.line); AxisValueLabel().foregroundStyle(palette.muted) } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(palette.line); AxisValueLabel().foregroundStyle(palette.muted) } }
            .frame(height: 180)
            Text("\(component == .day ? "Daily" : component == .month ? "Monthly" : "Weekly") buckets · Click or drag to inspect. Changed lines describe code movement, not quality or productivity.")
                .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
        }.dashboardPanel(palette)
    }
}

private struct DashboardHeatmap: View {
    @Environment(\.themePalette) private var palette
    let history: DashboardHistory
    let selected: Set<String>
    let end: Date
    @Binding var selectedDay: Date?
    private var days: [Date] {
        let last = Calendar.current.startOfDay(for: end.addingTimeInterval(-0.001))
        return (-90...0).map { Calendar.current.date(byAdding: .day, value: $0, to: last)! }
    }
    var body: some View {
        let counts = Dictionary(grouping: history.commits.filter { selected.isEmpty || selected.contains($0.repository) }) { Calendar.current.startOfDay(for: $0.date) }.mapValues(\.count)
        let maximum = max(counts.values.max() ?? 1, 1)
        let count = selected.isEmpty ? history.repositories.count : selected.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("Activity calendar · last 13 weeks").font(.system(size: 17, weight: .bold, design: palette.fontDesign))
            Text("\(days.first!.formatted(date: .abbreviated, time: .omitted)) – \(days.last!.formatted(date: .abbreviated, time: .omitted))")
                .foregroundStyle(palette.muted)
            ScrollView(.horizontal) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(22), spacing: 4), count: 7), spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        let interval = DateInterval(start: day, end: min(Calendar.current.date(byAdding: .day, value: 1, to: day)!, end))
                        let complete = count > 0 && history.coveredCount(in: interval, repositories: selected) == count
                        let value = counts[day] ?? 0
                        Button { selectedDay = day } label: {
                            RoundedRectangle(cornerRadius: min(palette.cornerRadius, 3))
                                .fill(value > 0 ? palette.green.opacity(0.25 + 0.75 * Double(value) / Double(maximum)) : palette.lifted)
                                .overlay { if !complete { Image(systemName: "minus").font(.system(size: 8)).foregroundStyle(palette.muted) } }
                                .overlay { if selectedDay == day { RoundedRectangle(cornerRadius: 3).stroke(palette.text, lineWidth: 2) } }
                                .frame(width: 22, height: 22)
                        }.buttonStyle(.plain)
                        .help("\(day.formatted(date: .complete, time: .omitted)): \(value) commits\(complete ? "" : " · incomplete coverage")")
                        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(value) commits, \(complete ? "synced" : "not fully synced")")
                    }
                }.padding(2)
            }
            Text("Darker → brighter: fewer → more commits. A dash marks incomplete coverage. Click a day to see its commits.")
                .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
        }.dashboardPanel(palette)
    }
}

private struct DashboardCommitList: View {
    @Environment(\.themePalette) private var palette
    let commits: [DashboardCommit]
    @State private var limit = 50
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(commits.sorted { $0.date > $1.date }.prefix(limit)) { commit in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Link(commit.message, destination: commit.url).fontWeight(.medium)
                        Text("\(commit.repository) · \(commit.sha.prefix(7)) · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10, design: palette.fontDesign)).foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 8)
                    Text("+\(commit.additions) −\(commit.deletions)").monospacedDigit().foregroundStyle(palette.muted)
                }
                Divider().overlay(palette.line)
            }
            if commits.isEmpty { Text("No fetched commits in this selection. Check sync coverage before treating this as inactivity.").foregroundStyle(palette.muted) }
            if commits.count > limit { Button("Show more (\(commits.count - limit) remaining)") { limit += 100 } }
        }.dashboardPanel(palette)
    }
}

private struct RepositoryDetailView: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    let repository: DashboardRepository
    let history: DashboardHistory
    let range: DateInterval
    @State private var metric = "Commits"
    var body: some View {
        let commits = history.commits(in: range, repositories: [repository.id])
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(repository.id).font(.system(size: 23, weight: .bold, design: palette.fontDesign)).textSelection(.enabled)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                HStack {
                    Text("\(repository.isPrivate ? "Private" : "Public")\(repository.isArchived ? " · Archived" : "")")
                    Spacer()
                    Link("Open on GitHub", destination: repository.url)
                }
                Text("\(range.start.formatted(date: .abbreviated, time: .omitted)) – \(range.end.formatted(date: .abbreviated, time: .shortened))")
                if history.coverage[repository.id]?.contains(range) != true {
                    Text("This period is not fully synced. Close this view and use Sync history to fetch it.").foregroundStyle(palette.coral)
                }
                if let error = history.coverage[repository.id]?.error { Text(error).foregroundStyle(palette.coral) }
                DashboardStatsView(values: commits, previous: [], comparable: false, complete: history.coverage[repository.id]?.contains(range) == true)
                DashboardActivityChart(commits: commits, range: range, metric: $metric)
                Text("Commit history").font(.headline)
                DashboardCommitList(commits: commits)
            }.padding(24)
        }.frame(minWidth: 680, idealWidth: 780, minHeight: 580, idealHeight: 720)
            .background(palette.ink).foregroundStyle(palette.text).tint(palette.green)
    }
}
