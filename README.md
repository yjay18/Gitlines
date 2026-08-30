# Gitlines

`Gitlines` is a widget-first native macOS product for focused code-activity snapshots. Its host app installs the WidgetKit extension, manages the GitHub connection and data refresh, presents snapshot analytics, and controls shared appearance preferences.

## Features

- **Daily, weekly, and monthly views** — choose a period per widget and cycle between them directly from the widget.
- **Calendar or rolling windows** — show today, this week, or this month, or switch to the last 24 hours, 7 days, or 30 days.
- **Real GitHub activity** — exact commits, additions, deletions, net change, active intervals, peak activity, averages, and repository rankings.
- **Activity across branches** — discovers recent work beyond the default branch and deduplicates commits that appear on more than one branch.
- **Personal and organization repositories** — connect a personal GitHub account and add organization access independently with fine-grained, read-only tokens.
- **Four widget sizes** — purpose-built small, medium, large, and extra-large layouts rather than one stretched design.
- **Snapshot dashboard** — review the activity pulse, change shape, rhythm, repository ledger, and a plain-language review in the host app, with its own daily/weekly/monthly and calendar/rolling toggles.
- **Resilient refreshes** — configurable refresh timing, lightweight widget refreshes, remembered activity branches, cached results, stale-data indicators, and retry states.
- **Native macOS behavior** — WidgetKit configuration, desktop vibrant-mode support, immediate timeline reloads, and App Store-delivered updates.

## Themes

Every theme uses the same activity snapshot; changing the look never changes the numbers.

- **Default** — a restrained dark dashboard with bright additions, coral deletions, compact charts, and clear repository rows.
- **Blockwork** — a modular studio theme. Drag panes into different slots for each widget size, hide panes you do not need, and choose Workshop, Blueprint, or Newsprint colorways plus per-block colors. Available panes include additions, deletions, commit summary, activity bars, activity table, insights, repositories, and commit snek.
- **Glasshouse** — dark translucent surfaces, hairline separators, mint additions, rose deletions, and very little chrome.
- **Phosphor** — terminal-inspired monospaced output with block-glyph charts, green activity, amber deletions, and `git log`-style repository rows.
- **Broadsheet** — warm newsprint, serif typography, press-red deletions, dotted day-book rows, and engraved activity bars.
- **Arcade** — a four-color handheld-console palette built around the commit snek, with commits as score and peak activity as the high score.

The Widget Studio provides live previews for every size, a global theme, optional per-size theme overrides, repository-density controls, refresh timing, and configurable snek units based on commits, additions, deletions, or net lines.

## Open and preview

1. Open `widtget.xcodeproj` in Xcode 15.4 or newer.
2. Select both the `widtget app` and `widtget` extension targets, then assign the same development team under Signing & Capabilities.
3. Confirm that `group.com.yjay18.widtget` is available to both targets as an App Group.
4. Run the `widtget app` target once so macOS registers the embedded widget.
5. Connect GitHub in the host app using the setup below.
6. Open `WidtgetPreviews.swift` to inspect all widget families and states in the canvas.
7. Add `Gitlines` from the macOS widget gallery. Edit an individual widget to select Daily, Weekly, or Monthly.

The app controls global appearance preferences. The period remains a native per-widget setting, so multiple widgets can show different time ranges at once; the dashboard has its own period toggle.

The project targets macOS 14 because it uses native App Intent widget configuration and interactive retry.

## Connect GitHub

1. Use **Create a fine-grained token** in the host app. Choose your GitHub account as the resource owner, select the repositories to include, and keep the prefilled **Contents: read-only** permission.
2. Paste the token into the host app and select **Connect GitHub**.
3. To include repositories owned by an organization, enter its GitHub name under **Add organization**. The generated GitHub link preselects that organization and the minimum read-only permission; choose the repositories, generate the token, paste it back into `Gitlines`, and select **Add organization**.
4. If the organization requires approval, ask an organization owner to approve the fine-grained token before adding it. A pending token cannot expose private repositories.

GitHub limits each fine-grained personal access token to one resource owner, so every additional organization needs its own token. `Gitlines` validates that the organization is actually visible to the token and that all connected tokens authenticate the same GitHub user. The connection manager shows each owner and accessible repository count, supports independent organization removal, stores all tokens only in Keychain, merges repositories across owners, and deduplicates repositories and commits.

Activity is calculated from commits authored by the authenticated user across every accessible branch. The **Fixed** window uses the current local calendar day, week, or month; **Rolling** uses the last 24 hours, seven days, or 30 days. Both are cached on every refresh so the setting can switch immediately. Commits reachable from multiple branches are deduplicated by repository and SHA, and addition/deletion totals come from GitHub's individual commit statistics.

Select **Refresh** in the host app to perform a full branch discovery and remember branches containing recent activity. Refreshing from the widget is intentionally lighter: it checks each active repository's default branch plus the previously discovered activity branches. Opening the app also uses this lightweight refresh when the cache is older than 15 minutes. If refresh fails, the widget keeps the last successful snapshot and marks it stale.

## Command-line development

The repository includes a repeatable Xcode build loop for Codex and local terminal work:

```sh
./script/build_and_run.sh build
```

That command performs an unsigned compile check. Unsigned validation artifacts and signed run artifacts use separate directories under `.build/DerivedData`; the validation copy is unregistered after compiling so it cannot replace the Keychain-enabled app in Launch Services. To use the Personal Team signing configured in Xcode, register the widget extension, and launch the host app, run:

```sh
./script/build_and_run.sh run
```

XcodeBuildMCP settings live in `.xcodebuildmcp/config.yaml`; they enable macOS builds, project discovery, and Xcode 26's IDE bridge while keeping the project and host-app scheme selected by default.

## Data boundary

`GitHubActivityService` in `widtgetApp/GitHubActivityService.swift` is the only GitHub API client. The host app keeps personal access tokens in the app-scoped macOS data-protection Keychain, turns API responses into display-ready daily, weekly, and monthly snapshots, and writes those snapshots atomically to the shared App Group container. `ActivityDataSource` in `widtget/Provider/ActivityProvider.swift` only reads that cache, so the widget extension never receives tokens or makes authenticated requests.

Deterministic snapshots remain limited to Xcode previews. A widget without cached data displays a setup prompt, and tapping a connected widget opens the authenticated user's GitHub profile. `Gitlines` does not claim to be an official GitHub product.

## Packaging

The `widtget app` target builds `gitlines.app` and embeds and signs `widtget.appex`. Normal use happens from the widget, while the host app provides refresh, connection management, snapshot analytics, and appearance preferences.
