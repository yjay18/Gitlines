#!/bin/zsh
set -euo pipefail
repo_root="${0:A:h:h}"
for check in test_dashboard_history test_dashboard_service test_github_signin test_account_model; do
  print "Running $check"
  zsh "$repo_root/script/$check.sh"
done
