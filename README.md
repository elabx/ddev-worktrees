# ddev-worktree

A global DDEV add-on that clones an existing DDEV project (files + database) into a new directory. If the project is a git repo, it uses `git worktree` to create a linked worktree; otherwise it copies files with rsync.

The new directory gets its own DDEV project name via `config.worktree.yaml`, so both instances can run simultaneously without collision.

## Installation

```bash
ddev add-on install --global esanmiguel/ddev-worktree
```

Or install from a local clone:

```bash
ddev add-on install --global /path/to/ddev-worktree
```

Once installed, the `ddev worktree` and `ddev worktree-remove` commands are available in every DDEV project.

## Quick Start

```bash
cd ~/projects/my-site

# Create a worktree for a new branch
ddev worktree feature-login

# Both projects now run side-by-side
ddev list
# my-site          running
# my-site-feature-login  running

# Done with the worktree? Clean up
ddev worktree-remove feature-login
```

## Usage

### `ddev worktree`

```
ddev worktree <branch-or-name> [--profile=NAME] [--no-db] [--no-start] [--force]
```

Creates a clone of the current DDEV project in a sibling directory.

**What it does:**

1. Exports the database from the source project
2. Creates the target directory via `git worktree add` (or `rsync` if not a git repo)
3. Copies `.ddev/` if it's gitignored
4. Copies any files specified in the profile's `copy` list
5. Creates `.ddev/config.worktree.yaml` with a unique project name
6. Starts DDEV and imports the database
7. Runs any `post_create` commands from the profile

**Flags:**

| Flag | Description |
|------|-------------|
| `--profile=NAME` | Which profile from `.ddev/worktree.yaml` to use |
| `--no-db` | Skip database export/import |
| `--no-start` | Create files only — don't start DDEV or run post_create |
| `--force`, `-f` | Overwrite an existing target directory/project |

**Target directory:** `../<source-dirname>-<sanitized-name>`
**Target project name:** `<source-project>-<sanitized-name>`

Branch names are sanitized for use as directory names (e.g., `feature/foo` becomes `feature-foo`).

### `ddev worktree-remove`

```
ddev worktree-remove <name> [--list]
```

**List clones:**

```bash
ddev worktree-remove --list
```

**Remove a clone:**

```bash
ddev worktree-remove feature-login
```

This stops the DDEV project, removes the git worktree (or deletes the directory), and cleans up. It refuses to remove directories that don't have a `config.worktree.yaml` as a safety measure.

## Configuration: `.ddev/worktree.yaml`

Create this file in your project's `.ddev/` directory to configure what gets copied and what commands run after clone creation. Commit it to git so your team shares the same setup.

```yaml
# .ddev/worktree.yaml
default_profile: full

profiles:
  full:
    copy:
      - site/assets
      - .env
    post_create:
      - composer install
      - npm install

  minimal:
    copy:
      - .env
    post_create:
      - composer install

  frontend:
    copy:
      - .env
    post_create:
      - npm install
```

**Fields:**

| Field | Description |
|-------|-------------|
| `default_profile` | Which profile to use when `--profile` is not specified |
| `profiles.<name>.copy` | Files/directories to copy from source to target (relative to project root). Use this for things not in git: uploads, `.env`, etc. |
| `profiles.<name>.post_create` | Shell commands to run in the target directory after DDEV is started |

If no `.ddev/worktree.yaml` exists, the command works fine — it just skips the copy and post_create steps.

### Profile Examples

**ProcessWire:**

```yaml
default_profile: full

profiles:
  full:
    copy:
      - site/assets
      - .env
    post_create:
      - composer install
```

**Drupal:**

```yaml
default_profile: full

profiles:
  full:
    copy:
      - sites/default/files
      - .env
    post_create:
      - composer install
      - ddev drush cr
```

**Laravel:**

```yaml
default_profile: full

profiles:
  full:
    copy:
      - storage/app
      - .env
    post_create:
      - composer install
      - npm install
      - ddev artisan key:generate
```

**WordPress:**

```yaml
default_profile: full

profiles:
  full:
    copy:
      - wp-content/uploads
      - .env
    post_create:
      - composer install
```

## How It Works

### Project Isolation

The clone gets a `config.worktree.yaml` with `override_config: true` and a unique `name` field. This overrides the project name from `config.yaml` without modifying any git-tracked files. Both projects can run simultaneously with their own containers, databases, and URLs.

### Git Worktree Behavior

When the source project is a git repo:

- **Existing local branch** — `git worktree add <path> <branch>`
- **Remote branch only** — creates a local tracking branch
- **No such branch** — creates a new branch from HEAD

### Non-Git Projects

If there's no git repo, the command uses `rsync` to copy all files, excluding DDEV runtime artifacts.

### .ddev/.gitignore

The command automatically adds `config.worktree.yaml` to `.ddev/.gitignore` to keep git clean.

## Dependencies

- **DDEV >= v1.24.0**
- **yq** (recommended) — for full YAML parsing of `.ddev/worktree.yaml`. Install via `brew install yq` or see [yq docs](https://github.com/mikefarah/yq). Without yq, the command falls back to basic grep/awk parsing with a warning.
- **rsync** — for file copying (pre-installed on macOS and most Linux distributions)

## Uninstall

```bash
ddev add-on remove --global ddev-worktree
```
