#!/usr/bin/env bats
# Tests for `ddev worktree-remove`, run against a fake ddev (see test_helper.bash).

load test_helper

setup() {
    common_setup
    make_source site
}

@test "removes a clone: DDEV project, git worktree and directory" {
    worktree feat-x --no-db --no-start
    : > "$DDEV_LOG"

    run worktree_remove feat-x
    [ "$status" -eq 0 ]
    ddev_called '^delete --omit-snapshot -y @site-feat-x$'
    [ ! -e "${PARENT}/site-feat-x" ]
    ! git worktree list | grep -q site-feat-x
}

@test "accepts the original branch name, not just the sanitized one" {
    worktree 'feature/Foo_bar' --no-db --no-start
    run worktree_remove 'feature/Foo_bar'
    [ "$status" -eq 0 ]
    [ ! -e "${PARENT}/site-feature-foo-bar" ]
}

@test "removes a non-git (rsync) clone" {
    rm -rf .git
    worktree feat-x --no-db --no-start
    [ -d "${PARENT}/site-feat-x" ]
    run worktree_remove feat-x
    [ "$status" -eq 0 ]
    [ ! -e "${PARENT}/site-feat-x" ]
}

@test "still removes clones named by v1.1.2 and earlier (underscores kept)" {
    git worktree add -q -b feat_x "${PARENT}/site-feat_x"
    printf 'override_config: true\nname: site-feat_x\n' > "${PARENT}/site-feat_x/.ddev/config.worktree.local.yaml"

    run worktree_remove feat_x
    [ "$status" -eq 0 ]
    [ ! -e "${PARENT}/site-feat_x" ]
}

@test "still removes clones with the pre-v1.1.0 config.worktree.yaml" {
    git worktree add -q -b old "${PARENT}/site-old"
    printf 'override_config: true\nname: site-old\n' > "${PARENT}/site-old/.ddev/config.worktree.yaml"

    run worktree_remove old
    [ "$status" -eq 0 ]
    [ ! -e "${PARENT}/site-old" ]
}

@test "refuses a directory that was not created by ddev worktree" {
    mkdir "${PARENT}/site-junk"
    touch "${PARENT}/site-junk/keep-me"

    run worktree_remove junk
    [ "$status" -ne 0 ]
    [[ "$output" == *"Safety check failed"* ]]
    [ -f "${PARENT}/site-junk/keep-me" ]
}

@test "reports a missing clone with a hint" {
    run worktree_remove nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"Directory not found: ${PARENT}/site-nope"* ]]
    [[ "$output" == *"--list"* ]]
}

@test "requires a name" {
    run worktree_remove
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "--list shows this project's clones" {
    worktree feat-a --no-db --no-start
    worktree feat-b --no-db --no-start

    run worktree_remove --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat-a"*"${PARENT}/site-feat-a/"* ]]
    [[ "$output" == *"feat-b"*"${PARENT}/site-feat-b/"* ]]
}

@test "--list says when there are none" {
    run worktree_remove --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"(none found)"* ]]
}
