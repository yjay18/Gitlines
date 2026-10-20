#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
mkdir -p "$repo_root/.build/tests"
sources=("${(@f)$(rg --files "$repo_root/Shared" -g '*.swift')}")
xcrun swiftc -parse-as-library -module-cache-path "$repo_root/.build/tests/ModuleCache" \
  "${sources[@]}" "$repo_root/widtget/Models/ActivityModels.swift" \
  "$repo_root/widtgetApp/GitHubSignInService.swift" \
  "$repo_root/widtgetApp/DashboardHistory.swift" \
  "$repo_root/widtgetApp/GitHubActivityService.swift" \
  "$repo_root/widtgetApp/GitHubAccountModel.swift" \
  "$repo_root/widtgetApp/GitHubBackgroundRefresh.swift" \
  "$repo_root/tests/GitHubAccountModelTests.swift" \
  -o "$repo_root/.build/tests/account-model-tests"
"$repo_root/.build/tests/account-model-tests" --sample-data
