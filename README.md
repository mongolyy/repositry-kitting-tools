# repositry-kitting-tools

GitHubリポジトリの初期設定を自動化するツール集です。

## setup-repo.sh

作成済みのGitHubリポジトリに対して、以下の初期設定を [gh CLI](https://cli.github.com/) で適用するスクリプトです。何度実行しても安全(冪等)です。

### 適用される設定

**マージ設定**

- Squashマージのみ許可 (Merge commit / Rebase merge は無効化)
- マージ後のブランチ自動削除
- auto-merge の有効化
- Squashマージ時のコミットメッセージは PRタイトル + PR本文

**ブランチ保護 (Ruleset)**

デフォルトブランチに `default-branch-protection` という名前のRulesetを作成します。

- PR経由でのマージを必須化 (直接pushの禁止)
  - 承認レビュー数は 0 (個人リポジトリでもセルフマージ可能)
- force push の禁止
- ブランチ削除の禁止

対象は `~DEFAULT_BRANCH` 指定なので、デフォルトブランチをリネームしても追従します。

### 前提条件

- [gh CLI](https://cli.github.com/) がインストール済みであること
- `gh auth login` でログイン済みであること

### 使い方

```bash
# リポジトリを指定して適用
./setup-repo.sh <owner>/<repo>

# 引数を省略すると、カレントディレクトリのリポジトリに適用
./setup-repo.sh
```

実行後、以下のページで設定を確認できます。

- `https://github.com/<owner>/<repo>/settings` (マージ設定)
- `https://github.com/<owner>/<repo>/settings/rules` (Ruleset)

### 注意事項

- 個人アカウントの **プライベートリポジトリ** でRulesetを有効化するには **GitHub Pro** が必要です。パブリックリポジトリは無料プランで利用できます。
- 設定内容を変更したい場合は、スクリプト冒頭の「設定」セクション (`ruleset_json` など) を編集してください。

## setup-team-repo.sh

チーム開発向けの推奨設定を適用するスクリプトです。ブランチ戦略を **GitHub Flow** / **GitFlow** から選択でき、戦略に応じて設定内容が切り替わります。何度実行しても安全(冪等)です。

### 使い方

```bash
# GitHub Flow (デフォルト)
./setup-team-repo.sh <owner>/<repo>
./setup-team-repo.sh --strategy github-flow <owner>/<repo>

# GitFlow
./setup-team-repo.sh --strategy git-flow <owner>/<repo>

# 引数を省略すると、カレントディレクトリのリポジトリに適用
./setup-team-repo.sh --strategy git-flow
```

### 共通で適用される設定

**マージ設定**

- マージ後のブランチ自動削除
- auto-merge の有効化
- Squashマージ時のコミットメッセージは PRタイトル + PR本文

**ブランチ保護 (Ruleset)**

保護対象ブランチに `team-branch-protection` という名前のRulesetを作成します。

- PR経由でのマージを必須化 (直接pushの禁止)
  - **承認レビュー1件以上を必須** (チーム開発向け)
  - push時に古いレビューを自動却下
  - レビュースレッドの解決を必須化
- force push の禁止
- ブランチ削除の禁止

### 戦略ごとの違い

| 設定 | github-flow | git-flow |
| --- | --- | --- |
| マージ方法 | Squashのみ | Squash + Merge commit |
| developブランチ | 作成しない | 無ければデフォルトブランチから作成 |
| 保護対象ブランチ | デフォルトブランチのみ | デフォルトブランチ + develop |

GitHub Flow はデフォルトブランチに直接featureブランチをマージするシンプルな戦略なので、履歴が一直線になるSquashマージのみを許可します。

GitFlow は develop で開発を進め、release / hotfix ブランチ経由でデフォルトブランチ(main)にリリースする戦略なので、リリースの履歴を残せる Merge commit も許可し、develop ブランチの作成・保護まで行います。

### 前提条件・注意事項

setup-repo.sh と同じです (gh CLI + ログイン済み、プライベートリポジトリのRulesetにはGitHub Proが必要)。

## 開発

### テスト

`test/*.bats` に [bats-core](https://github.com/bats-core/bats-core) によるユニットテストがあります。gh CLI は `test/stubs/gh` のスタブに差し替わるため、**実際のGitHub APIは呼ばれず**、認証もネットワークも不要です。

「どんな引数で `gh` が呼ばれたか」「同名Rulesetの有無でPOST/PUTが切り替わるか」「送信されるRuleset JSONの内容」を検証しています。

```bash
# 依存ツールのインストール
#   Ubuntu: sudo apt-get install -y bats jq shellcheck
#   macOS:  brew install bats-core jq shellcheck

bash -n setup-repo.sh setup-team-repo.sh                      # 構文チェック
shellcheck setup-repo.sh setup-team-repo.sh test/stubs/gh     # 静的解析
bats test/                                                    # ユニットテスト
```

上記3つは `.github/workflows/ci.yml` でpush / pull request時に自動実行されます。

## License

[MIT](./LICENSE)
