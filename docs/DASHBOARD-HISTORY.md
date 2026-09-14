# Dashboard history

The host dashboard has Overview, Repositories and Activity views. Its history cache
is separate from WidgetKit snapshots and contains repository metadata, commit subjects,
authored dates and line statistics. Tokens remain in the host Keychain.

The repository list includes every repository returned by the connected account's
installation endpoints or advanced token connections, including inactive and archived
repositories. Full owner/name identifiers prevent similarly named repositories from
colliding. Repository rows distinguish unsynced activity from a verified zero count.

Sync history fetches the selected date window, its comparison and the trailing 13-week
calendar. Historical selections also backfill through the current date. Every branch
is scanned, and commits are deduplicated by repository and SHA. Previously fetched
commit details are reused. Sync publishes the catalog immediately and checkpoints
successful results; stop/retry preserves completed work. Per-repository coverage is
recorded only after that repository's scan finishes. Permission/network failures retain
cached activity with an error. Rate limits stop the scan and expose GitHub's retry time.
Repositories removed from the accessible catalog are removed from the history cache.

A complete past calendar period compares to the complete previous calendar period.
An unfinished period compares to the same elapsed part, capped at the previous period's
end. Custom ranges include the selected end date and compare to the preceding range.
Current charts and comparisons are evaluated as of the history sync timestamp; use
Sync history to move that timestamp forward. Comparisons are withheld when either
period has incomplete coverage. Lines are descriptive activity, not productivity.

The cache lives in the host's Application Support/com.yjay18.widtget/dashboard-history.json
and is removed on Disconnect. Favourites use host preferences. Widget settings and
snapshot formats are unchanged.

Validation:

- `zsh script/test_dashboard_history.sh`: DST/calendar boundaries, comparison windows,
  coverage gaps, deduplication, filtering and cache serialization.
- `zsh script/test_dashboard_service.sh`: real service with mocked GitHub responses;
  pagination, inactive/private/archived repositories, cache reuse, partial failures,
  branch deduplication and removed access.
- `./script/build_and_run.sh build`: native host/widget compilation.
