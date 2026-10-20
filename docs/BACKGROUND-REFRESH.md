# Background widget refresh

In Connections → Widget refresh, turn on **Refresh widgets when Gitlines is
closed**. macOS may ask you to allow Gitlines under System Settings → General →
Login Items & Extensions. The same switch turns background refresh off.

Gitlines embeds a user launch agent registered through Apple's `SMAppService`.
Every 15 minutes, while you are logged in, it starts the signed host executable
with `--background-refresh`. That mode runs without SwiftUI, a Dock icon or a
window and exits after checking or syncing. It follows the selected refresh
interval (Automatic is 30 minutes), retains failure throttling and rate-limit
cooldowns across runs, and catches up after login or sleep. Your Mac must be
awake and online; macOS schedules both the job and the widget's redraw.

The agent uses the host's existing sandbox, Keychain access group, GitHub client
and snapshot store. Credentials never enter the agent plist or widget extension.
Background Keychain reads disallow authentication prompts. A lock in the shared
App Group serializes visible and scheduled host processes, including token
renewal and cache writes. A scheduled process skips work while the app is open;
opening the app during a scheduled sync waits for it to finish.

Widgets are built from complete all-branch history using shared calendar/rolling
buckets. Incomplete history falls back to an all-branch fetch. A successful cache
uses the actual data cutoff as its timestamp.

Development checks:

```sh
./script/test.sh
./script/build_and_run.sh build
./script/build_and_run.sh run
```

For native diagnosis, the installed signed executable accepts
`--enable-background-refresh` to register the agent and request an initial
refresh, and `--background-refresh` to run its normal scheduled entry point.
The launch-agent label is `com.yjay18.widtget.refresh`. Do not register an unsigned
validation bundle or a temporary build instead of the installed app.

Reference: [Apple SMAppService documentation](https://developer.apple.com/documentation/servicemanagement/smappservice).
