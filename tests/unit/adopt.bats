#!/usr/bin/env bats
# Tests for --path: worktrees created by another tool (IDE, agent) and
# adopted by `ddev worktree --path`, then cleaned up by `worktree-remove`.

load test_helper

setup() {
    common_setup
    make_source site
    git worktree add -q -b feat/ide "${PARENT}/ide/paseo-abc"
    IDE="${PARENT}/ide/paseo-abc"
}

cfg() { echo "${1}/.ddev/config.worktree.local.yaml"; }

# ── Adopting ─────────────────────────────────────────────────────────────────

@test "sets up DDEV in an existing worktree without creating one" {
    run worktree --path="$IDE"
    [ "$status" -eq 0 ]

    grep -q '^# managed-by: external' "$(cfg "$IDE")"
    grep -qx 'name: site-paseo-abc' "$(cfg "$IDE")"
    [ "$(git worktree list | wc -l | tr -d ' ')" -eq 2 ]
    [ "$(git -C "$IDE" symbolic-ref --short HEAD)" = "feat/ide" ]
    ddev_called '^export-db .* @site$'
    ddev_called '^start @paseo-abc$'
    ddev_called '^import-db .* @paseo-abc$'
}

@test "the default name drops the source folder's prefix" {
    git worktree add -q -b feature-x "${PARENT}/site-feature-x"
    run worktree --path="${PARENT}/site-feature-x" --no-db --no-start
    [ "$status" -eq 0 ]
    grep -qx 'name: site-feature-x' "$(cfg "${PARENT}/site-feature-x")"
}

@test "an explicit name wins over the folder name" {
    run worktree custom --path="$IDE" --no-db --no-start
    [ "$status" -eq 0 ]
    grep -qx 'name: site-custom' "$(cfg "$IDE")"
}

@test "accepts --path DIR as two arguments" {
    run worktree --path "$IDE" --no-db --no-start
    [ "$status" -eq 0 ]
    [ -f "$(cfg "$IDE")" ]
}

# ── Refusals ─────────────────────────────────────────────────────────────────

@test "--force cannot be combined with --path" {
    run worktree --path="$IDE" --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"--force cannot be combined with --path"* ]]
}

@test "an empty --path is an error, not a fallback to a normal clone" {
    run worktree feat --path=""
    [ "$status" -ne 0 ]
    [[ "$output" == *"--path needs a directory"* ]]
    [ ! -e "${PARENT}/site-feat" ]
}

@test "--path without a value is an error" {
    run worktree feat --path
    [ "$status" -ne 0 ]
    [[ "$output" == *"--path needs a directory"* ]]
}

@test "refuses a directory that is not a worktree of this repo" {
    mkdir "${PARENT}/random"
    run worktree --path="${PARENT}/random"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a git worktree of"* ]]
}

@test "refuses the source checkout itself" {
    run worktree --path=.
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a git worktree of"* ]]
}

@test "refuses a worktree that is already adopted" {
    worktree --path="$IDE" --no-db --no-start
    run worktree --path="$IDE" --no-db --no-start
    [ "$status" -ne 0 ]
    [[ "$output" == *"already set up by ddev-worktree"* ]]
    [[ "$output" == *"ddev worktree-remove --path=\"${IDE}\""* ]]
}

@test "refuses a clone made by ddev worktree itself, including pre-v1.1.0 ones" {
    worktree normal --no-db --no-start
    run worktree --path="${PARENT}/site-normal"
    [ "$status" -ne 0 ]
    [[ "$output" == *"created by 'ddev worktree' itself"* ]]

    git worktree add -q -b old "${PARENT}/site-old"
    printf 'name: site-old\n' > "${PARENT}/site-old/.ddev/config.worktree.yaml"
    run worktree --path="${PARENT}/site-old"
    [ "$status" -ne 0 ]
    [[ "$output" == *"created by 'ddev worktree' itself"* ]]
}

@test "a project name collision suggests a way out other than --force" {
    DDEV_REGISTERED="site-paseo-abc" run worktree --path="$IDE" --no-db
    [ "$status" -ne 0 ]
    [[ "$output" == *"ddev delete --omit-snapshot site-paseo-abc"* ]]
}

@test "a normal --force never replaces an adopted worktree" {
    git worktree add -q -b feature-x "${PARENT}/site-feature-x"
    worktree --path="${PARENT}/site-feature-x" --no-db --no-start
    echo wip > "${PARENT}/site-feature-x/wip.txt"

    run worktree feature-x --force --no-db --no-start
    [ "$status" -ne 0 ]
    [[ "$output" == *"managed by another tool"* ]]
    [ -f "${PARENT}/site-feature-x/wip.txt" ]
}

# ── Removing ─────────────────────────────────────────────────────────────────

@test "removal by name deletes only the DDEV project and our config" {
    worktree --path="$IDE" --no-db --no-start
    echo wip > "${IDE}/wip.txt"

    run worktree_remove paseo-abc
    [ "$status" -eq 0 ]
    ddev_called '^delete --omit-snapshot -y @paseo-abc$'
    [ ! -e "$(cfg "$IDE")" ]
    [ -f "${IDE}/wip.txt" ]
    [ -f "${IDE}/.ddev/config.yaml" ]
    git worktree list | grep -q "$IDE"
}

@test "removal with --path does the same" {
    worktree --path="$IDE" --no-db --no-start
    run worktree_remove --path="$IDE"
    [ "$status" -eq 0 ]
    [ ! -e "$(cfg "$IDE")" ]
    [ -d "$IDE" ]
}

@test "removes a .ddev/ that was copied in because the source ignores it" {
    echo '.ddev' > .gitignore
    git rm -rq --cached .ddev
    git add .gitignore && git commit -qm "ignore .ddev"
    git worktree add -q -b ign "${PARENT}/ide/ign"

    worktree --path="${PARENT}/ide/ign" --no-db --no-start
    grep -q '^# ddev-dir: copied' "$(cfg "${PARENT}/ide/ign")"

    run worktree_remove --path="${PARENT}/ide/ign"
    [ "$status" -eq 0 ]
    [ ! -e "${PARENT}/ide/ign/.ddev" ]
    [ -f "${PARENT}/ide/ign/.gitignore" ]
}

@test "keeps the config when ddev delete fails and the project is still registered" {
    worktree --path="$IDE" --no-db --no-start
    DDEV_DELETE_RC=1 DDEV_REGISTERED="site-paseo-abc" run worktree_remove paseo-abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"Nothing was removed"* ]]
    [ -f "$(cfg "$IDE")" ]
}

@test "keeps the config when ddev delete fails and registration can't be checked" {
    worktree --path="$IDE" --no-db --no-start
    DDEV_DELETE_RC=1 DDEV_LIST_RC=1 run worktree_remove paseo-abc
    [ "$status" -ne 0 ]
    [ -f "$(cfg "$IDE")" ]
}

@test "finishes cleanup when ddev delete fails because the project is already gone" {
    worktree --path="$IDE" --no-db --no-start
    DDEV_DELETE_RC=1 run worktree_remove paseo-abc
    [ "$status" -eq 0 ]
    [[ "$output" == *"was already removed"* ]]
    [ ! -e "$(cfg "$IDE")" ]
}

@test "remove --path refuses a normal clone" {
    worktree normal --no-db --no-start
    run worktree_remove --path="${PARENT}/site-normal"
    [ "$status" -ne 0 ]
    [[ "$output" == *"was not adopted with 'ddev worktree --path'"* ]]
    [ -d "${PARENT}/site-normal" ]
}

@test "remove refuses a name and --path together" {
    run worktree_remove x --path="$IDE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"either a name or --path"* ]]
}

@test "remove --path refuses a worktree of another project" {
    worktree --path="$IDE" --no-db --no-start
    make_source other
    run worktree_remove --path="$IDE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a worktree of other"* ]]
    [ -f "$(cfg "$IDE")" ]
}

@test "an unrelated folder at the default location does not hide an adopted worktree" {
    worktree --path="$IDE" --no-db --no-start
    mkdir "${PARENT}/site-paseo-abc"

    run worktree_remove paseo-abc
    [ "$status" -eq 0 ]
    [ ! -e "$(cfg "$IDE")" ]
    [ -d "${PARENT}/site-paseo-abc" ]
}

@test "--list shows adopted worktrees marked external" {
    worktree --path="$IDE" --no-db --no-start
    run worktree_remove --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"paseo-abc"*"${IDE} (external)"* ]]
}
