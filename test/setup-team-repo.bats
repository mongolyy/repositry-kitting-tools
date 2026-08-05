#!/usr/bin/env bats
#
# setup-team-repo.sh のユニットテスト。
# gh CLI はスタブ (test/stubs/gh) に差し替えるため、実際のGitHub APIは呼ばれない。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP_SCRIPT="$REPO_ROOT/setup-team-repo.sh"

  TEST_TMP="$(mktemp -d)"

  # gh スタブを PATH の先頭に置く
  mkdir -p "$TEST_TMP/bin"
  cp "$REPO_ROOT/test/stubs/gh" "$TEST_TMP/bin/gh"
  chmod +x "$TEST_TMP/bin/gh"
  PATH="$TEST_TMP/bin:$PATH"
  export PATH

  export GH_STUB_LOG="$TEST_TMP/gh-calls.log"
  export GH_STUB_PAYLOAD="$TEST_TMP/payload.json"
  : >"$GH_STUB_LOG"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ---------------------------------------------------------------------------
# 前提チェック
# ---------------------------------------------------------------------------

@test "gh コマンドが無い場合はエラーで終了する" {
  mkdir -p "$TEST_TMP/nogh"
  ln -s "$(command -v bash)" "$TEST_TMP/nogh/bash"

  run env PATH="$TEST_TMP/nogh" "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"gh コマンドが見つかりません"* ]]
}

@test "gh にログインしていない場合はエラーで終了する" {
  export GH_STUB_AUTH_FAIL=1

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"gh auth login"* ]]
}

# ---------------------------------------------------------------------------
# 引数の解析
# ---------------------------------------------------------------------------

@test "不明なブランチ戦略を指定するとエラーで終了する" {
  run "$SETUP_SCRIPT" --strategy trunk-based owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"不明なブランチ戦略"* ]]
  # 不正な入力でAPIを叩いてはいけない
  ! grep -q 'gh repo edit' "$GH_STUB_LOG"
}

@test "--strategy に値が無い場合はエラーで終了する" {
  run "$SETUP_SCRIPT" owner/repo --strategy

  [ "$status" -eq 1 ]
  [[ "$output" == *"--strategy には値が必要です"* ]]
}

@test "不明なオプションはエラーで終了する" {
  run "$SETUP_SCRIPT" --unknown-flag owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"不明なオプション"* ]]
}

@test "--help で使い方を表示して正常終了する" {
  run "$SETUP_SCRIPT" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"github-flow"* ]]
  [[ "$output" == *"git-flow"* ]]
}

@test "--approvals に整数以外を指定するとエラーで終了する" {
  run "$SETUP_SCRIPT" --approvals two owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"0以上の整数"* ]]
  ! grep -q 'gh repo edit' "$GH_STUB_LOG"
}

@test "--approvals に値が無い場合はエラーで終了する" {
  run "$SETUP_SCRIPT" owner/repo --approvals

  [ "$status" -eq 1 ]
  [[ "$output" == *"--approvals には値が必要です"* ]]
}

@test "リポジトリ名の形式が不正な場合はエラーで終了する" {
  run "$SETUP_SCRIPT" not-a-repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"<owner>/<repo> の形式"* ]]
}

@test "引数省略時は gh repo view でカレントリポジトリを解決する" {
  export GH_STUB_CURRENT_REPO="mongolyy/current-repo"

  run "$SETUP_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"対象リポジトリ: mongolyy/current-repo"* ]]
  grep -q 'gh repo edit mongolyy/current-repo' "$GH_STUB_LOG"
}

# ---------------------------------------------------------------------------
# GitHub Flow (デフォルト)
# ---------------------------------------------------------------------------

@test "戦略を省略すると github-flow が使われる" {
  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"ブランチ戦略: github-flow"* ]]
}

@test "github-flow は Squashマージのみを許可する" {
  run "$SETUP_SCRIPT" --strategy github-flow owner/repo
  [ "$status" -eq 0 ]

  local call
  call="$(grep 'gh repo edit' "$GH_STUB_LOG")"
  [[ "$call" == *"--enable-squash-merge"* ]]
  [[ "$call" == *"--enable-merge-commit=false"* ]]
  [[ "$call" == *"--enable-rebase-merge=false"* ]]
  [[ "$call" == *"--delete-branch-on-merge"* ]]
  [[ "$call" == *"--enable-auto-merge"* ]]
  [[ "$call" == *"--squash-merge-commit-title PR_TITLE"* ]]
  [[ "$call" == *"--squash-merge-commit-message PR_BODY"* ]]
}

@test "マージ設定に失敗した場合はRulesetに進まず終了する" {
  export GH_STUB_REPO_EDIT_FAIL=1

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -ne 0 ]
  ! grep -q -- '--method' "$GH_STUB_LOG"
}

@test "github-flow は developブランチを作成しない" {
  run "$SETUP_SCRIPT" --strategy github-flow owner/repo

  [ "$status" -eq 0 ]
  ! grep -q 'git/refs' "$GH_STUB_LOG"
}

@test "github-flow のRulesetはデフォルトブランチのみ保護する" {
  run "$SETUP_SCRIPT" --strategy github-flow owner/repo
  [ "$status" -eq 0 ]

  run jq -e . "$GH_STUB_PAYLOAD"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.name' "$GH_STUB_PAYLOAD")" = "team-branch-protection" ]
  [ "$(jq -r '.conditions.ref_name.include | length' "$GH_STUB_PAYLOAD")" = "1" ]
  [ "$(jq -r '.conditions.ref_name.include[0]' "$GH_STUB_PAYLOAD")" = "~DEFAULT_BRANCH" ]
}

# ---------------------------------------------------------------------------
# GitFlow
# ---------------------------------------------------------------------------

@test "git-flow は Merge commit と Squashマージを許可する" {
  export GH_STUB_DEVELOP_EXISTS=1

  run "$SETUP_SCRIPT" --strategy git-flow owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"ブランチ戦略: git-flow"* ]]

  local call
  call="$(grep 'gh repo edit' "$GH_STUB_LOG")"
  [[ "$call" == *"--enable-squash-merge"* ]]
  [[ "$call" == *"--enable-merge-commit"* ]]
  [[ "$call" != *"--enable-merge-commit=false"* ]]
  [[ "$call" == *"--enable-rebase-merge=false"* ]]
}

@test "git-flow は developブランチが無ければデフォルトブランチから作成する" {
  export GH_STUB_DEVELOP_EXISTS=0
  export GH_STUB_DEFAULT_BRANCH="main"

  run "$SETUP_SCRIPT" --strategy git-flow owner/repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"main から develop ブランチを作成しました"* ]]
  grep -q -- '--method POST repos/owner/repo/git/refs' "$GH_STUB_LOG"
  grep -q -- 'ref=refs/heads/develop' "$GH_STUB_LOG"
  grep -q -- 'sha=stub-sha-' "$GH_STUB_LOG"
}

@test "git-flow は developブランチが既に存在すれば作成しない (冪等性)" {
  export GH_STUB_DEVELOP_EXISTS=1

  run "$SETUP_SCRIPT" --strategy git-flow owner/repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"既に存在します"* ]]
  ! grep -q 'git/refs' "$GH_STUB_LOG"
}

@test "git-flow で developブランチの作成に失敗した場合はエラーで終了する" {
  export GH_STUB_DEVELOP_EXISTS=0
  export GH_STUB_BRANCH_CREATE_FAIL=1

  run "$SETUP_SCRIPT" --strategy git-flow owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"develop ブランチの作成に失敗しました"* ]]
}

@test "git-flow のRulesetはデフォルトブランチと develop を保護する" {
  export GH_STUB_DEVELOP_EXISTS=1

  run "$SETUP_SCRIPT" --strategy git-flow owner/repo
  [ "$status" -eq 0 ]

  run jq -e . "$GH_STUB_PAYLOAD"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.conditions.ref_name.include | length' "$GH_STUB_PAYLOAD")" = "2" ]
  [ "$(jq -r '.conditions.ref_name.include[0]' "$GH_STUB_PAYLOAD")" = "~DEFAULT_BRANCH" ]
  [ "$(jq -r '.conditions.ref_name.include[1]' "$GH_STUB_PAYLOAD")" = "refs/heads/develop" ]
}

# ---------------------------------------------------------------------------
# ブランチ保護 (Ruleset) — チーム向け設定
# ---------------------------------------------------------------------------

@test "Rulesetのペイロードがチーム開発向けの内容である" {
  run "$SETUP_SCRIPT" owner/repo
  [ "$status" -eq 0 ]

  [ "$(jq -r '.target' "$GH_STUB_PAYLOAD")" = "branch" ]
  [ "$(jq -r '.enforcement' "$GH_STUB_PAYLOAD")" = "active" ]
  [ "$(jq -r '[.rules[].type] | sort | join(",")' "$GH_STUB_PAYLOAD")" = "deletion,non_fast_forward,pull_request" ]

  local pr_params
  pr_params="$(jq -c '.rules[] | select(.type == "pull_request") | .parameters' "$GH_STUB_PAYLOAD")"
  # チーム開発なので承認レビューを1件以上必須にする
  [ "$(jq -r '.required_approving_review_count' <<<"$pr_params")" = "1" ]
  # push時に古いレビューを自動却下する
  [ "$(jq -r '.dismiss_stale_reviews_on_push' <<<"$pr_params")" = "true" ]
  # レビュースレッドの解決を必須にする
  [ "$(jq -r '.required_review_thread_resolution' <<<"$pr_params")" = "true" ]
}

@test "--approvals で必須承認レビュー数を変更できる" {
  run "$SETUP_SCRIPT" --approvals 2 owner/repo
  [ "$status" -eq 0 ]

  [ "$(jq -r '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count' "$GH_STUB_PAYLOAD")" = "2" ]
}

@test "--approvals 0 で個人リポジトリ向けにセルフマージ可能な設定にできる" {
  run "$SETUP_SCRIPT" --approvals 0 owner/repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"必須承認レビュー数: 0"* ]]
  [ "$(jq -r '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count' "$GH_STUB_PAYLOAD")" = "0" ]
}

@test "Ruleset一覧の照会に失敗しても新規作成にフォールバックする" {
  export GH_STUB_RULESET_LIST_FAIL=1

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 0 ]
  grep -q -- '--method POST' "$GH_STUB_LOG"
}

@test "同名のRulesetが無い場合は POST で新規作成する" {
  export GH_STUB_EXISTING_RULESET_ID=""

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 0 ]
  grep -q -- '--method POST repos/owner/repo/rulesets' "$GH_STUB_LOG"
  ! grep -q -- '--method PUT' "$GH_STUB_LOG"
  [[ "$output" == *"を作成しました"* ]]
}

@test "同名のRulesetがある場合は PUT で更新する (冪等性)" {
  export GH_STUB_EXISTING_RULESET_ID="12345"

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 0 ]
  grep -q -- '--method PUT repos/owner/repo/rulesets/12345' "$GH_STUB_LOG"
  ! grep -q -- '--method POST' "$GH_STUB_LOG"
  [[ "$output" == *"を更新しました"* ]]
}

@test "Rulesetの作成に失敗した場合はGitHub Proの注意書きを表示して終了する" {
  export GH_STUB_RULESET_WRITE_FAIL=1

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub Pro"* ]]
}
