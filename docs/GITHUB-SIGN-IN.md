# GitHub sign-in

Gitlines uses the GitHub App device flow directly from the host app. The registration
is Gitlines Desktop (`gitlines-desktop`), owned by `yjay18`, with device flow and
expiring user tokens enabled. It requests only read-only repository Contents and
Metadata; webhooks, callback wildcards, and installation-time web OAuth are disabled.
It is currently installable only on the owner's account.

The client ID and installation slug in `GitHubSignInConfiguration` are public.
Never add a client secret or private key to the native app. Device-flow access tokens
can be refreshed without a client secret. Keep any registration administration keys
outside the source tree and app bundle.

## User flow

1. Open Connections and choose repositories on GitHub. Install the GitHub App on
   the selected account; the user controls repository access and grants consent.
2. Click Sign in with GitHub, then Copy code and open GitHub. Enter the displayed
   code on `https://github.com/login/device` and approve the matching app.
3. Gitlines verifies the account identity and saves the approved sign-in before
   discovering repositories or refreshing activity. A repository error cannot discard
   that sign-in. Cancellation or denial before saving preserves the prior connection.
   Existing organization tokens are retained separately. The Connections card shows
   the active authentication method, sign-in progress, and any failure directly.
4. Access and refresh tokens remain in the app's existing data-protection Keychain
   record. Before fetching activity, tokens near expiry are renewed and the rotated
   credentials saved immediately. Widgets receive only display-ready snapshots.

Use Choose repositories on GitHub to adjust installations; refresh all activity
after changing access. If consent or the refresh token expires, sign in again.
Disconnect removes local credentials and cached activity. Revoke Gitlines on GitHub
as well if the authorization should be removed from the GitHub account.

## Validation

Run `./script/test_github_signin.sh` for mocked protocol tests, then
`./script/build_and_run.sh build` for the host and widget compilation check.
A signed run is required for real Keychain and WidgetKit validation.

References: [GitHub App device authorization](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)
and [refreshing user access tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens).
