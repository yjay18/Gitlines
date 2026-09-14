#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
mkdir -p "$repo_root/.build/tests"
xcrun swiftc -parse-as-library "$repo_root/widtgetApp/DashboardHistory.swift" \
  "$repo_root/tests/DashboardHistoryTests.swift" -o "$repo_root/.build/tests/dashboard-history-tests"
"$repo_root/.build/tests/dashboard-history-tests"
