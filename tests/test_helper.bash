# Shared setup for the bats suite.
#
# Each test gets an isolated sandbox: its own HOME, TMPDIR and a fake `ddev`
# first on PATH. The fake logs every call to $DDEV_LOG ("<args> @<dir>") and
# can be steered with:
#   DDEV_REGISTERED  space-separated project names `ddev list -j` reports
#   DDEV_DELETE_RC   exit status of `ddev delete` (default 0)

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
WORKTREE_CMD="${REPO_ROOT}/commands/host/worktree"
REMOVE_CMD="${REPO_ROOT}/commands/host/worktree-remove"

common_setup() {
    # Physical path: macOS puts temp dirs under a /var -> /private/var symlink.
    SANDBOX="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    export HOME="${SANDBOX}/home"
    export TMPDIR="${SANDBOX}/tmp"
    export DDEV_LOG="${SANDBOX}/ddev.log"
    mkdir -p "$HOME" "$TMPDIR" "${SANDBOX}/bin" "${SANDBOX}/work"
    : > "$DDEV_LOG"

    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

    cat > "${SANDBOX}/bin/ddev" <<'EOF'
#!/bin/bash
echo "$* @$(basename "$PWD")" >> "$DDEV_LOG"
case "$1" in
    list)
        printf '{"raw":['
        sep=""
        for name in ${DDEV_REGISTERED:-}; do
            printf '%s{"name":"%s"}' "$sep" "$name"
            sep=","
        done
        printf ']}\n'
        ;;
    describe) echo '{"raw":{"status":"running"}}' ;;
    export-db)
        for arg in "$@"; do
            [[ "$arg" == --file=* ]] && echo "fake dump" > "${arg#--file=}"
        done
        ;;
    delete) exit "${DDEV_DELETE_RC:-0}" ;;
esac
exit 0
EOF
    chmod +x "${SANDBOX}/bin/ddev"
    export PATH="${SANDBOX}/bin:${PATH}"
}

# make_source <dir-name> [project-name]
# Creates a git repo with a DDEV config under $SANDBOX/work and cd's into it.
make_source() {
    local dir="${SANDBOX}/work/$1" project="${2:-$1}"
    mkdir -p "${dir}/.ddev"
    echo "name: ${project}" > "${dir}/.ddev/config.yaml"
    echo "hello" > "${dir}/index.php"
    git -C "$dir" init -q -b main
    git -C "$dir" add -A
    git -C "$dir" commit -q -m init
    cd "$dir" || return 1
    # Used by the .bats files.
    # shellcheck disable=SC2034
    SOURCE="$dir"
    # shellcheck disable=SC2034
    PARENT="${SANDBOX}/work"
}

worktree() { bash "$WORKTREE_CMD" "$@"; }
worktree_remove() { bash "$REMOVE_CMD" "$@"; }

# ddev_called <pattern>: succeeds if a logged ddev call matches the regex.
ddev_called() { grep -qE "$1" "$DDEV_LOG"; }
