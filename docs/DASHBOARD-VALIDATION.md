# Dashboard validation — 2026-09-10

- Working branch: `claude/gitlines-dashboard-analytics-d59293`.
- `zsh script/test_dashboard_history.sh`: passed calendar and rolling windows,
  equivalent elapsed comparisons, custom end dates, 23-hour DST calendar days versus
  24-hour rolling days, coverage gaps, resync deduplication and cache serialization.
- `zsh script/test_dashboard_service.sh`: passed 101-repository pagination,
  private/archived/empty repository handling, duplicate branches, cached detail reuse,
  partial permission failures and removal of inaccessible repository data.
- `./script/test_github_signin.sh`: all existing sign-in protocol checks passed.
- Unsigned and signed Xcode host/widget builds passed; `git diff --check` passed.
- Installed signed binary matched the build (SHA-256:
  `e25a390de2ccb183562d00c222d4f649456630a9ea5fb9c5aa4a50edde270335`).
- Only `/Users/yuuvjauhari/Applications/Gitlines.app` was running after installation.
- Native screenshots inspected for Default, Blockwork, Glasshouse, Phosphor,
  Broadsheet and Arcade. Explorer controls fit the 880-point window and retain state
  across theme changes. Verified previous month Aug 1–31 against July, forward
  navigation, rolling week and custom date controls. Restored Monthly/Calendar/Phosphor.
- Live API returned a rate limit before catalog discovery, with reset at 16:30 Dublin.
  Verified the installed app retained the saved 847-commit snapshot and exposed the
  limit, automatic retry time and cancellation control. Live history backfill is pending
  that external reset; mock coverage tests do not certify a completed live sync.

## Live reset recovery

At 16:31 Dublin, the installed app automatically resumed after the reset without
manual retry. Its host cache contained 33 accessible repositories, 227 fetched commits
and coverage records for 17 repositories, with zero repository errors at that point.
The initial history backfill was still running. The catalog is available before all
history is complete. Native UI control became intermittent again after the theme/date
checks, so repository detail interactions with the newly fetched data have not all
been manually replayed; the service and derivation tests above cover their data path.
