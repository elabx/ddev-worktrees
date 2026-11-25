#!/usr/bin/env bats

# End-to-end test against a real DDEV, following ddev/ddev-addon-template.
# The fast tests that use a fake ddev are in tests/unit/ (bats tests/unit).
#
# This installs the add-on's global commands into ~/.ddev/commands/host, so
# it only runs in GitHub Actions unless you opt in:
#   DDEV_WORKTREE_E2E=1 bats ./tests/test.bats
# Needs bats-core, bats-assert, bats-file and bats-support.
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

e2e_enabled() { [[ -n "${GITHUB_ACTIONS:-}" || -n "${DDEV_WORKTREE_E2E:-}" ]]; }

setup() {
  set -eu -o pipefail
  e2e_enabled || skip "installs into ~/.ddev; set DDEV_WORKTREE_E2E=1 to run locally"

  export GITHUB_REPO=elabx/ddev-worktrees

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  export BRANCH="feat-e2e"
  export CLONE_PROJECT="${PROJNAME}-${BRANCH}"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export CLONE_DIR="${TESTDIR}-${BRANCH}"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  export CI=true
  ddev delete -Oy "${CLONE_PROJECT}" >/dev/null 2>&1 || true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true

  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-type=php --project-tld=ddev.site
  assert_success
  echo '<?php echo "hello from the source project";' > index.php
  git init -q -b main
  git -c user.name=test -c user.email=test@example.com add -A
  git -c user.name=test -c user.email=test@example.com commit -qm init
  run ddev start -y
  assert_success

  # A row the clone must inherit through the database copy.
  run ddev mysql -e "CREATE TABLE marker (v VARCHAR(32)); INSERT INTO marker VALUES ('from-source');"
  assert_success
}

health_checks() {
  cd "${TESTDIR}"

  # Create a clone: git worktree, own project name, database copied.
  run ddev worktree "${BRANCH}"
  assert_success
  assert_dir_exists "${CLONE_DIR}"
  assert_file_exists "${CLONE_DIR}/.ddev/config.worktree.local.yaml"

  run ddev describe -j "${CLONE_PROJECT}"
  assert_success
  assert_output --partial '"status":"running"'

  cd "${CLONE_DIR}"
  run ddev mysql -N -B -e "SELECT v FROM marker"
  assert_success
  assert_output "from-source"

  run curl -sf "https://${CLONE_PROJECT}.ddev.site"
  assert_success
  assert_output --partial "hello from the source project"

  # The source project keeps running alongside it.
  run ddev describe -j "${PROJNAME}"
  assert_output --partial '"status":"running"'

  # --list, then remove the clone completely.
  cd "${TESTDIR}"
  run ddev worktree-remove --list
  assert_success
  assert_output --partial "${BRANCH}"

  run ddev worktree-remove "${BRANCH}"
  assert_success
  assert_dir_not_exists "${CLONE_DIR}"
  run ddev describe "${CLONE_PROJECT}"
  assert_failure
}

teardown() {
  set -eu -o pipefail
  e2e_enabled || return 0
  ddev delete -Oy "${CLONE_PROJECT}" >/dev/null 2>&1 || true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  [ -n "${CLONE_DIR:-}" ] && rm -rf "${CLONE_DIR}"
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR:-}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  health_checks
}
