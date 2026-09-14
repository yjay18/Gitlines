#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
mkdir -p "$repo_root/.build/tests"
xcrun swiftc -parse-as-library \
  "$repo_root/widtgetApp/GitHubSignInService.swift" \
  "$repo_root/tests/GitHubSignInTests.swift" \
  -o "$repo_root/.build/tests/github-signin-tests"
"$repo_root/.build/tests/github-signin-tests"
