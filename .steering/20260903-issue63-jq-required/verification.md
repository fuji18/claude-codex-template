# 実測記録: 委託経路で jq を必須化する(#63)

`design.md` §6 の実測手順に沿って、`$NOJQ`(jq 以外の実行ファイルへの symlink を張った PATH)を
作成した上で V1〜V12 を実行した結果。

| # | コマンド | 期待 | 実際 |
| --- | --- | --- | --- |
| V1 | `PATH="$NOJQ" bash .claude/scripts/delegate-codex.sh impl .steering/20260903-issue63-jq-required; echo $?` | `3` + `delegate-codex: jq が見つかりません…` | `rc=3`。メッセージ: `delegate-codex: jq が見つかりません。run record を安全に読み書きできないため中止します(jq を入れてください)。`(入口検査4 の codex CLI 不在ではないことを確認) |
| V2 | `PATH="$NOJQ" bash .claude/scripts/delegate-codex.sh --print-forbidden \| wc -l; echo rc=$?` | jq あり実行時と同じ行数 / rc=0 | jq あり: 32 行 / jq なし: 32 行(一致)。rc=0 |
| V3 | `PATH="$NOJQ" bash .claude/scripts/codex-run.sh pending; echo $?` | 出力なし / 0 | 出力なし、rc=0 |
| V4 | `PATH="$NOJQ" bash .claude/hooks/session-start.sh </dev/null; echo $?` | 0(注入本文が出て、Codex 委託の節だけが消える) | rc=0。注入本文は出力され、「Codex 委託(未検収)」の節は出力に含まれない |
| V5 | `PATH="$NOJQ" bash .claude/scripts/codex-run.sh list; echo $?` | 2 + jq のメッセージ | `rc=2`。メッセージ: `codex-run: jq が見つかりません。run record を安全に読み書きできないため中止します(jq を入れてください)。` |
| V6 | `PATH="$NOJQ" bash .claude/scripts/codex-run.sh accept <既存 id>; echo $?` | 2。record が書き換わっていないこと | `rc=2`。対象 record(`20260823-133418-92576.json`)の md5 は実行前後で一致(書き換えなし) |
| V7 | `bash .claude/scripts/codex-run.sh pending`(jq あり) | 従来どおり未検収一覧が出る | 未検収 33 件の一覧が出力された |
| V8 | `bash .claude/scripts/codex-run.sh list --all \| head` | 全フィールドが埋まっている | id / mode / status / branch / accepted / steering がすべて埋まって出力された |
| V9 | 使い捨て record を作って `accept` → `set-status failed` → `jq .` | rc=0 / `accepted: true` / `status: "failed"` / JSON として妥当。`.bak` `.tmp.*` 残らない | 両コマンドとも rc=0。`jq .` の出力は `"status": "failed"` / `"accepted": true` で妥当な JSON。`.bak` `.tmp.*` は残らず、検証後に record を削除済み |
| V10 | `CODEX_DELEGATE_NO_SELF_COPY=1 bash .claude/scripts/delegate-codex.sh --print-forbidden \| wc -l` | V2 と同じ行数 | 32 行(一致) |
| V11 | `bash .claude/scripts/delegate-codex.sh --print-forbidden >/dev/null; echo $?` | 0(警告 `lib-record.sh の一時コピーを使えていません` が出ないこと) | rc=0。該当警告は stderr に出力されなかった |
| V12 | `bash -n` を 3 本 + `shellcheck` | エラーなし | `bash -n` は 3 本すべて OK。`shellcheck` は info/style レベルの指摘が 7 件あるが、変更前(`git stash` で確認)と完全に同一の指摘であり、今回の変更に起因するものはない |

## §6-3: `check-guard-integrity.sh`

`bash .claude/scripts/check-guard-integrity.sh`(引数なし)を実行し、rc=0(出力なし)。
ガードレール健全性は変わっていない。

## 補足

- `shellcheck` は本環境に未インストールだったため `sudo apt-get install -y shellcheck` で導入した(devcontainer / CI には通常同梱されている想定)
- V9 で作成した使い捨て record(`.harness/codex-runs/99999999-000000-*.json`)は検証直後に削除済み。`.harness/codex-runs/` は `.gitignore` 対象のため `git status` に差分は出ない
