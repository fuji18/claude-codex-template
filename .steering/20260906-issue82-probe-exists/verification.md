# 検証結果(Issue #82: 検証プローブのホスト実行経路を閉じる)

手順は design.md §10 のとおり。`AGENTS.md` を `/tmp/AGENTS.md.bak` にバックアップし、
86 行目のマーカーだけを line-targeted `sed` で差し替えて
`CODEX_DELEGATE_ACK_SECRETS=1 bash .claude/scripts/delegate-codex.sh impl /tmp/not-steering`
を実行(入口検査5-1 で `exit 2` になるため codex は起動されず、入口検査3 の出力だけを観測)。
全 V の実行後にバックアップから復元し、`git diff -- AGENTS.md` で D-1/D-2/D-3 の変更のみに
なっていることを確認した。

| ID | プローブ | 結果 | 実測 |
| --- | --- | --- | --- |
| V1 | `exists node_modules/.bin/eslint` | pass | `検証プローブ(存在確認・プロセス起動なし): node_modules/.bin/eslint` が出力、`exit=2`(検査5-1) |
| V2 | `exists node_modules/.bin/does-not-exist` | pass | `検証プローブの対象が存在しません: node_modules/.bin/does-not-exist`、`exit=3`(`EX_UNAVAIL`) |
| V3 | `exists ../../etc/passwd` | pass | `exists のパスが不正です(リポジトリ相対のみ。.. と絶対パスは不可): ../../etc/passwd` で形式検査により未実行、`exit=2` |
| V4 | `exists /etc/passwd` | pass | 同上メッセージ(絶対パス)、`exit=2` |
| V5 | `exists node_modules/../../../etc/passwd` | pass | 同上メッセージ(`..` を含む)、`exit=2` |
| V6 | `exists -rf` | pass | 同上メッセージ(`-` 始まり)、`exit=2` |
| V7 | `exists`(1 トークン) | pass | `exists 形式は exists <相対パス> の 2 トークンである必要があります`、`exit=2` |
| V8 | `exists a b`(3 トークン) | pass | 同上メッセージ、`exit=2` |
| V9 | `exists --version` | pass | `exists のパスが不正です(...): --version`(`-` 始まりで弾かれ、P1 として通らない)、`exit=2` |
| V10 | `npx --no-install eslint --version` | pass | `検証プローブを実行します: npx --no-install eslint --version`(後方互換で従来どおり実行)、`exit=2` |
| V11 | `node --version` / `java -version` | pass | いずれも `検証プローブを実行します: ...`(後方互換で従来どおり実行)、`exit=2` |
| V12 | `python3 -I -m pytest --version` | pass | `検証プローブを実行します: python3 -I -m pytest --version` が出力され形式検査は通過(pytest 未インストールのため実行自体は失敗し `exit=3`) |
| V13 | バックアップからの復元確認 | pass | `AGENTS.md` を `/tmp/AGENTS.md.bak` から復元後、`git diff -- AGENTS.md` は D-1(マーカー変更)/ D-2(§2 形式制約ブロック)/ D-3(155 行目の禁止領域説明)の 3 箇所のみ |
| V14 | `npm run lint` | pass | エラーなし |
| V15 | `npm run format:check` | pass | `All matched files use Prettier code style!` |
| V16 | `bash .claude/scripts/check-guard-integrity.sh` | pass | 出力なし、`exit=0` |

## 補足

- すべての委託起動は入口検査5-1(`/tmp/not-steering` が正規のステアリングディレクトリでないため)で
  `exit 2` になり、codex 自体は一度も起動していない。観測対象は入口検査3(検証プローブ判定)の
  出力のみ。
- `bash -n .claude/scripts/delegate-codex.sh` は実装直後(T5)に実施し `SYNTAX_OK` を確認済み。
