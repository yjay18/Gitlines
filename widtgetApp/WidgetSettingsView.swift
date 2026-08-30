import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

private enum HostSection: String, CaseIterable, Identifiable {
    case dashboard
    case widgets
    case connections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .widgets: "Widget Studio"
        case .connections: "Connections"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "waveform.path.ecg"
        case .widgets: "square.grid.3x3.fill"
        case .connections: "key.horizontal.fill"
        }
    }
}

struct WidgetSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var github = GitHubAccountModel()
    @State private var showingDisconnectConfirmation = false
    @State private var showingRemoveOrganizationConfirmation = false
    @State private var organizationPendingRemoval: GitHubConnectionSummary?
    @State private var isReplacingAccountToken = false
    @State private var isAddingOrganization = false
    @State private var selectedSection: HostSection = .dashboard
    @State private var dashboardWindowMode = SharedPreferences.windowMode
    @State private var dashboardPeriod = SharedPreferences.defaults
        .string(forKey: SharedPreferences.Key.dashboardPeriod)
        .flatMap(ActivityPeriod.init(rawValue:)) ?? .weekly
    @State private var paneOrder = SharedPreferences.modularPreferences.paneOrder
    @State private var enabledPanes = SharedPreferences.modularPreferences.enabledPanes
    @State private var blockworkColorway = SharedPreferences.modularPreferences.colorway
    @State private var visualTheme = SharedPreferences.modularPreferences.visualTheme
    @State private var familyLayouts = SharedPreferences.modularPreferences.familyLayouts
    @State private var blockColors = SharedPreferences.modularPreferences.blockColors
    @State private var refreshInterval = SharedPreferences.refreshInterval
    @State private var snakeBlockBasis = SharedPreferences.snakeBlockBasis
    @State private var snakeUnitsPerBlock = SharedPreferences.snakeUnitsPerBlock
    @State private var themeOverrides: [WidgetLayoutFamily: WidgetVisualTheme] = Dictionary(
        uniqueKeysWithValues: WidgetLayoutFamily.allCases.compactMap { family in
            SharedPreferences.themeOverride(for: family).map { (family, $0) }
        }
    )
    @State private var snekBasisOverrides: [SnekKey: SnakeBlockBasis] = {
        var result: [SnekKey: SnakeBlockBasis] = [:]
        for theme in WidgetVisualTheme.allCases {
            for family in WidgetLayoutFamily.allCases {
                if let basis = SharedPreferences.snekBasisOverride(theme: theme, family: family) {
                    result[SnekKey(theme: theme, family: family)] = basis
                }
            }
        }
        return result
    }()
    @State private var snekPerBlockOverrides: [SnekKey: Int] = {
        var result: [SnekKey: Int] = [:]
        for theme in WidgetVisualTheme.allCases {
            for family in WidgetLayoutFamily.allCases {
                if let value = SharedPreferences.snekPerBlockOverride(theme: theme, family: family) {
                    result[SnekKey(theme: theme, family: family)] = value
                }
            }
        }
        return result
    }()
    @State private var selectedBlock: WidgetPane = .additions
    @State private var draggedPane: WidgetPane?
    @State private var draggedOrigin: WidgetSlotOrigin?

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch selectedSection {
                case .dashboard:
                    if visualTheme == .blockwork {
                        BlockworkAnalyticsDashboardView(
                            github: github,
                            period: $dashboardPeriod,
                            windowMode: $dashboardWindowMode,
                            openConnections: { selectedSection = .connections }
                        )
                    } else {
                        AnalyticsDashboardView(
                            github: github,
                            period: $dashboardPeriod,
                            windowMode: $dashboardWindowMode,
                            openConnections: { selectedSection = .connections }
                        )
                        .environment(\.themePalette, visualTheme.dashboardPalette)
                    }
                case .widgets:
                    widgetStudioContent
                case .connections:
                    connectionsContent
                }
            }
        }
        .frame(minWidth: 880, minHeight: 640)
        .background(DashboardPalette.ink)
        .preferredColorScheme(.dark)
        .task {
            migrateToFixedDefaultIfNeeded()
            reloadWidgets()
            await github.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await github.handleActivation() }
        }
        .onChange(of: paneOrder) { _, _ in
            saveWidgetStudio()
        }
        .onChange(of: enabledPanes) { _, _ in
            saveWidgetStudio()
        }
        .onChange(of: blockworkColorway) { _, _ in
            saveWidgetStudio()
        }
        .onChange(of: visualTheme) { _, _ in
            saveWidgetStudio()
        }
        .onChange(of: dashboardWindowMode) { _, newValue in
            SharedPreferences.windowMode = newValue
            reloadWidgets()
        }
        .onChange(of: dashboardPeriod) { _, newValue in
            SharedPreferences.defaults.set(newValue.rawValue, forKey: SharedPreferences.Key.dashboardPeriod)
        }
        .onChange(of: familyLayouts) { _, _ in
            saveWidgetStudio()
        }
        .onChange(of: blockColors) { _, _ in
            saveWidgetStudio()
        }
        .onOpenURL { url in
            guard url.scheme == "widtget", url.host == "refresh" else { return }
            Task { await github.refresh(scope: .recentBranches) }
        }
        .confirmationDialog(
            "Disconnect @\(github.username)?",
            isPresented: $showingDisconnectConfirmation
        ) {
            Button("Disconnect GitHub", role: .destructive) {
                github.disconnect()
            }
        } message: {
            Text("The Keychain token and cached widget activity will be removed from this Mac.")
        }
        .confirmationDialog(
            "Remove \(organizationPendingRemoval?.owner ?? "organization")?",
            isPresented: $showingRemoveOrganizationConfirmation
        ) {
            Button("Remove organization", role: .destructive) {
                guard let id = organizationPendingRemoval?.id else { return }
                Task { await github.removeOrganization(id: id) }
            }
        } message: {
            Text("Its token will be removed from Keychain and its repositories will stop contributing to the widget.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DashboardPalette.green)
                    Text("W")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(DashboardPalette.ink)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("widtget")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text("GITHUB SIGNAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(DashboardPalette.muted)
                }
            }
            .padding(.horizontal, 14)

            VStack(spacing: 5) {
                ForEach(HostSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 18)
                            Text(section.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                        }
                        .foregroundStyle(selectedSection == section ? DashboardPalette.text : DashboardPalette.text.opacity(0.68))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(
                            selectedSection == section ? DashboardPalette.lifted : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay(alignment: .leading) {
                            if selectedSection == section {
                                Capsule()
                                    .fill(DashboardPalette.green)
                                    .frame(width: 3, height: 18)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)

            Spacer()

            if github.hasStoredToken {
                VStack(alignment: .leading, spacing: 5) {
                    Text(github.username.isEmpty ? "CONNECTED" : "@\(github.username)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(github.phase == .failed ? DashboardPalette.coral : DashboardPalette.green)
                            .frame(width: 6, height: 6)
                        Text(github.phase == .failed ? "REFRESH NEEDED" : "SNAPSHOT READY")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(DashboardPalette.muted)
                    }
                }
                .padding(14)
            }
        }
        .padding(.vertical, 14)
        .frame(width: 176)
        .background(DashboardPalette.panel.opacity(0.9))
        .overlay(alignment: .trailing) {
            Rectangle().fill(DashboardPalette.line).frame(width: 1)
        }
        .foregroundStyle(DashboardPalette.text)
    }

    private func resolvedStudioTheme(_ family: WidgetLayoutFamily) -> WidgetVisualTheme {
        themeOverrides[family] ?? visualTheme
    }

    private var widgetStudioContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WIDGET STUDIO")
                            .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1)
                            .foregroundStyle(DashboardPalette.green)
                        Text("A theme for every size")
                            .font(.system(size: 24, weight: .black, design: .rounded)).tracking(-0.6)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("DASHBOARD THEME")
                            .font(.system(size: 8, weight: .black, design: .monospaced)).tracking(0.9)
                            .foregroundStyle(DashboardPalette.muted)
                        Picker("", selection: $visualTheme) {
                            ForEach(WidgetVisualTheme.allCases) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 180)
                    }
                }

                ForEach(WidgetLayoutFamily.allCases) { family in
                    widgetSizeCard(family)
                }
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(DashboardPalette.text)
        .background(DashboardPalette.ink)
    }

    private func widgetSizeCard(_ family: WidgetLayoutFamily) -> some View {
        let theme = resolvedStudioTheme(family)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(family.displayName.uppercased()) WIDGET")
                    .font(.system(size: 11, weight: .black, design: .monospaced)).tracking(0.8)
                Spacer()
                Picker("", selection: themeOverrideBinding(family)) {
                    Text("Default \u{00B7} \(visualTheme.displayName)").tag(WidgetVisualTheme?.none)
                    ForEach(WidgetVisualTheme.allCases) { option in
                        Text(option.displayName).tag(WidgetVisualTheme?.some(option))
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 220)
            }

            if theme == .blockwork {
                DisclosureGroup {
                    blockworkSettings(family).padding(.top, 12)
                } label: {
                    Label("Settings", systemImage: "square.grid.2x2")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .tint(DashboardPalette.green)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    realThemePreview(family, theme: theme)
                }
            }

            if themeHasSnek(theme, family) {
                Rectangle().fill(DashboardPalette.line).frame(height: 1)
                snekConfigRow(theme: theme, family: family)
            }
        }
        .padding(16)
        .background(DashboardPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DashboardPalette.line, lineWidth: 1)
        }
    }

    private func themeHasSnek(_ theme: WidgetVisualTheme, _ family: WidgetLayoutFamily) -> Bool {
        switch theme {
        case .arcade: true
        case .glasshouse, .phosphor: family == .large || family == .extraLarge
        case .blockwork: (familyLayouts[family] ?? []).contains(.snake)
        case .broadsheet, .defaultTheme: false
        }
    }

    private func snekConfigRow(theme: WidgetVisualTheme, family: WidgetLayoutFamily) -> some View {
        let basis = SharedPreferences.snekBasis(theme: theme, family: family)
        return HStack(spacing: 10) {
            Text("SNEK")
                .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1)
                .foregroundStyle(DashboardPalette.muted)
            Picker("", selection: snekBasisBinding(theme, family)) {
                Text("Default").tag(SnakeBlockBasis?.none)
                ForEach(SnakeBlockBasis.allCases) { option in
                    Text(option.displayName).tag(SnakeBlockBasis?.some(option))
                }
            }
            .labelsHidden().pickerStyle(.menu).frame(width: 150)
            Spacer(minLength: 8)
            TextField("", value: snekPerBlockBinding(theme, family), format: .number)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 84)
            Text("\(basis.unitNoun)/block")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(DashboardPalette.muted)
        }
        .font(.system(size: 11))
    }

    private func snekBasisBinding(_ theme: WidgetVisualTheme, _ family: WidgetLayoutFamily) -> Binding<SnakeBlockBasis?> {
        let key = SnekKey(theme: theme, family: family)
        return Binding(
            get: { snekBasisOverrides[key] },
            set: { newValue in
                if let newValue {
                    snekBasisOverrides[key] = newValue
                    snekPerBlockOverrides[key] = newValue.defaultPerBlock
                    SharedPreferences.setSnekBasis(newValue, theme: theme, family: family)
                    SharedPreferences.setSnekPerBlock(newValue.defaultPerBlock, theme: theme, family: family)
                } else {
                    snekBasisOverrides.removeValue(forKey: key)
                    snekPerBlockOverrides.removeValue(forKey: key)
                    SharedPreferences.setSnekBasis(nil, theme: theme, family: family)
                    SharedPreferences.setSnekPerBlock(nil, theme: theme, family: family)
                }
                reloadWidgets()
            }
        )
    }

    private func snekPerBlockBinding(_ theme: WidgetVisualTheme, _ family: WidgetLayoutFamily) -> Binding<Int> {
        let key = SnekKey(theme: theme, family: family)
        return Binding(
            get: { snekPerBlockOverrides[key] ?? SharedPreferences.snekPerBlock(theme: theme, family: family) },
            set: { newValue in
                let clamped = max(1, newValue)
                snekPerBlockOverrides[key] = clamped
                SharedPreferences.setSnekPerBlock(clamped, theme: theme, family: family)
                reloadWidgets()
            }
        )
    }

    private func previewSize(_ family: WidgetLayoutFamily) -> (width: CGFloat, height: CGFloat) {
        switch family {
        case .small: (190, 190)
        case .medium: (380, 190)
        case .large: (320, 320)
        case .extraLarge: (620, 300)
        }
    }

    // Renders the real widget view so the studio preview always matches the build.
    @ViewBuilder
    private func realThemePreview(_ family: WidgetLayoutFamily, theme: WidgetVisualTheme) -> some View {
        let entry = previewEntry(theme: theme, family: family)
        let size = previewSize(family)
        let corner: CGFloat = family == .small ? 22 : 18
        Group {
            switch theme {
            case .glasshouse: GlasshouseWidgetView(entry: entry, preferences: entry.preferences, family: family)
            case .phosphor: PhosphorWidgetView(entry: entry, preferences: entry.preferences, family: family)
            case .broadsheet: BroadsheetWidgetView(entry: entry, preferences: entry.preferences, family: family)
            case .arcade: ArcadeWidgetView(entry: entry, preferences: entry.preferences, family: family)
            case .defaultTheme, .blockwork: DefaultWidgetView(entry: entry, preferences: entry.preferences, family: family)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(theme.containerBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .shadow(color: Color.black.opacity(0.28), radius: 14, y: 8)
    }

    private var previewSnapshot: ActivitySnapshot {
        if let archive = github.activityArchive {
            return archive.snapshot(for: .weekly, windowMode: SharedPreferences.windowMode)
        }
        let adds = [3204, 5411, 1102, 9812, 6904, 761, 0]
        let dels = [200, 120, 80, 400, 150, 41, 0]
        return ActivitySnapshot(
            additions: 25036,
            deletions: 1031,
            commits: 29,
            repositories: [
                RepositoryActivity(name: "Studio-portal", commits: 12, additions: 19000, deletions: 2100),
                RepositoryActivity(name: "linguistics", commits: 8, additions: 5000, deletions: 800),
                RepositoryActivity(name: "widtget", commits: 6, additions: 6100, deletions: 757),
                RepositoryActivity(name: "storymode", commits: 3, additions: 659, deletions: 40)
            ],
            activity: (0..<7).map { ActivityCell(id: $0, additions: adds[$0], deletions: dels[$0]) },
            updatedAt: .now,
            state: .loaded
        )
    }

    private func previewEntry(theme: WidgetVisualTheme, family: WidgetLayoutFamily) -> ActivityEntry {
        var prefs = WidgetViewPreferences.defaults
        prefs.visualTheme = theme
        prefs.periodWindowMode = SharedPreferences.windowMode
        prefs.snakeBlockBasis = SharedPreferences.snekBasis(theme: theme, family: family)
        prefs.snakeCommitsPerBlock = SharedPreferences.snekPerBlock(theme: theme, family: family)
        return ActivityEntry(
            date: .now,
            configuredPeriod: .weekly,
            period: .weekly,
            username: github.username,
            snapshot: previewSnapshot,
            preferences: prefs
        )
    }

    private func blockworkSettings(_ family: WidgetLayoutFamily) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BLOCKS")
                    .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1)
                VStack(spacing: 0) {
                    ForEach(WidgetPane.allCases) { pane in
                        blockLibraryRow(pane)
                    }
                }
                .overlay { Rectangle().stroke(studioInk, lineWidth: 2) }
                blockColorEditor
            }
            .frame(width: 300)

            ScrollView(.horizontal, showsIndicators: false) {
                familyComposer(
                    family,
                    width: composerSize(family).width,
                    height: composerSize(family).height
                )
            }
        }
        .padding(16)
        .background(studioPaper)
        .foregroundStyle(studioInk)
    }

    private func composerSize(_ family: WidgetLayoutFamily) -> (width: CGFloat, height: CGFloat) {
        switch family {
        case .small: (180, 180)
        case .medium: (380, 180)
        case .large: (360, 320)
        case .extraLarge: (620, 300)
        }
    }


    private func blockLibraryRow(_ block: WidgetPane) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedBlock = block
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(studioMuted)

                Image(systemName: block.studioSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.displayName)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    Text(block.detail)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(studioMuted)
                        .lineLimit(1)
                }

                Spacer()

                if selectedBlock == block {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(studioOrange)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 46)
            .background(selectedBlock == block ? studioLime.opacity(0.26) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(studioInk.opacity(0.22)).frame(height: 1)
        }
        .onDrag {
            selectedBlock = block
            draggedPane = block
            draggedOrigin = nil
            return NSItemProvider(object: block.rawValue as NSString)
        }
    }

    private var blockColorEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SELECTED BLOCK")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(studioMuted)
                    Text(selectedBlock.displayName)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                }
                Spacer()
                Image(systemName: selectedBlock.studioSymbol)
                    .font(.system(size: 15, weight: .black))
            }

            HStack(spacing: 8) {
                ForEach(WidgetBlockColor.allCases) { color in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            blockColors[selectedBlock] = color
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(studioSwatch(color))
                                .frame(width: 24, height: 24)
                            if selectedBlockColor == color {
                                Image(systemName: color == .automatic ? "a.circle.fill" : "checkmark")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(color == .ink ? studioPaper : studioInk)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(color.displayName)
                }
            }

            Text("Auto uses Blockwork's semantic poster color for this block.")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(studioMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(studioInk.opacity(0.055))
        .overlay {
            Rectangle().stroke(studioInk, lineWidth: 2)
        }
    }

    private func familyComposer(
        _ family: WidgetLayoutFamily,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(family.displayName.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(0.9)
                Spacer()
                Text("\(family.slotCount) \(family.slotCount == 1 ? "SLOT" : "SLOTS")")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundStyle(studioMuted)
            }

            VStack(spacing: 0) {
                HStack {
                    Text(github.username.isEmpty ? "@yjay18" : "@\(github.username)")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                    Spacer()
                    Text("W")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .foregroundStyle(studioInk)
                        .background(studioLime)
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .foregroundStyle(studioPaper)
                .background(studioInk)

                GeometryReader { proxy in
                    familySlotLayout(family, size: proxy.size)
                        .padding(3)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .background(studioInk)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: family == .small ? 24 : 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: family == .small ? 24 : 20, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 14, y: 9)
        }
    }

    @ViewBuilder
    private func familySlotLayout(_ family: WidgetLayoutFamily, size: CGSize) -> some View {
        let slots = familyLayouts[family]
            ?? WidgetModularPreferences.defaults.familyLayouts[family]
            ?? []
        let spacing: CGFloat = 3

        switch family {
        case .small:
            if let block = slots.first {
                composerSlot(family: family, index: 0, block: block)
            }
        case .medium:
            HStack(spacing: spacing) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, block in
                    composerSlot(family: family, index: index, block: block)
                }
            }
        case .large:
            VStack(spacing: spacing) {
                if let first = slots.first {
                    composerSlot(family: family, index: 0, block: first)
                        .frame(height: max(0, (size.height - spacing) * 0.44))
                }
                HStack(spacing: spacing) {
                    ForEach(Array(slots.dropFirst().enumerated()), id: \.offset) { offset, block in
                        composerSlot(family: family, index: offset + 1, block: block)
                    }
                }
            }
        case .extraLarge:
            HStack(spacing: spacing) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, block in
                    composerSlot(family: family, index: index, block: block)
                }
            }
        }
    }

    private func composerSlot(
        family: WidgetLayoutFamily,
        index: Int,
        block: WidgetPane
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedBlock = block
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: block.studioSymbol)
                    Spacer()
                    Text("\(index + 1)")
                }
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .opacity(0.68)

                Spacer(minLength: 0)

                Text(block.displayName)
                    .font(.system(size: family == .extraLarge ? 10 : 9, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(blockPreviewValue(block))
                    .font(.system(size: family == .small ? 18 : 15, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .padding(family == .small ? 9 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(studioBlockForeground(block))
            .background(studioBlockFill(block))
            .overlay {
                Rectangle()
                    .stroke(
                        selectedBlock == block ? studioOrange : Color.clear,
                        lineWidth: 3
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            selectedBlock = block
            draggedPane = block
            draggedOrigin = WidgetSlotOrigin(family: family, index: index)
            return NSItemProvider(object: block.rawValue as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: WidgetSlotDropDelegate(
                destination: WidgetSlotOrigin(family: family, index: index),
                layouts: $familyLayouts,
                draggedPane: $draggedPane,
                draggedOrigin: $draggedOrigin
            )
        )
    }

    private var selectedBlockColor: WidgetBlockColor {
        blockColors[selectedBlock] ?? .automatic
    }

    private func studioSwatch(_ color: WidgetBlockColor) -> Color {
        switch color {
        case .automatic:
            studioPaper
        case .orange: studioOrange
        case .lime: studioLime
        case .sky: studioSky
        case .ink: studioInk
        case .paper: studioPaper
        }
    }

    private func studioBlockFill(_ block: WidgetPane) -> Color {
        let selected = blockColors[block] ?? .automatic
        if selected != .automatic {
            return studioSwatch(selected)
        }
        switch block {
        case .additions: return studioOrange
        case .deletions, .snake: return studioInk
        case .summary, .insights: return studioLime
        case .activity, .activityTable: return studioSky
        case .repositories: return studioPaper
        }
    }

    private func studioBlockForeground(_ block: WidgetPane) -> Color {
        let selected = blockColors[block] ?? .automatic
        let fillChoice: WidgetBlockColor
        if selected == .automatic {
            fillChoice = block == .deletions || block == .snake ? .ink : .paper
        } else {
            fillChoice = selected
        }
        return fillChoice == .ink ? studioPaper : studioInk
    }

    private func blockPreviewValue(_ block: WidgetPane) -> String {
        switch block {
        case .additions: "+25k"
        case .deletions: "−1k"
        case .summary: "29 / 3"
        case .activity: "▂▇▃▅"
        case .activityTable: "▦ ▦"
        case .insights: "+24k"
        case .repositories: "3 repos"
        case .snake: "snek happy"
        }
    }

    private var studioInk: Color {
        Color(red: 0.063, green: 0.067, blue: 0.059)
    }

    private var studioPaper: Color {
        Color(red: 0.937, green: 0.898, blue: 0.804)
    }

    private var studioOrange: Color {
        Color(red: 0.953, green: 0.357, blue: 0.173)
    }

    private var studioLime: Color {
        Color(red: 0.725, green: 0.863, blue: 0.235)
    }

    private var studioSky: Color {
        Color(red: 0.412, green: 0.729, blue: 0.859)
    }

    private var studioMuted: Color {
        Color(red: 0.46, green: 0.45, blue: 0.41)
    }
    private var connectionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !github.hasStoredToken {
                    githubConnectionSection
                } else {
                    connectionManagementSection
                    if let message = github.message {
                        connectionError(message)
                    }
                    if let notice = github.notice {
                        connectionNotice(notice)
                    }
                }
                refreshIntervalSection
                snekBlockSection
                widgetConfigurationGuide
            }
            .padding(28)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var refreshIntervalSection: some View {
        GroupBox("Widget refresh") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("How often widgets reload", selection: $refreshInterval) {
                    ForEach(WidgetRefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .pickerStyle(.menu)

                Text("Applies to every widtget widget. Automatic uses a system-tuned default; macOS still meters refreshes against the daily budget, so very short intervals are not guaranteed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: refreshInterval) { _, newValue in
            SharedPreferences.refreshInterval = newValue
            reloadWidgets()
        }
    }

    private var snekBlockSection: some View {
        GroupBox("Commit snek blocks") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Each block counts", selection: $snakeBlockBasis) {
                    ForEach(SnakeBlockBasis.allCases) { basis in
                        Text(basis.displayName).tag(basis)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("\(snakeBlockBasis.unitNoun.capitalized) per block")
                    Spacer()
                    TextField("", value: $snakeUnitsPerBlock, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Text("The commit snek grows one block per \(snakeUnitsPerBlock) \(snakeBlockBasis.unitNoun), across every theme. Line-based options want a larger number than commits.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: snakeBlockBasis) { _, newValue in
            SharedPreferences.snakeBlockBasis = newValue
            snakeUnitsPerBlock = newValue.defaultPerBlock
            SharedPreferences.snakeUnitsPerBlock = snakeUnitsPerBlock
            reloadWidgets()
        }
        .onChange(of: snakeUnitsPerBlock) { _, newValue in
            SharedPreferences.snakeUnitsPerBlock = max(1, newValue)
            reloadWidgets()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Color(red: 0.22, green: 0.80, blue: 0.46))
                .frame(width: 42, height: 42)
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(github.hasStoredToken && !github.username.isEmpty ? "@\(github.username)" : "GitHub activity")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if github.hasStoredToken, let lastRefresh = github.lastRefresh {
                    Text("Updated \(lastRefresh, style: .relative)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect GitHub and configure the widget")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if github.hasStoredToken {
                if github.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(github.phase == .refreshing ? "Refreshing…" : "Refresh") {
                    Task { await github.refresh(scope: .allBranches) }
                }
                .disabled(github.isBusy)
                .help("Discover activity across every accessible branch")

                Button {
                    showingDisconnectConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Disconnect GitHub")
                .disabled(github.isBusy)
            }
        }
    }

    private var githubConnectionSection: some View {
        GroupBox("GitHub activity") {
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Fine-grained personal access token", text: $github.tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard github.canConnect else { return }
                        Task { await github.connect() }
                    }

                HStack {
                    Link(
                        "Create a fine-grained token",
                        destination: GitHubTokenTemplate.url()
                    )
                    .font(.system(size: 11, weight: .medium))

                    Spacer()

                    if github.isBusy {
                        ProgressView().controlSize(.small)
                    }

                    Button(github.phase == .connecting ? "Connecting…" : "Connect GitHub") {
                        Task { await github.connect() }
                    }
                    .disabled(!github.canConnect)
                }

                Text("Choose your account as the resource owner, select the repositories to include, and leave the prefilled Contents permission at read-only. Organization connections can be added next.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = github.message {
                    connectionError(message)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var connectionManagementSection: some View {
        GroupBox("GitHub connections") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(github.connections) { connection in
                    connectionRow(connection)
                    if connection.id != github.connections.last?.id {
                        Divider()
                    }
                }

                Divider()

                tokenDisclosure(title: "Replace account token", isExpanded: $isReplacingAccountToken) {
                    VStack(alignment: .leading, spacing: 8) {

                    HStack {
                        Link(
                            "Create replacement token",
                            destination: GitHubTokenTemplate.url()
                        )
                        .font(.system(size: 10, weight: .medium))

                        Spacer()

                        Text("Include your private repositories and Contents: Read-only.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    SecureField(
                        "Paste replacement account token",
                        text: $github.replacementAccountTokenInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard github.canReplaceAccountToken else { return }
                        Task { await github.replaceAccountToken() }
                    }

                    HStack(alignment: .top) {
                        Text("widtget checks the token belongs to @\(github.username), refreshes every branch, then replaces the saved Keychain token. Your current token stays active if validation fails.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button(github.phase == .connecting ? "Replacing…" : "Replace token") {
                            Task { await github.replaceAccountToken() }
                        }
                        .disabled(!github.canReplaceAccountToken)
                    }
                    }
                }

                Divider()

                tokenDisclosure(title: "Add organization", isExpanded: $isAddingOrganization) {
                    VStack(alignment: .leading, spacing: 8) {

                    TextField("GitHub organization name", text: $github.organizationInput)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Link(
                            "1. Create read-only token on GitHub",
                            destination: github.organizationTokenURL
                        )
                        .font(.system(size: 10, weight: .medium))
                        .disabled(!github.canCreateOrganizationToken)

                        Spacer()

                        Text("Select the repositories on GitHub, then generate the token.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    SecureField(
                        "2. Paste the organization token",
                        text: $github.additionalTokenInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard github.canAddToken else { return }
                        Task { await github.addOrganization() }
                    }

                    HStack(alignment: .top) {
                        Text("widtget verifies the organization and repository access before saving. If approval is required, ask an organization owner to approve the token first.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button(github.phase == .connecting ? "Adding…" : "Add organization") {
                            Task { await github.addOrganization() }
                        }
                        .disabled(!github.canAddToken)
                    }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func connectionRow(_ connection: GitHubConnectionSummary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: connection.kind == .account ? "person.crop.circle.fill" : "building.2.fill")
                .font(.system(size: 17))
                .foregroundStyle(connection.kind == .account ? Color.secondary : Color.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.kind == .account ? "@\(connection.owner)" : connection.owner)
                    .font(.system(size: 12, weight: .semibold))

                if let repositoryCount = connection.repositoryCount,
                   let privateRepositoryCount = connection.privateRepositoryCount {
                    Text("\(repositoryCount) \(repositoryCount == 1 ? "repository" : "repositories") · \(privateRepositoryCount) private")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(connection.kind == .account ? "GitHub account" : "Connected resource owner")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if connection.kind == .organization {
                Button {
                    organizationPendingRemoval = connection
                    showingRemoveOrganizationConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove \(connection.owner)")
                .disabled(github.isBusy)
            }
        }
    }

    private func connectionError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func connectionNotice(_ message: String) -> some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var widgetConfigurationGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DashboardPalette.green)
                    .frame(width: 34, height: 34)
                    .background(DashboardPalette.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Per-widget controls stay with the widget")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Right-click a widtget on the desktop and choose Edit Widget.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Each widget chooses its own period, window, repository detail, and commits per snek block. Widget Studio supplies the shared pane order and colorway.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tokenDisclosure<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded.wrappedValue ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }
    private func themeOverrideBinding(_ family: WidgetLayoutFamily) -> Binding<WidgetVisualTheme?> {
        Binding(
            get: { themeOverrides[family] },
            set: { newValue in
                if let newValue {
                    themeOverrides[family] = newValue
                } else {
                    themeOverrides.removeValue(forKey: family)
                }
                SharedPreferences.setThemeOverride(newValue, for: family)
                reloadWidgets()
            }
        )
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidtgetWidgetKind.value)
    }

    private func migrateToFixedDefaultIfNeeded() {
        let currentVersion = SharedPreferences.defaults.integer(
            forKey: SharedPreferences.Key.themeScopeVersion
        )
        guard currentVersion < 1 else { return }

        visualTheme = .defaultTheme
        SharedPreferences.defaults.set(1, forKey: SharedPreferences.Key.themeScopeVersion)
        saveWidgetStudio()
    }

    private func saveWidgetStudio() {
        SharedPreferences.saveModularPreferences(
            WidgetModularPreferences(
                paneOrder: paneOrder,
                enabledPanes: enabledPanes,
                colorway: blockworkColorway,
                visualTheme: visualTheme,
                familyLayouts: familyLayouts,
                blockColors: blockColors
            )
        )
        reloadWidgets()
    }
}

private struct WidgetSlotOrigin: Equatable {
    let family: WidgetLayoutFamily
    let index: Int
}

private struct SnekKey: Hashable {
    let theme: WidgetVisualTheme
    let family: WidgetLayoutFamily
}

private struct WidgetSlotDropDelegate: DropDelegate {
    let destination: WidgetSlotOrigin
    @Binding var layouts: [WidgetLayoutFamily: [WidgetPane]]
    @Binding var draggedPane: WidgetPane?
    @Binding var draggedOrigin: WidgetSlotOrigin?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedPane else { return false }

        var destinationLayout = layouts[destination.family]
            ?? WidgetModularPreferences.defaults.familyLayouts[destination.family]
            ?? []
        guard destinationLayout.indices.contains(destination.index) else { return false }

        let displaced = destinationLayout[destination.index]
        destinationLayout[destination.index] = draggedPane
        layouts[destination.family] = destinationLayout

        if let draggedOrigin,
           draggedOrigin != destination {
            var sourceLayout = layouts[draggedOrigin.family]
                ?? WidgetModularPreferences.defaults.familyLayouts[draggedOrigin.family]
                ?? []
            if sourceLayout.indices.contains(draggedOrigin.index) {
                sourceLayout[draggedOrigin.index] = displaced
                layouts[draggedOrigin.family] = sourceLayout
            }
        }

        self.draggedPane = nil
        self.draggedOrigin = nil
        return true
    }
}

private struct WidgetPaneDropDelegate: DropDelegate {
    let destination: WidgetPane
    @Binding var panes: [WidgetPane]
    @Binding var draggedPane: WidgetPane?

    func dropEntered(info: DropInfo) {
        guard let draggedPane,
              draggedPane != destination,
              let sourceIndex = panes.firstIndex(of: draggedPane),
              let destinationIndex = panes.firstIndex(of: destination)
        else {
            return
        }

        withAnimation(.snappy(duration: 0.2)) {
            panes.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedPane = nil
        return true
    }
}

private extension WidgetPane {
    var studioSymbol: String {
        switch self {
        case .additions: "plus"
        case .deletions: "minus"
        case .summary: "number"
        case .activity: "chart.bar.fill"
        case .activityTable: "square.grid.3x3.fill"
        case .insights: "scope"
        case .repositories: "shippingbox.fill"
        case .snake: "circle.grid.3x3.fill"
        }
    }
}

#Preview {
    WidgetSettingsView()
}
