# 設計: ハーネスレビュー指摘の修正

## 1. 司令塔専用ルールの自動ロードを止める

- **ディレクトリは移動しない。** 移動すると参照(40 箇所超)・委託禁止領域(`FORBIDDEN_PATHS` と `delegation-policy.md` の表)・`template-manifest.json` を同時に直す必要があり、下流プロジェクトの `/sync-template` でも旧ディレクトリが残る
- 代わりに Claude Code の公式機能「path-scoped rules」を使う。`lead/*.md` と `mode/*.md` の先頭に YAML frontmatter を置き、`paths` を**そのファイル自身のディレクトリ**にする
  - `lead/*.md` → `paths: [".claude/rules/lead/**"]`
  - `mode/*.md` → `paths: [".claude/rules/mode/**"]`
  - 意味は「このルール自体を編集・参照しているときだけ載る」。それ以外では自動ロードされない
- frontmatter はファイルの 1 行目に置く(既存の HTML コメントより前)
- **SessionStart hook は本文を貼らない。** 出力の上限(約 10,000 文字)を超えるとプレビューに切り詰められるため、司令塔専用ルールは「作業前に Read で読むファイル一覧」として出す
- `mode/<mode>.md` は 4KB 程度なので従来どおり本文を注入する。frontmatter は awk で取り除いて出す

## 2. リモートセッションのブランチをポリシー準拠に切り替える

- 場所: `session-start.sh`。条件は `CLAUDE_CODE_REMOTE=true` かつ `source=startup`
- 現在のブランチが `allowedPrefixes` のどれにも前方一致せず、保護ブランチでもなく、`remoteSessionPrefix` が空でないとき:
  - 新しい名前 = `remoteSessionPrefix` + 現在のブランチ名(例: `ccr-xxxx` → `claude/ccr-xxxx`)
  - 既にローカルにあれば `git switch`、無ければ `git switch -c`。作業ツリーの変更は持ち越される(switch -c は HEAD を変えない)
  - 失敗したら警告を出すだけ(フェイルオープン)
- 切り替えたことと、push 先(`git push -u origin <新ブランチ>`)を出力する
- `lead/branch-and-tickets.md` に、プラットフォームが指定したポリシー外のブランチではなく切り替え後のブランチへ push する運用を、ユーザーが承認していることを明記する

## 3. push のガード

- 判定の実体は `.claude/scripts/check-push-policy.sh`(標準入力から pre-push の行 `<local ref> <local sha> <remote ref> <remote sha>` を読む)
  - `refs/heads/` 以外(タグ等)は対象外
  - 宛先が `protectedBranches` → 違反(削除も含む)
  - 削除(local sha が全 0)で保護ブランチ以外 → 通す
  - 宛先のブランチ名が `allowedPrefixes` に前方一致しない → 違反
  - 違反は exit 1、問題なしは exit 0。ポリシーや jq が無ければ exit 0(フェイルオープン)
- `.husky/pre-push` は `pre-commit` と同じ形で呼ぶ(`&& rc=0 || rc=$?` で受け、1 だけを中断に読み替える)
- `check-branch-policy.sh` に `git push … --no-verify` のブロックを足す(Claude 経由で pre-push を迂回する唯一の経路)
- `template-manifest.json` の `merge` に `.husky/pre-push` を足す
