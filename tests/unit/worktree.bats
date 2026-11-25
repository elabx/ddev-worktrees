#!/usr/bin/env bats
# Tests for `ddev worktree`, run against a fake ddev (see test_helper.bash).

load test_helper

setup() {
    common_setup
    make_source site
}

# ── Creating a clone ─────────────────────────────────────────────────────────

@test "creates a sibling worktree with its own project name" {
    run worktree feat-x
    [ "$status" -eq 0 ]

    [ -d "${PARENT}/site-feat-x" ]
    [ "$(git -C "${PARENT}/site-feat-x" symbolic-ref --short HEAD)" = "feat-x" ]
    grep -qx 'override_config: true' "${PARENT}/site-feat-x/.ddev/config.worktree.local.yaml"
    grep -qx 'name: site-feat-x' "${PARENT}/site-feat-x/.ddev/config.worktree.local.yaml"
}

@test "exports the database from the source and imports it into the clone" {
    run worktree feat-x
    [ "$status" -eq 0 ]

    ddev_called '^export-db --gzip --file=.* @site$'
    ddev_called '^start @site-feat-x$'
    ddev_called '^import-db --file=.* @site-feat-x$'
}

@test "removes the database dump afterwards" {
    run worktree feat-x
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "--no-db skips export and import" {
    run worktree feat-x --no-db
    [ "$status" -eq 0 ]
    ! ddev_called '^export-db'
    ! ddev_called '^import-db'
    ddev_called '^start @site-feat-x$'
}

@test "--no-start creates files but does not start DDEV" {
    run worktree feat-x --no-db --no-start
    [ "$status" -eq 0 ]
    [ -d "${PARENT}/site-feat-x" ]
    ! ddev_called '^start'
}

@test "checks out an existing local branch" {
    git branch existing
    run worktree existing --no-db --no-start
    [ "$status" -eq 0 ]
    [ "$(git -C "${PARENT}/site-existing" rev-parse HEAD)" = "$(git rev-parse existing)" ]
}

@test "creates a tracking branch for a remote-only branch" {
    git clone -q --bare "$SOURCE" "${SANDBOX}/origin.git"
    git -C "${SANDBOX}/work" clone -q "${SANDBOX}/origin.git" clone-src
    git -C "${SANDBOX}/origin.git" branch remote-only main
    cd "${SANDBOX}/work/clone-src"
    mkdir -p .ddev && echo 'name: site' > .ddev/config.yaml
    git fetch -q origin

    run worktree remote-only --no-db --no-start
    [ "$status" -eq 0 ]
    [ "$(git -C "${SANDBOX}/work/clone-src-remote-only" rev-parse --abbrev-ref '@{upstream}')" = "origin/remote-only" ]
}

@test "copies a gitignored .ddev/ into the clone" {
    echo '.ddev' > .gitignore
    git rm -rq --cached .ddev
    git add .gitignore && git commit -qm "ignore .ddev"

    run worktree feat-x --no-db --no-start
    [ "$status" -eq 0 ]
    grep -qx 'name: site' "${PARENT}/site-feat-x/.ddev/config.yaml"
}

@test "fails outside a DDEV project" {
    cd "${SANDBOX}/work"
    mkdir plain && cd plain
    run worktree feat-x
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not appear to be a DDEV project"* ]]
}

@test "requires a branch name" {
    run worktree
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "rejects unknown flags" {
    run worktree feat-x --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown flag: --bogus"* ]]
}

# ── Name sanitizing ──────────────────────────────────────────────────────────

@test "lowercases and replaces characters that are invalid in hostnames" {
    run worktree 'feature/Foo_bar' --no-db --no-start
    [ "$status" -eq 0 ]
    [ -d "${PARENT}/site-feature-foo-bar" ]
    grep -qx 'name: site-feature-foo-bar' "${PARENT}/site-feature-foo-bar/.ddev/config.worktree.local.yaml"
    # The git branch keeps its original name.
    [ "$(git -C "${PARENT}/site-feature-foo-bar" symbolic-ref --short HEAD)" = "feature/Foo_bar" ]
}

@test "turns dots into dashes" {
    run worktree 'release/1.2' --no-db --no-start
    [ "$status" -eq 0 ]
    [ -d "${PARENT}/site-release-1-2" ]
}

@test "rejects a name that sanitizes to nothing" {
    run worktree '///' --no-db --no-start
    [ "$status" -ne 0 ]
    [[ "$output" == *"sanitizes to empty string"* ]]
}

# ── Collisions and --force ───────────────────────────────────────────────────

@test "refuses an existing target directory without --force" {
    mkdir "${PARENT}/site-feat-x"
    run worktree feat-x --no-db --no-start
    [ "$status" -ne 0 ]
    [[ "$output" == *"Target directory already exists"* ]]
}

@test "--force replaces an existing target directory" {
    mkdir "${PARENT}/site-feat-x"
    touch "${PARENT}/site-feat-x/stale"
    run worktree feat-x --force --no-db --no-start
    [ "$status" -eq 0 ]
    [ ! -e "${PARENT}/site-feat-x/stale" ]
    [ -f "${PARENT}/site-feat-x/index.php" ]
}

@test "--force can recreate the same branch's worktree" {
    worktree feat-x --no-db --no-start
    run worktree feat-x --force --no-db --no-start
    [ "$status" -eq 0 ]
    [ "$(git -C "${PARENT}/site-feat-x" symbolic-ref --short HEAD)" = "feat-x" ]
}

@test "--force never replaces another branch's worktree with the same sanitized name" {
    worktree feat-login --no-db --no-start
    echo "work in progress" > "${PARENT}/site-feat-login/wip.txt"

    run worktree feat_login --force --no-db --no-start
    [ "$status" -ne 0 ]
    [[ "$output" == *"is a worktree for branch 'feat-login', not 'feat_login'"* ]]
    [ -f "${PARENT}/site-feat-login/wip.txt" ]
}

@test "stops before the database export when the branch is checked out elsewhere" {
    git worktree add -q -b feat-x "${PARENT}/somewhere-else"
    run worktree feat-x
    [ "$status" -ne 0 ]
    [[ "$output" == *"already checked out at ${PARENT}/somewhere-else"* ]]
    ! ddev_called '^export-db'
}

@test "refuses a registered project with the same name" {
    DDEV_REGISTERED="site-feat-x" run worktree feat-x --no-db --no-start
    [ "$status" -ne 0 ]
    [[ "$output" == *"A DDEV project named 'site-feat-x' already exists"* ]]
}

@test "a project whose name only starts the same is not a collision" {
    DDEV_REGISTERED="site-feat-x-old" run worktree feat-x --no-db --no-start
    [ "$status" -eq 0 ]
}

# ── Profiles (.ddev/worktree-hooks.yaml) ─────────────────────────────────────

write_hooks() {
    cat > .ddev/worktree-hooks.yaml <<'EOF'
default_profile: full

profiles:
  full:
    copy:
      - .env
      - uploads
    post_create:
      - touch post-create-ran
  minimal:
    copy:
      - .env
EOF
    echo "SECRET=1" > .env
    mkdir -p uploads && echo img > uploads/a.jpg
}

@test "copies profile files and runs post_create in the clone" {
    write_hooks
    run worktree feat-x --no-db
    [ "$status" -eq 0 ]
    [ -f "${PARENT}/site-feat-x/.env" ]
    [ -f "${PARENT}/site-feat-x/uploads/a.jpg" ]
    [ -f "${PARENT}/site-feat-x/post-create-ran" ]
}

@test "--profile selects another profile" {
    write_hooks
    run worktree feat-x --no-db --profile=minimal
    [ "$status" -eq 0 ]
    [ -f "${PARENT}/site-feat-x/.env" ]
    [ ! -e "${PARENT}/site-feat-x/uploads" ]
    [ ! -e "${PARENT}/site-feat-x/post-create-ran" ]
}

@test "an unknown profile fails and lists the available ones" {
    write_hooks
    run worktree feat-x --no-db --profile=nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"  - full"* ]]
    [[ "$output" == *"  - minimal"* ]]
    [[ "$output" == *"Profile 'nope' not found"* ]]
}

# ── omit_project_name_by_default ─────────────────────────────────────────────

@test "with omit_project_name_by_default and no name in config.yaml, no override is written" {
    skip "known bug: the source project name is read only from config.yaml, so the command stops before reaching the omit logic"
    mkdir -p "${HOME}/.ddev"
    echo 'omit_project_name_by_default: true' > "${HOME}/.ddev/global_config.yaml"
    echo 'type: php' > .ddev/config.yaml
    echo 'name: site' > .ddev/config.local.yaml   # the source still needs a name
    git add -A && git commit -qm "omit name"

    run worktree feat-x --no-db --no-start
    [ "$status" -eq 0 ]
    [ ! -e "${PARENT}/site-feat-x/.ddev/config.worktree.local.yaml" ]
}
