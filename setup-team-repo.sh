#!/usr/bin/env bash
#
# setup-team-repo.sh — チーム開発向けのGitHubリポジトリ推奨設定を適用するスクリプト
#
# ブランチ戦略を GitHub Flow / GitFlow から選択でき、戦略に応じて
# マージ設定とブランチ保護 (Ruleset) を切り替えます。
#
# 共通で適用する設定:
#   - マージ後ブランチ自動削除、auto-merge有効化
#   - 保護ブランチへのPR必須 (承認レビュー1件以上、古いレビューの自動却下、
#     レビュースレッドの解決必須)、force push禁止、ブランチ削除禁止
#
# 戦略ごとの違い:
#   github-flow (デフォルト):
#     - Squashマージのみ許可 (コミットメッセージは PRタイトル + PR本文)
#     - デフォルトブランチのみ保護
#   git-flow:
#     - Squashマージ (feature -> develop) と Merge commit (release/hotfix -> main) を許可
#     - develop ブランチが無ければデフォルトブランチから作成
#     - デフォルトブランチと develop を保護
#
# 使い方:
#   ./setup-team-repo.sh [--strategy github-flow|git-flow] [<owner>/<repo>]
#
# 何度実行しても安全(冪等)です。

set -euo pipefail

# ---------------------------------------------------------------------------
# 設定 (必要に応じてここを編集)
# ---------------------------------------------------------------------------

RULESET_NAME="team-branch-protection"
GITFLOW_DEVELOP_BRANCH="develop"

# チーム開発向けの保護ブランチRuleset。
# include には保護対象ブランチのリスト (JSON配列) を渡す。
ruleset_json() {
  local include_refs="$1"
  cat <<JSON
{
  "name": "${RULESET_NAME}",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ${include_refs},
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON
}

# ---------------------------------------------------------------------------
# 引数の解析
# ---------------------------------------------------------------------------

usage() {
  cat <<'USAGE'
使い方: ./setup-team-repo.sh [--strategy github-flow|git-flow] [<owner>/<repo>]

オプション:
  --strategy <strategy>  ブランチ戦略 (github-flow | git-flow)。省略時は github-flow。
  -h, --help             このヘルプを表示する。

リポジトリを省略すると、カレントディレクトリのリポジトリに適用します。
USAGE
}

STRATEGY="github-flow"
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strategy)
      if [[ $# -lt 2 ]]; then
        echo "エラー: --strategy には値が必要です (github-flow | git-flow)" >&2
        exit 1
      fi
      STRATEGY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "エラー: 不明なオプションです: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$REPO" ]]; then
        echo "エラー: リポジトリは1つだけ指定してください" >&2
        exit 1
      fi
      REPO="$1"
      shift
      ;;
  esac
done

if [[ "$STRATEGY" != "github-flow" && "$STRATEGY" != "git-flow" ]]; then
  echo "エラー: 不明なブランチ戦略です: $STRATEGY (github-flow | git-flow から選択してください)" >&2
  exit 1
fi

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

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || {
    echo "エラー: 対象リポジトリを特定できません。'./setup-team-repo.sh <owner>/<repo>' の形式で指定してください。" >&2
    exit 1
  }
fi

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "エラー: リポジトリは <owner>/<repo> の形式で指定してください (指定値: $REPO)" >&2
  exit 1
fi

echo "対象リポジトリ: $REPO"
echo "ブランチ戦略: $STRATEGY"

# ---------------------------------------------------------------------------
# 1. マージ設定
# ---------------------------------------------------------------------------

echo "==> マージ設定を適用中..."

if [[ "$STRATEGY" == "github-flow" ]]; then
  gh repo edit "$REPO" \
    --enable-squash-merge \
    --enable-merge-commit=false \
    --enable-rebase-merge=false \
    --delete-branch-on-merge \
    --enable-auto-merge \
    --squash-merge-commit-title PR_TITLE \
    --squash-merge-commit-message PR_BODY
  echo "    Squashマージのみ許可 / マージ後ブランチ自動削除 / auto-merge有効化 ... 完了"
else
  # GitFlowでは release/hotfix -> main の履歴を残すため Merge commit も許可する
  gh repo edit "$REPO" \
    --enable-squash-merge \
    --enable-merge-commit \
    --enable-rebase-merge=false \
    --delete-branch-on-merge \
    --enable-auto-merge \
    --squash-merge-commit-title PR_TITLE \
    --squash-merge-commit-message PR_BODY
  echo "    Squashマージ + Merge commit許可 / マージ後ブランチ自動削除 / auto-merge有効化 ... 完了"
fi

# ---------------------------------------------------------------------------
# 2. developブランチの作成 (GitFlowのみ)
# ---------------------------------------------------------------------------

if [[ "$STRATEGY" == "git-flow" ]]; then
  echo "==> ${GITFLOW_DEVELOP_BRANCH} ブランチを確認中..."

  if gh api "repos/${REPO}/branches/${GITFLOW_DEVELOP_BRANCH}" >/dev/null 2>&1; then
    echo "    ${GITFLOW_DEVELOP_BRANCH} ブランチは既に存在します"
  else
    default_branch="$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
    default_sha="$(gh api "repos/${REPO}/git/ref/heads/${default_branch}" --jq .object.sha)"

    if gh api --method POST "repos/${REPO}/git/refs" \
      -f ref="refs/heads/${GITFLOW_DEVELOP_BRANCH}" \
      -f sha="$default_sha" >/dev/null; then
      echo "    ${default_branch} から ${GITFLOW_DEVELOP_BRANCH} ブランチを作成しました"
    else
      echo "エラー: ${GITFLOW_DEVELOP_BRANCH} ブランチの作成に失敗しました。" >&2
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3. ブランチ保護 (Ruleset)
# ---------------------------------------------------------------------------

echo "==> ブランチ保護 (Ruleset) を適用中..."

if [[ "$STRATEGY" == "git-flow" ]]; then
  include_refs="[\"~DEFAULT_BRANCH\", \"refs/heads/${GITFLOW_DEVELOP_BRANCH}\"]"
else
  include_refs='["~DEFAULT_BRANCH"]'
fi

existing_ruleset_id="$(gh api "repos/${REPO}/rulesets" \
  --jq ".[] | select(.name == \"${RULESET_NAME}\") | .id" 2>/dev/null | head -n1)" || existing_ruleset_id=""

if [[ -n "$existing_ruleset_id" ]]; then
  if ruleset_json "$include_refs" | gh api --method PUT "repos/${REPO}/rulesets/${existing_ruleset_id}" --input - >/dev/null; then
    echo "    既存のRuleset '${RULESET_NAME}' (id: ${existing_ruleset_id}) を更新しました"
  else
    echo "エラー: Rulesetの更新に失敗しました。" >&2
    exit 1
  fi
else
  if ruleset_json "$include_refs" | gh api --method POST "repos/${REPO}/rulesets" --input - >/dev/null; then
    echo "    Ruleset '${RULESET_NAME}' を作成しました"
  else
    echo "エラー: Rulesetの作成に失敗しました。" >&2
    echo "ヒント: 個人アカウントのプライベートリポジトリでRulesetを有効化するには GitHub Pro が必要です。" >&2
    echo "       パブリックリポジトリ、または Pro / Team / Enterprise プランでは利用できます。" >&2
    exit 1
  fi
fi

echo ""
echo "✅ ${REPO} のチーム開発向け設定 (${STRATEGY}) が完了しました"
echo "   確認: https://github.com/${REPO}/settings"
echo "         https://github.com/${REPO}/settings/rules"
