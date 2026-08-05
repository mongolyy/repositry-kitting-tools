#!/usr/bin/env bash
#
# setup-repo.sh — GitHubリポジトリの初期設定を適用するスクリプト
#
# 適用する設定:
#   1. マージ設定 (Squashマージのみ許可、マージ後ブランチ自動削除、auto-merge有効化)
#   2. デフォルトブランチの保護 (Ruleset: PR必須、force push禁止、ブランチ削除禁止)
#
# 使い方:
#   ./setup-repo.sh <owner>/<repo>   # 対象リポジトリを指定
#   ./setup-repo.sh                  # 省略時はカレントディレクトリのリポジトリ
#
# 何度実行しても安全(冪等)です。

set -euo pipefail

# ---------------------------------------------------------------------------
# 設定 (必要に応じてここを編集)
# ---------------------------------------------------------------------------

RULESET_NAME="default-branch-protection"

# デフォルトブランチに適用するRuleset。
# required_approving_review_count: 0 なので個人リポジトリでもセルフマージ可能。
ruleset_json() {
  cat <<JSON
{
  "name": "${RULESET_NAME}",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON
}

# ---------------------------------------------------------------------------
# 前提チェック
# ---------------------------------------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
  echo "エラー: gh コマンドが見つかりません。https://cli.github.com/ からインストールしてください。" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "エラー: gh にログインしていません。'gh auth login' を実行してください。" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 対象リポジトリの解決
# ---------------------------------------------------------------------------

if [[ $# -ge 1 ]]; then
  REPO="$1"
else
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || {
    echo "エラー: 対象リポジトリを特定できません。'./setup-repo.sh <owner>/<repo>' の形式で指定してください。" >&2
    exit 1
  }
fi

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "エラー: リポジトリは <owner>/<repo> の形式で指定してください (指定値: $REPO)" >&2
  exit 1
fi

echo "対象リポジトリ: $REPO"

# ---------------------------------------------------------------------------
# 1. マージ設定
# ---------------------------------------------------------------------------

echo "==> マージ設定を適用中..."
gh repo edit "$REPO" \
  --enable-squash-merge \
  --enable-merge-commit=false \
  --enable-rebase-merge=false \
  --delete-branch-on-merge \
  --enable-auto-merge \
  --squash-merge-commit-title PR_TITLE \
  --squash-merge-commit-message PR_BODY
echo "    Squashマージのみ許可 / マージ後ブランチ自動削除 / auto-merge有効化 ... 完了"

# ---------------------------------------------------------------------------
# 2. デフォルトブランチの保護 (Ruleset)
# ---------------------------------------------------------------------------

echo "==> ブランチ保護 (Ruleset) を適用中..."

existing_ruleset_id="$(gh api "repos/${REPO}/rulesets" \
  --jq ".[] | select(.name == \"${RULESET_NAME}\") | .id" 2>/dev/null | head -n1)" || existing_ruleset_id=""

if [[ -n "$existing_ruleset_id" ]]; then
  if ruleset_json | gh api --method PUT "repos/${REPO}/rulesets/${existing_ruleset_id}" --input - >/dev/null; then
    echo "    既存のRuleset '${RULESET_NAME}' (id: ${existing_ruleset_id}) を更新しました"
  else
    echo "エラー: Rulesetの更新に失敗しました。" >&2
    exit 1
  fi
else
  if ruleset_json | gh api --method POST "repos/${REPO}/rulesets" --input - >/dev/null; then
    echo "    Ruleset '${RULESET_NAME}' を作成しました"
  else
    echo "エラー: Rulesetの作成に失敗しました。" >&2
    echo "ヒント: 個人アカウントのプライベートリポジトリでRulesetを有効化するには GitHub Pro が必要です。" >&2
    echo "       パブリックリポジトリ、または Pro / Team / Enterprise プランでは利用できます。" >&2
    exit 1
  fi
fi

echo ""
echo "✅ ${REPO} の初期設定が完了しました"
echo "   確認: https://github.com/${REPO}/settings"
echo "         https://github.com/${REPO}/settings/rules"
