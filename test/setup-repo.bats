#!/usr/bin/env bats
#
# setup-repo.sh のユニットテスト。
# gh CLI はスタブ (test/stubs/gh) に差し替えるため、実際のGitHub APIは呼ばれない。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP_SCRIPT="$REPO_ROOT/setup-repo.sh"

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
# 対象リポジトリの解決
# ---------------------------------------------------------------------------

@test "リポジトリ名の形式が不正な場合はエラーで終了する" {
  run "$SETUP_SCRIPT" not-a-repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"<owner>/<repo> の形式"* ]]
  # 不正な入力でAPIを叩いてはいけない
  ! grep -q 'gh repo edit' "$GH_STUB_LOG"
}

@test "引数省略時は gh repo view でカレントリポジトリを解決する" {
  export GH_STUB_CURRENT_REPO="mongolyy/current-repo"

  run "$SETUP_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"対象リポジトリ: mongolyy/current-repo"* ]]
  grep -q 'gh repo edit mongolyy/current-repo' "$GH_STUB_LOG"
}

@test "引数省略かつカレントリポジトリを解決できない場合はエラーで終了する" {
  export GH_STUB_CURRENT_REPO=""

  run "$SETUP_SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"対象リポジトリを特定できません"* ]]
}

@test "引数で指定したリポジトリが gh repo view より優先される" {
  export GH_STUB_CURRENT_REPO="mongolyy/current-repo"

  run "$SETUP_SCRIPT" mongolyy/explicit-repo

  [ "$status" -eq 0 ]
  grep -q 'gh repo edit mongolyy/explicit-repo' "$GH_STUB_LOG"
  ! grep -q 'current-repo' "$GH_STUB_LOG"
}

# ---------------------------------------------------------------------------
# マージ設定
# ---------------------------------------------------------------------------

@test "Squashマージのみを許可するフラグで gh repo edit を呼ぶ" {
  run "$SETUP_SCRIPT" owner/repo
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

# ---------------------------------------------------------------------------
# ブランチ保護 (Ruleset)
# ---------------------------------------------------------------------------

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

@test "Ruleset一覧の照会に失敗しても新規作成にフォールバックする" {
  export GH_STUB_RULESET_LIST_FAIL=1

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 0 ]
  grep -q -- '--method POST' "$GH_STUB_LOG"
}

@test "Rulesetの作成に失敗した場合はGitHub Proの注意書きを表示して終了する" {
  export GH_STUB_RULESET_WRITE_FAIL=1

  run "$SETUP_SCRIPT" owner/repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub Pro"* ]]
}

@test "送信されるRulesetのペイロードが期待通りである" {
  run "$SETUP_SCRIPT" owner/repo
  [ "$status" -eq 0 ]

  # 妥当なJSONであること
  run jq -e . "$GH_STUB_PAYLOAD"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.name' "$GH_STUB_PAYLOAD")" = "default-branch-protection" ]
  [ "$(jq -r '.target' "$GH_STUB_PAYLOAD")" = "branch" ]
  [ "$(jq -r '.enforcement' "$GH_STUB_PAYLOAD")" = "active" ]

  # デフォルトブランチのリネームに追従するため ~DEFAULT_BRANCH を使う
  [ "$(jq -r '.conditions.ref_name.include | length' "$GH_STUB_PAYLOAD")" = "1" ]
  [ "$(jq -r '.conditions.ref_name.include[0]' "$GH_STUB_PAYLOAD")" = "~DEFAULT_BRANCH" ]

  [ "$(jq -r '[.rules[].type] | sort | join(",")' "$GH_STUB_PAYLOAD")" = "deletion,non_fast_forward,pull_request" ]

  # 個人リポジトリでもセルフマージできるよう承認必須数は0
  [ "$(jq -r '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count' "$GH_STUB_PAYLOAD")" = "0" ]
}

@test "更新時も作成時と同じペイロードを送る" {
  export GH_STUB_EXISTING_RULESET_ID="12345"

  run "$SETUP_SCRIPT" owner/repo
  [ "$status" -eq 0 ]

  [ "$(jq -r '.name' "$GH_STUB_PAYLOAD")" = "default-branch-protection" ]
  [ "$(jq -r '[.rules[].type] | sort | join(",")' "$GH_STUB_PAYLOAD")" = "deletion,non_fast_forward,pull_request" ]
}
