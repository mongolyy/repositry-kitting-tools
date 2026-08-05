# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

GitHubリポジトリの初期設定を `gh` CLI で自動化するBashツール集。エントリーポイントは `setup-repo.sh` のみで、ブランチ戦略 (`github-flow` | `git-flow`) に応じてチーム開発向けのマージ設定とブランチ保護 (Ruleset) を適用する。スクリプトは冪等でなければならない — 何度実行しても安全であること (例: 同名Rulesetが存在する場合はPOSTで再作成せずPUTで更新する)。

ドキュメント・コードコメント・スクリプトのユーザー向け出力はすべて日本語で書く。この慣習に従うこと。

## コマンド

依存ツール: `bats`, `jq`, `shellcheck` (Ubuntu: `sudo apt-get install -y bats jq shellcheck` / macOS: `brew install bats-core jq shellcheck`)

```bash
bash -n setup-repo.sh                   # 構文チェック
shellcheck setup-repo.sh test/stubs/gh  # 静的解析
bats test/                              # 全テスト実行
bats test/setup-repo.bats --filter "冪等"  # テスト名 (正規表現) を絞って実行
```

CI (`.github/workflows/ci.yml`) は mainへのpushとPRで、上記3つのチェック (構文チェック・shellcheck・bats) をそのまま実行する。

## テストの仕組み

`test/setup-repo.bats` のテストは実際のGitHub APIには一切触れない。`setup()` が `test/stubs/gh` を `PATH` の先頭に置くため、すべての `gh` 呼び出しはスタブに差し替わる。スタブの動作:

- 呼び出された引数を `$GH_STUB_LOG` に追記する — テストはこのログを検証して、どの `gh` コマンドがどのフラグで実行されたかを確認する。
- `--input -` で渡されたリクエストボディを `$GH_STUB_PAYLOAD` に保存する — テストは `jq` でこれを検証して、実際に送信されるRuleset JSONの内容を確認する。
- `GH_STUB_*` 環境変数 (例: `GH_STUB_AUTH_FAIL`, `GH_STUB_EXISTING_RULESET_ID`, `GH_STUB_DEVELOP_EXISTS`) で成功/失敗や返り値を切り替える — 一覧はスタブ冒頭のコメントに記載。

`setup-repo.sh` に新しい `gh` 呼び出しを追加する場合は、スタブにも対応を追加する必要がある (未対応の呼び出しは「未対応の呼び出しです」を出力して exit 1 する)。テストで結果を制御したい場合は `GH_STUB_*` 変数も追加する。

## setup-repo.sh の構成

スクリプトはコメントで区切られたセクションで構成され、実行順に並んでいる: 設定 (適用内容を変えるには `RULESET_NAME` や `ruleset_json()` をここで編集)、引数の解析、前提チェック (`gh` のインストール・ログイン確認)、対象リポジトリの解決 (省略時は `gh repo view` でカレントリポジトリにフォールバック)、マージ設定、developブランチ作成 (git-flowのみ)、Rulesetの作成または更新。バリデーションエラーはAPI呼び出しの前に終了しなければならない — テストがこれを検証している。

Rulesetの保護対象はリテラルのブランチ名ではなく `~DEFAULT_BRANCH` を指定しているため、デフォルトブランチをリネームしても保護が追従する。
