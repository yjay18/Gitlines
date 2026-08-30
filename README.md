# widtget

`widtget` is a widget-first native macOS product for focused code-activity snapshots. Its small host app installs the WidgetKit extension, manages the GitHub connection and data refresh, controls shared appearance preferences, and renders an analytics dashboard from the same display-ready snapshots the widgets use.

## What is included

- Native `AppIntentConfiguration` with **Daily**, **Weekly**, and **Monthly** modes.
- Purpose-built small, medium, large, and extra-large layouts.
- Large tabular addition/deletion totals, compact commit and repository metrics, proportional repository bars, and two-color activity visualizations.
- Loading, no-activity, API-error/retry, stale-data, and “+N more” visual states.
- A minimal macOS settings window for connecting GitHub and controlling repository breakdowns, activity visualization, update status, and repository density.
- Exact commit, addition, and deletion totals fetched by the host app for the authenticated user's accessible repositories.
- A Keychain-protected GitHub token and display-ready App Group snapshots, with no credential or network access in the widget extension.
- Shared App Group preferences with immediate WidgetKit timeline reloads.
- Deterministic preview data for every layout, including the requested `+29,696` and `−43,332` daily headline values.
- Repository ranking by total lines changed, then commit count.

## Open and preview

1. Open `widtget.xcodeproj` in Xcode 15.4 or newer.
2. Select both the `widtget app` and `widtget` extension targets, then assign the same development team under Signing & Capabilities.
3. Confirm that `group.com.yjay18.widtget` is available to both targets as an App Group.
4. Run the `widtget app` target once so macOS registers the embedded widget.
5. Connect GitHub in the host app using the setup below.
6. Open `WidtgetPreviews.swift` to inspect all widget families and states in the canvas.
7. Add `widtget` from the macOS widget gallery. Edit an individual widget to select Daily, Weekly, or Monthly.

The app controls global appearance preferences. The period remains a native, per-widget setting so multiple instances can show different periods; the dashboard has its own period toggle.

The project targets macOS 14 because it uses native App Intent widget configuration and interactive retry.

## Connect GitHub

1. Use **Create a fine-grained token** in the host app. Choose your GitHub account as the resource owner, select the repositories to include, and keep the prefilled **Contents: read-only** permission.
2. Paste the token into the host app and select **Connect GitHub**.
3. To include repositories owned by an organization, enter its GitHub name under **Add organization**. The generated GitHub link preselects that organization and the minimum read-only permission; choose the repositories, generate the token, paste it back into `widtget`, and select **Add organization**.
4. If the organization requires approval, ask an organization owner to approve the fine-grained token before adding it. A pending token cannot expose private repositories.

GitHub limits each fine-grained personal access token to one resource owner, so every additional organization needs its own token. `widtget` validates that the organization is actually visible to the token and that all connected tokens authenticate the same GitHub user. The connection manager shows each owner and accessible repository count, supports independent organization removal, stores all tokens only in Keychain, merges repositories across owners, and deduplicates repositories and commits.

Activity is calculated from commits authored by the authenticated user across every accessible branch. The **Fixed** window uses the current local calendar day, week, or month; **Rolling** uses the last 24 hours, 7 days, or 30 days. Both are cached on every refresh so the setting can switch immediately. Commits reachable from multiple branches are deduplicated by repository and SHA, and addition/deletion totals come from GitHub's individual commit statistics.

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

`GitHubActivityService` in `widtgetApp/GitHubActivityService.swift` is the only GitHub API client. The host app keeps personal access tokens in the app-scoped macOS data-protection Keychain, turns API responses into display-ready daily and weekly snapshots, and writes those snapshots atomically to the shared App Group container. `ActivityDataSource` in `widtget/Provider/ActivityProvider.swift` only reads that cache, so the widget extension never receives tokens or makes authenticated requests.

Deterministic snapshots remain limited to Xcode previews. A widget without cached data displays a setup prompt, and tapping a connected widget opens the authenticated user's GitHub profile. `widtget` does not claim to be an official GitHub product.

## Packaging

The `widtget app` target embeds and signs `widtget.appex`. The host has no product dashboard: normal use happens from the widget, while the app is reopened only to refresh GitHub activity, manage the connection, or change appearance preferences.
