#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
project_path="$repo_root/widtget.xcodeproj"
scheme="widtget app"
configuration="${WIDTGET_CONFIGURATION:-Debug}"
action="${1:-build}"
derived_data_root="$repo_root/.build/DerivedData"
unsigned_derived_data="${WIDTGET_UNSIGNED_DERIVED_DATA:-$derived_data_root/Unsigned}"
signed_derived_data="${WIDTGET_SIGNED_DERIVED_DATA:-$derived_data_root/Signed}"
legacy_derived_data="$derived_data_root"
lsregister_path="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

common_build_args=(
  -project "$project_path"
  -scheme "$scheme"
  -configuration "$configuration"
  -destination "platform=macOS"
)

if [[ -n "${WIDTGET_DERIVED_DATA:-}" ]]; then
  unsigned_derived_data="$WIDTGET_DERIVED_DATA/Unsigned"
  signed_derived_data="$WIDTGET_DERIVED_DATA/Signed"
fi

unregister_app() {
  local app_path="$1"
  if [[ -d "$app_path" ]]; then
    "$lsregister_path" -u "$app_path" >/dev/null 2>&1 || true
  fi
}

register_signed_app_if_available() {
  local app_path="$signed_derived_data/Build/Products/$configuration/gitlines.app"
  if [[ -d "$app_path" ]] && codesign --verify "$app_path" >/dev/null 2>&1; then
    "$lsregister_path" -f -R -trusted "$app_path"
  fi
}

case "$action" in
  build)
    # Keep unsigned validation artifacts isolated from the signed app. Xcode registers macOS
    # products during a normal build, so immediately unregister the validation copy and restore
    # the signed registration if one already exists.
    xcodebuild "${common_build_args[@]}" \
      -derivedDataPath "$unsigned_derived_data" \
      CODE_SIGNING_ALLOWED=NO \
      build
    unregister_app "$unsigned_derived_data/Build/Products/$configuration/gitlines.app"
    register_signed_app_if_available
    ;;
  run)
    # A signed run registers the embedded WidgetKit extension with macOS.
    # -allowProvisioningUpdates renews the 7-day development profile, which otherwise expires
    # and makes macOS refuse to launch the app ("The application \"gitlines\" can't be opened.").
    xcodebuild "${common_build_args[@]}" \
      -derivedDataPath "$signed_derived_data" \
      -allowProvisioningUpdates \
      build

    app_path="$signed_derived_data/Build/Products/$configuration/gitlines.app"
    if [[ ! -d "$app_path" ]]; then
      print -u2 "Built app was not found at: $app_path"
      exit 1
    fi

    # Remove stale unsigned/legacy registrations that can otherwise win bundle-ID or URL-scheme
    # resolution and launch without the Keychain entitlement.
    unregister_app "$unsigned_derived_data/Build/Products/$configuration/gitlines.app"
    unregister_app "$legacy_derived_data/Build/Products/$configuration/gitlines.app"
    "$lsregister_path" -f -R -trusted "$app_path"

    # `open` only activates an existing process for the same app. Restart both the host and its
    # embedded extension so WidgetKit cannot keep rendering through an older loaded executable.
    pkill -f "$app_path" >/dev/null 2>&1 || true
    open -n "$app_path"
    ;;
  clean)
    xcodebuild "${common_build_args[@]}" -derivedDataPath "$unsigned_derived_data" clean
    xcodebuild "${common_build_args[@]}" -derivedDataPath "$signed_derived_data" clean
    ;;
  *)
    print -u2 "Usage: $0 [build|run|clean]"
    exit 64
    ;;
esac
