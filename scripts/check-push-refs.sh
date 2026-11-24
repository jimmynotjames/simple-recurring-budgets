#!/usr/bin/env bash
# pre-push guard (lefthook.yml): refuse any push whose target on the remote is `main`,
# whichever branch the checkout is on. Changes reach main only through a PR.
#
# git feeds the hook one line per ref being pushed on stdin:
#   <local ref> <local sha> <remote ref> <remote sha>
# Pushing a feature branch, or deleting one, is allowed even while the checkout is on main.
set -euo pipefail

status=0
while read -r local_ref _local_sha remote_ref _remote_sha; do
    if [ "$remote_ref" = "refs/heads/main" ]; then
        echo "error: push to main is not allowed (${local_ref:-?} -> main) - open a PR instead" >&2
        status=1
    fi
done
exit "$status"
