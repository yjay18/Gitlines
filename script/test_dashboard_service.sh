#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
mkdir -p "$repo_root/.build/tests"
xcrun swiftc -parse-as-library \
 "$repo_root/Shared/WidgetPreferences.swift" "$repo_root/Shared/ActivitySnapshotStore.swift" \
 "$repo_root/widtget/Models/ActivityModels.swift" "$repo_root/widtgetApp/GitHubSignInService.swift" \
 "$repo_root/widtgetApp/DashboardHistory.swift" "$repo_root/widtgetApp/GitHubActivityService.swift" \
 "$repo_root/tests/DashboardServiceTests.swift" -o "$repo_root/.build/tests/dashboard-service-tests"
"$repo_root/.build/tests/dashboard-service-tests"
