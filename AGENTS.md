# Gitlines development guide

## Product boundary

- `Gitlines` is a native macOS WidgetKit product with a deliberately small host app.
- Keep the widget as the primary product. The host app only manages shared widget preferences and credentials/data refresh when live GitHub data is added.
- The public product and app name is `Gitlines`. The existing `widtget` project, schemes, target names, bundle identifiers, App Group, Keychain service, and refresh URL scheme are compatibility identifiers; do not rename them without an explicit migration plan.
- Preserve the dark, number-first visual hierarchy and native Daily/Weekly/Monthly App Intent configuration. The widget period pill cycles daily → weekly → monthly; monthly activity is bucketed week by week (five cells, labelled W1–W5) and its peak/active/average analytics read from those week cells. Every theme renders periods through the shared `ActivityIntervalLabels`, so new periods flow to all themes and sizes automatically.

## Xcode project

- Project: `widtget.xcodeproj`
- Host app scheme: `widtget app`
- Widget extension scheme: `widtget`
- Built host app: `gitlines.app`
- Deployment target: macOS 14+
- App bundle ID: `com.yjay18.widtget`
- Widget bundle ID: `com.yjay18.widtget.widget`
- Shared App Group: `group.com.yjay18.widtget`

The two targets must use the same signing team and App Group. Do not replace or remove the developer team configured by the user unless explicitly requested.

## Build and run

Use the repository entrypoint:

```sh
./script/build_and_run.sh build
```

This performs an unsigned Debug build, suitable for compile validation in an agent sandbox.

To build with the user's Xcode signing configuration and launch the host app:

```sh
./script/build_and_run.sh run
```

The signed run is required for macOS to register the embedded widget extension correctly. Build artifacts stay under `.build/DerivedData` and must not be committed.

## Architecture

- `widtgetApp/`: minimal SwiftUI host and shared appearance controls.
- `widtget/`: WidgetKit extension, App Intent configuration, timeline provider, models, and size-specific views.
- `Shared/WidgetPreferences.swift`: App Group preferences shared by both targets.
- `widtget/Provider/ActivityProvider.swift`: current fixture data and the integration seam for live GitHub activity.

## Widget themes

A theme owns type, chrome, and pane shape; a colorway only swaps hues. `WidgetVisualTheme`
(in `Shared/WidgetPreferences.swift`) selects one, and every theme renders the same
`ActivitySnapshot` — the numbers never change, only their treatment.

Two families of theme live side by side:

- **Blockwork** is modular: `ComposedWidgetView` in `WidtgetWidgetView.swift` lays out
  user-arranged panes (`WidgetPane`) per family, with drag-and-drop editing in the host.
  Modular slot/colorway/block-color editing stays scoped to Blockwork.
- **Default and the four themes below are fixed**: each is one hand-composed layout per
  family, like `DefaultWidgetView`. They ignore `familyLayouts`/`blockColors`.

### Adding a fixed theme (the pattern every new theme follows)

1. Add a case to `WidgetVisualTheme` and its `displayName` switch in
   `Shared/WidgetPreferences.swift`.
2. Add one `…WidgetView.swift` under `widtget/Views/` exposing
   `init(entry:preferences:family:)` and switching on `WidgetLayoutFamily`. Paint the
   theme's own `.background(...)`, but read `@Environment(\.widgetRenderingMode)` and
   fall back to `Color.clear` when it is not `.fullColor`: macOS renders desktop
   widgets in vibrant (de-emphasized) mode when the desktop is unfocused, dropping
   colour for luminance. A light theme must also render its content in bright semantic
   colours (`.primary`/`.secondary`) in that mode or it whites out — see Broadsheet.
3. Route it from the `switch entry.preferences.visualTheme` in `WidtgetWidgetView.body`,
   and give it a base colour in `WidgetVisualTheme.containerBackgroundColor`
   (`widtget/Views/ThemeMetrics.swift`) so the widget's bleed area matches.
4. Register the new file in `widtget.xcodeproj/project.pbxproj` (the project is not
   file-system-synchronized): add a `PBXFileReference` (`B1…`), a `PBXBuildFile` (`A1…`),
   a child in the `Views` group, and an entry in the widget target's `Sources` phase.
5. The host theme picker (`WidgetSettingsView`) iterates `WidgetVisualTheme.allCases`, so
   it adopts the case automatically; only Blockwork shows the composer, every other theme
   shows the fixed-layout overview.

Shared derivations (`net`, `averagePerCommit`, `activeIntervals`, `peakIndex`) and the
interval-label helper live in `widtget/Views/ThemeMetrics.swift` — reuse them, don't
recompute per theme.

### The four themes

- **Glasshouse** — the one that disappears. Dark translucent ground, SF, hairline
  separators, no frame of its own; colour appears only on the data (mint additions, rose
  deletions), everything else white at a few opacities. Cheapest to build: Default's
  hierarchy in system chrome. Strongest at small/medium beside system widgets.
  Palette: `#1c1d21 · #f2f3f5 · #7ee2a8 · #f0868c`.
- **Phosphor** — the week as terminal output. `.monospaced` throughout; block glyphs
  (`▁▃▂█▆▄▁`) do the charting instead of bar views; deletions in amber; a caret marks the
  widget as live. Strongest at medium/large where the repository rows read as a `git log`.
  Palette: `#06090a · #4af08a · #1f7a4a · #ffb340`.
- **Broadsheet** — Blockwork's opposite twin: same newsprint stock, but hairlines and a
  high-contrast serif (system New York, `.serif`) instead of slabs and heavy mono. Front-page
  figure, a day book with dotted leaders, activity engraved as hatched rules; press red on
  deletions. Wants column space — best at large/XL. Palette: `#e9e4d5 · #19170f · #9e2f1b`.
  Upgrade path: bundle Bodoni Moda for a closer match to the mockup.
- **Arcade** — built around the commit-snek pane that already exists. Four-colour Game Boy
  palette, pixel grid for the snek playfield and bars; commits are score, peak day is a
  hi-score. Best at XL where the playfield is the point. Palette:
  `#0f380f · #306230 · #8bac0f · #9bbc0f · #d94f1e (food)`. Ships with `.monospaced`;
  upgrade path: bundle a pixel face (Silkscreen) for the true arcade look.

Mockups of all four (small + medium) live in the project's design board artifact.

When adding live GitHub data, store credentials in Keychain from the host app, fetch there, write only display-ready snapshots into the App Group container, and reload WidgetKit timelines. Never place a token in source, plist files, UserDefaults, or widget timeline entries.

## Validation

- Run the smallest relevant check first; at minimum, run `./script/build_and_run.sh build` after Swift or project changes.
- Use Xcode previews to inspect all supported widget families when layout changes.
- Preserve user-authored signing/project changes and unrelated worktree changes.
- Do not add commit co-author trailers.
