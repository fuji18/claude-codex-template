# 検証記録: explore / review の run record を auto-accept する(Issue #22)

## 1. 構文チェック(design.md §4-1)

```bash
bash -n .claude/scripts/delegate-codex.sh
```

結果: エラーなし(exit 0)。

## 2. スタブ Codex(design.md §4-2 と同一)

```bash
#!/bin/bash
[ "${1:-}" = "login" ] && exit 0
LASTPATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output-last-message) LASTPATH="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$LASTPATH" ] && printf 'スタブの調査結果サマリー\n' > "$LASTPATH"
exit 0
```

`PATH` の先頭にこのスタブを置き、実 Codex を呼ばずに `explore` / `review` を通した。
スクラッチディレクトリに置き、リポジトリにはコミットしていない。

design.md との相違点: 実行時にワークツリーの機密ファイル検査(`.claude/settings.local.json`
が該当)に引っかかったため、`CODEX_DELEGATE_ACK_SECRETS=1` を付けて実行した。
これは今回の変更(read-only の auto-accept)とは無関係な既存の入口検査であり、
`delegate-codex.sh` 本体の追加変更は不要だった。

## 3. シナリオ1 — `explore` を正常終了

```
[codex:explore] status=completed id=20260826-030635-55423 exit=0
```

record:

```json
{
  "status": "completed",
  "accepted": true
}
```

`accepted` はヒアドキュメントの最終フィールドでカンマ無し(`tail -3` で確認)。
`bash .claude/scripts/codex-run.sh pending` には出ず、`list --all` には
`accepted=true` として出た。期待どおり。

## 4. シナリオ2 — `review HEAD` を正常終了

```
[codex:review] status=completed id=20260826-030656-56341 exit=0
```

record: `status=completed` / `accepted=true`。`pending` には出ず、`list --all` には
`accepted=true` として出た。シナリオ1と同じ結果パターンで期待どおり。

## 5. シナリオ3 — スタブを `exit 1` に変えて `explore`

```
[codex:explore] status=failed id=20260826-030714-57186 exit=2
```

record: `status=failed` / `accepted=false`。`bash .claude/scripts/codex-run.sh pending`
に以下のとおり出た。

```
- 20260826-030714-57186 / mode=explore / 対象 テスト用の調査指示(失敗)
  → 検収を通したら `bash .claude/scripts/codex-run.sh accept 20260826-030714-57186`
```

異常終了は従来どおり pending に出ることを確認した。期待どおり。

## 6. シナリオ4 — impl の `completed` は `accepted: false` のまま

既存の impl 完了レコードのうち直近のもの(`.harness/codex-runs/20260824-231027-99066.json`)
は `accepted=false` だったが、これは今回の変更前から存在する record であり、
今回追加した分岐の直接証拠にはならない(他の accepted=true な impl レコードは
`codex-run.sh accept` による事後更新)。design.md §4-2 の代替手段どおり、分岐そのものの
単体確認で代替した。

```bash
$ bash -c 'MODE=impl; ACCEPT_ON_COMPLETE=false; [ "$MODE" = "impl" ] || ACCEPT_ON_COMPLETE=true; echo $ACCEPT_ON_COMPLETE'
false
$ bash -c 'MODE=explore; ACCEPT_ON_COMPLETE=false; [ "$MODE" = "impl" ] || ACCEPT_ON_COMPLETE=true; echo $ACCEPT_ON_COMPLETE'
true
```

`MODE=impl` のときだけ `ACCEPT_ON_COMPLETE=false` に倒ることを確認した。期待どおり。

## 7. JSON の妥当性(design.md §4-3)

シナリオ1〜3 それぞれで次を実行し、いずれも成功した(詳細は上記の各シナリオ節に記載)。

```bash
jq -e . .harness/codex-runs/[id].json >/dev/null && echo "valid json"
jq -r '.accepted' .harness/codex-runs/[id].json
tail -3 .harness/codex-runs/[id].json
```

## 8. 後片付け(design.md §4-4)

シナリオ1〜3 で作成した record 一式(`.json` / `.log` / `.last.txt`)は削除済み。
`git status --short` で確認したところ、残る差分は次の 2 つのみ。

```
 M .claude/scripts/delegate-codex.sh
?? .steering/20260826-issue22-readonly-auto-accept/
```

他 8 箇所の `write_record` 呼び出し(`running` / `failed` x5 / `rate-limited` /
`unavailable` / `blocked`)は第 5 引数を渡していないことをコードで確認済み
(design.md §3 のとおり)。
