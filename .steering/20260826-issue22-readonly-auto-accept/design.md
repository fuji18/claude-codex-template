<!-- status: ready -->

# 設計: explore / review の run record を auto-accept する(Issue #22)

対象ファイルは **`.claude/scripts/delegate-codex.sh` の 1 ファイルのみ**。
`codex-run.sh` は変更しない。

## 0. 前提(読む順に確認すること)

- `write_record()` は `.claude/scripts/delegate-codex.sh` の 468 行目付近。
  `cat >"$REC" <<JSON` のヒアドキュメントで record 全体を毎回書き直す
- 呼び出しは全部で 9 箇所(`running` 1 / `failed` 4 / `rate-limited` 1 /
  `unavailable` 1 / `blocked` 1 / `completed` 1)。`grep -n 'write_record ' で列挙できる
- `accepted` は **JSON の最終フィールド**。`codex-run.sh` の `cmd_accept` が
  `write_field "$_f" accepted true ""`(第 4 引数 = 末尾カンマ無し)で更新するため、
  **フィールドの並び順を変えてはならない**

## 1. `write_record` に第 5 引数を足す

現在のシグネチャ(コメント行含む):

```bash
# $1=status $2=summary $3=error $4=resetAt
write_record() {
```

これを次のようにする。

```bash
# $1=status $2=summary $3=error $4=resetAt $5=accepted(true/false。既定 false)
write_record() {
  # JSON にそのまま埋めるため true/false のリテラルに正規化する。
  # 呼び出し側の綴り間違いや空文字で record が壊れた JSON になるのを防ぐ。
  local _accepted
  case "${5:-false}" in
    true) _accepted=true ;;
    *) _accepted=false ;;
  esac
  cat >"$REC" <<JSON
...(既存のまま)...
  "accepted": $_accepted
}
JSON
}
```

変更点は次の 3 つだけ:

1. 直前のコメント行に `$5=accepted(true/false。既定 false)` を足す
2. 関数の先頭に上記 `case` を置き、`_accepted` を `local` で宣言する
3. ヒアドキュメント内の `"accepted": false` を `"accepted": $_accepted` にする
   (**行の位置・インデント・末尾にカンマを付けないことは現状のまま**)

`_accepted` を `local` にする理由: `write_record` は 9 箇所から繰り返し呼ばれる。
グローバルに漏らすと前回の値が次回に残る形になり、既定値の意味が壊れる。

## 2. `completed` の呼び出しだけモードで出し分ける

ファイル末尾(841 行目付近)の

```bash
write_record "completed" "$SUMMARY" "" ""
emit "completed" 0
```

を次のようにする。

```bash
# read-only の委託(explore / review)は検収対象の成果物を残さない。
# サマリーは下の標準出力で司令塔に渡り切っており、あとから accept する対象が無い。
# accepted: false のまま残すと codex-run.sh pending が SessionStart のたびに
# 注入し続け、コンテキストを削るための委託がコンテキストを太らせる(Issue #22)。
ACCEPT_ON_COMPLETE=false
[ "$MODE" = "impl" ] || ACCEPT_ON_COMPLETE=true

write_record "completed" "$SUMMARY" "" "" "$ACCEPT_ON_COMPLETE"
emit "completed" 0
```

**`[ "$MODE" = "impl" ] || ...` の向き**(`!= explore/review` の列挙ではなく impl の否定)
にする理由: モードが将来増えたとき、既定を「検収が要る = false」に倒しておく方が安全側に
落ちる。新モードを足した人が明示的に auto-accept を選ぶ形になる。

## 3. 他の呼び出しは一切触らない

`running` / `failed` / `rate-limited` / `unavailable` / `blocked` の 8 箇所は
**第 5 引数を渡さない**。既定の `false` が効き、異常終了は従来どおり pending に出る
(受け入れ条件の 4 番目)。impl の `blocked`(判断待ち)も false のままでよい —
判断待ちは司令塔が design.md を追記して再委託する対象であり、未処理として見えるべき。

## 4. 検証手順(実装者が実行して verification.md に記録する)

### 4-1. 構文チェック

```bash
bash -n .claude/scripts/delegate-codex.sh
```

### 4-2. スタブ Codex による実機確認

`.steering/20260825-issue20-codex-exit-check/verification.md` と同じ要領で、
`PATH` の先頭にスタブを置いて実 Codex を呼ばずに通す。スタブは
**スクラッチディレクトリに置き、リポジトリにはコミットしない**。

```bash
STUB="$(mktemp -d)"
cat > "$STUB/codex" <<'STUBEOF'
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
STUBEOF
chmod +x "$STUB/codex"
PATH="$STUB:$PATH" .claude/scripts/delegate-codex.sh explore "テスト用の調査指示"
```

explore / review は事前スナップショットも成果実在確認も通らない(`if [ "$MODE" = "impl" ]`
で囲まれている)ため、impl のときのような未追跡ディレクトリの罠(#20 の verification.md
§3)は踏まない。

確認するシナリオは 4 つ:

| # | 実行 | 期待 |
| --- | --- | --- |
| 1 | `explore` を上のスタブで正常終了 | record の `"accepted": true` / `codex-run.sh pending` に出ない / `list --all` には出る |
| 2 | `review HEAD` を上のスタブで正常終了 | 同上 |
| 3 | スタブを `exit 1` に変えて `explore` | record が `status: failed` かつ `"accepted": false` / `pending` に出る |
| 4 | 既存の impl レコード(または `codex-run.sh show`)を確認 | impl の completed は `"accepted": false` のまま |

シナリオ 4 は impl の実行が難しければ、`write_record` の分岐が `MODE=impl` で
`ACCEPT_ON_COMPLETE=false` になることをコードで確認したうえで、
`bash -c 'MODE=impl; ACCEPT_ON_COMPLETE=false; [ "$MODE" = "impl" ] || ACCEPT_ON_COMPLETE=true; echo $ACCEPT_ON_COMPLETE'`
のような**分岐そのものの単体確認**で代替してよい(その旨を verification.md に明記する)。

### 4-3. JSON の妥当性

生成された record に対して:

```bash
jq -e . .harness/codex-runs/[id].json >/dev/null && echo "valid json"
jq -r '.accepted' .harness/codex-runs/[id].json
tail -3 .harness/codex-runs/[id].json   # accepted が最終フィールド・カンマ無しであること
```

### 4-4. 後片付け

検証で作った record は `.harness/codex-runs/` に残る(`.gitignore` 済みなのでコミット
されない)。シナリオ 1〜3 で作った record ファイルは**削除してよい**。削除するなら
`rm .harness/codex-runs/[id].json .harness/codex-runs/[id].log` のように**その run の
ファイルだけ**を消す(ディレクトリごと消さない)。

## 5. ドキュメントの追随

`docs/template-dev/codex-delegation-plan.md` の 256 行目
(`accepted` は検収の通過を表し…)に、read-only モードの例外を **1 文だけ**足す。

> read-only の委託(explore / review)は検収対象の成果物を残さないため、`completed` の
> 時点で `accepted: true` を書く(Issue #22)。

**それ以外の記述・ファイルは変更しない。** `CLAUDE.md` / `AGENTS.md` / `.claude/rules/`
はこの record 意味論に触れていないため追随不要。
