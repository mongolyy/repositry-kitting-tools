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

## 開発

### テスト

`test/setup-repo.bats` に [bats-core](https://github.com/bats-core/bats-core) によるユニットテストがあります。gh CLI は `test/stubs/gh` のスタブに差し替わるため、**実際のGitHub APIは呼ばれず**、認証もネットワークも不要です。

「どんな引数で `gh` が呼ばれたか」「同名Rulesetの有無でPOST/PUTが切り替わるか」「送信されるRuleset JSONの内容」を検証しています。

```bash
# 依存ツールのインストール
#   Ubuntu: sudo apt-get install -y bats jq shellcheck
#   macOS:  brew install bats-core jq shellcheck

bash -n setup-repo.sh                      # 構文チェック
shellcheck setup-repo.sh test/stubs/gh     # 静的解析
bats test/                                 # ユニットテスト
```

上記3つは `.github/workflows/ci.yml` でpush / pull request時に自動実行されます。

## License

[MIT](./LICENSE)
