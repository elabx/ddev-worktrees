#!/usr/bin/env bats
# Packaging checks for install.yaml and the command files.

load test_helper

@test "every global file exists and is executable" {
    while read -r f; do
        [ -f "${REPO_ROOT}/${f}" ]
        [ -x "${REPO_ROOT}/${f}" ]
    done < <(sed -n 's/^  - \(commands\/.*\)$/\1/p' "${REPO_ROOT}/install.yaml")
}

@test "commands carry #ddev-generated so add-on upgrades can replace them" {
    for f in "$WORKTREE_CMD" "$REMOVE_CMD"; do
        [ "$(sed -n 2p "$f")" = "#ddev-generated" ]
    done
}

@test "the Flags header is valid JSON" {
    for f in "$WORKTREE_CMD" "$REMOVE_CMD"; do
        sed -n 's/^## Flags: //p' "$f" | python3 -c 'import json,sys; json.load(sys.stdin)'
    done
}
