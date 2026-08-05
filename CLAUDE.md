# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Bash tooling that automates GitHub repository setup via the `gh` CLI. The single entry point is `setup-repo.sh`, which applies team-oriented merge settings and branch protection (Rulesets) to a repo, switching behavior based on a branch strategy (`github-flow` or `git-flow`). The script must remain idempotent — safe to re-run any number of times (e.g., existing Rulesets are updated via PUT instead of re-created via POST).

All documentation, code comments, and user-facing script output are written in Japanese. Follow that convention.

## Commands

Dependencies: `bats`, `jq`, `shellcheck` (Ubuntu: `sudo apt-get install -y bats jq shellcheck`; macOS: `brew install bats-core jq shellcheck`).

```bash
bash -n setup-repo.sh                   # Syntax check
shellcheck setup-repo.sh test/stubs/gh  # Lint
bats test/                              # Run all tests
bats test/setup-repo.bats --filter "冪等"  # Run tests matching a name (regex)
```

CI (`.github/workflows/ci.yml`) runs exactly these three checks (syntax, shellcheck, bats) on push to main and on PRs.

## Test architecture

Tests in `test/setup-repo.bats` never touch the real GitHub API. `setup()` prepends `test/stubs/gh` to `PATH`, so every `gh` invocation hits the stub instead. The stub:

- Appends each invocation's arguments to `$GH_STUB_LOG` — tests assert on this log to verify which `gh` commands ran and with what flags.
- Saves any `--input -` request body to `$GH_STUB_PAYLOAD` — tests assert on this with `jq` to verify the Ruleset JSON actually sent.
- Switches success/failure and return values via `GH_STUB_*` environment variables (e.g., `GH_STUB_AUTH_FAIL`, `GH_STUB_EXISTING_RULESET_ID`, `GH_STUB_DEVELOP_EXISTS`) — documented in the stub's header comment.

When adding a new `gh` call to `setup-repo.sh`, you must also teach the stub to handle it (unhandled calls exit 1 with "未対応の呼び出しです") and add a `GH_STUB_*` variable if tests need to control its outcome.

## Structure of setup-repo.sh

The script is organized into clearly commented sections, in execution order: configuration (edit `RULESET_NAME` / `ruleset_json()` here to change what gets applied), argument parsing, prerequisite checks (`gh` installed and authenticated), target repo resolution (falls back to `gh repo view` for the current directory), merge settings, develop-branch creation (git-flow only), and Ruleset create-or-update. Validation errors must exit before any API call is made — tests enforce this.

The Ruleset targets `~DEFAULT_BRANCH` (not a literal branch name) so protection follows a renamed default branch.
