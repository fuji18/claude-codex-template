# 検証記録: Codex 委託の出口検査(design.md §4・§5)

## 1. 構文チェック

```bash
bash -n .claude/scripts/delegate-codex.sh
```

結果: エラーなし(exit 0)。

## 2. スタブスクリプト(design.md §5-0 と同一)

```bash
#!/bin/bash
# delegate-codex.sh の出口検査を試すためのスタブ(テスト専用)
[ "${1:-}" = "login" ] && exit 0
LASTPATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output-last-message) LASTPATH="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "${FAKE_CODEX_TOUCH:-}" ] && printf '\n<!-- tampered by fake codex -->\n' >> "$FAKE_CODEX_TOUCH"
[ -n "${FAKE_CODEX_WORK:-}" ] && printf 'fake work\n' >> "$FAKE_CODEX_WORK"
[ -n "$LASTPATH" ] && printf '完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass\n' > "$LASTPATH"
exit 0
```

`PATH` の先頭にこのスタブを置き、実 Codex を呼ばずに `delegate-codex.sh impl` を通した。

## 3. design.md との相違点(実装者が発見・補正したもの)

design.md §5-0 は「`FAKE_CODEX_WORK` に `$S/scratch.txt`(新規の未追跡ファイル)を渡せば
成果実在確認(作業ツリーの変化)を通せる」としているが、**この前提は実機で成立しなかった**。

- `git status --porcelain` は新規の未追跡ディレクトリを 1 行(`?? .steering/xxx/`)に畳んで
  表示するため、そのディレクトリ配下の未追跡ファイルへの追記は `tree_snapshot`(=
  `git status --porcelain | sort`)の出力を一切変えない。前後のスナップショットが常に一致し、
  既存の「成果実在確認」(`delegate-codex.sh` の元々のロジック、この出口検査より後段)が
  「exit 0 だが成果物が確認できない」として exit 2 を返してしまう
- これは今回追加した出口検査(`FORBIDDEN_PATHS` 周り)の不具合ではない。実際、シナリオ1
  (禁止領域改ざん)は出口検査が成果実在確認より**先に**評価されるため、この問題の影響を
  受けずに正しく `failed` / `exit 2` になった(design.md §0.3 の並び順の意図どおり)
- シナリオ2・3(禁止領域に触れないケース)を正しく検証するため、`scratch*.txt` を
  作成直後に `git add` してから追記する形に変更した。`git add` 済みのファイルは
  `git status --porcelain` で個別に `AM` として現れるため、追記が正しく検出される
- 併せて、シナリオごとに**別名の scratch ファイル**(`scratch1a.txt` 等)を使うようにした。
  同じファイルを使い回すと 2 回目以降の追記が `AM` という同じステータス行に畳まれ、
  「前回の呼び出しで既に AM だった」ため今回の差分として検出できなかった(実測)
- これは検証手順(テストの book-keeping)の補正であり、`delegate-codex.sh` 本体・
  `CLAUDE.md` / `AGENTS.md` の記述には影響しない

再現時の追加コマンド(design.md §5-0 の後に足す):

```bash
git add "$scratch"   # scratch ファイルを作成した直後に実行する
```

シナリオごとに使う scratch ファイル名を変える(例: `scratch1a.txt` / `scratch1b.txt` / …)。

### 補足: 事前に汚れていた `AGENTS.md` を `git checkout` で戻さないこと

design.md §5-1/§5-3 は改ざんの巻き戻しに `git checkout -- <path>` を使う想定だが、
今回のように **同じファイルに未コミットの設計変更がすでに乗っている**状態でこれを実行すると、
`HEAD` まで戻ってその設計変更ごと消える(実機で発生し、`AGENTS.md` の 2-B〜2-D を
1 度やり直した)。作業対象ファイルに未コミットの変更がある間は、`git checkout` ではなく
`cp` によるバックアップ/リストアで戻すこと。

## 4. シナリオ1 — 禁止領域を書き換えた委託は failed / exit 2

3 パスとも同一の結果パターン。

| 改ざん対象 | exit | status | error(run record) |
| --- | --- | --- | --- |
| `AGENTS.md` | 2 | failed | `委託禁止領域が変更されました: AGENTS.md` |
| `.husky/pre-commit` | 2 | failed | `委託禁止領域が変更されました: .husky/pre-commit` |
| `.github/workflows/ci.yml` | 2 | failed | `委託禁止領域が変更されました: .github/workflows/ci.yml` |

stderr(共通、パス部分のみ差し替え):

```
delegate-codex: 委託禁止領域のファイルが変更されました(出口検査)。

これらはサンドボックスの外で実行される層(AGENTS.md の verify-probe / .husky/* /
.github/workflows/* / run record)です。委託の成果をそのまま採用しないでください。

  git diff -- <該当パス>

で内容を確認し、意図しない変更は破棄してから検収してください。

該当:
  AGENTS.md
```

run record 例(`AGENTS.md` 改ざん時):

```json
{
  "status": "failed",
  "summary": "⚠️ 委託禁止領域が変更されました(出口検査): AGENTS.md\n\n完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass",
  "error": "委託禁止領域が変更されました: AGENTS.md"
}
```

期待どおり。判定行が「完了」であっても出口検査が先に評価され `failed` に上書きされることを確認した(design.md §0.3 の意図)。

## 5. シナリオ2 — 禁止領域に触れない委託は completed / exit 0

```
[codex:impl] status=completed id=... exit=0
--- summary ---
完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass

⚠️ tasklist.md の [x] が増えていません(変更はあります)。逐次更新がされていない
可能性があるため、進捗の判断は tasklist ではなく git diff --stat を根拠にしてください。
```

`exit=0` / `status=completed`。誤検出なし。（末尾の警告はスタブが tasklist.md を実際には
更新しないための既存仕様の警告で、出口検査とは無関係)

## 6. シナリオ3 — 委託前から dirty な禁止領域ファイルを誤検出しない

`AGENTS.md` に事前ローカル編集を加えた状態(委託前後で内容が変わらない)で実行。

```
[codex:impl] status=completed id=... exit=0
```

`exit=0` / `status=completed`。事前の dirty 分は前後のハッシュが一致するため誤検出しない
ことを確認した(design.md §0.2 の意図どおり)。

## 7. 後片付け

- 改ざんした 3 ファイル(`AGENTS.md` / `.husky/pre-commit` / `.github/workflows/ci.yml`)は
  それぞれテスト直後に元の内容へ復元した(`AGENTS.md` は設計変更込みのバックアップへ復元、
  他の 2 つは元のコミット内容と一致することを `diff` で確認済み)
- テスト用ステアリング `.steering/99999999-exit-check-probe/` と scratch ファイルは
  `git reset` でステージを解除したうえで `rm -rf`
- テスト用の run record(`.harness/codex-runs/2026...`)は削除済み(`.gitignore` 済みで
  コミットには影響しないが、紛らわしいため)
- 最終 `git status --short`:

```
 M .claude/scripts/delegate-codex.sh
 M AGENTS.md
 M CLAUDE.md
?? .steering/20260825-issue20-codex-exit-check/
```

意図した 3 ファイルの変更と、本チケットのステアリングディレクトリ以外に差分は無い。

## 8. 検収指摘の対応

初版の検収で P0 1 件・P2 2 件・語の誤り 1 件が指摘され、以下のとおり修正した。

### 修正1(P0): 出口検査が `CODEX_EXIT` != 0 の経路を素通ししていた

初版は出口検査ブロックを `if [ "$MODE" = "impl" ]; then`(出口判定側、`VERDICT=` の手前)
の先頭に置いていたが、その手前(703 行目付近・722 行目付近)に `CODEX_EXIT -ne 0` の
無条件 `exit` が 2 箇所あり、レート上限・認証失敗・異常終了の経路では出口検査が
一度も評価されなかった。禁止領域を改ざんした直後にレート上限へ達したセッションは
`rate-limited` として記録されるだけで、改ざんが検出されない状態だった。

出口検査ブロックを `[ -f "$LAST" ] && SUMMARY=...` の直後・
`if [ "$CODEX_EXIT" -ne 0 ]; then`(1 つ目、レート上限判定)の直前へ移動し、
`if [ "$MODE" = "impl" ]; then` で自前にガードする形に変更した。あわせて、
`CODEX_EXIT` が非ゼロのときは `error` に `(codex exit=$CODEX_EXIT / $ERR3)` を
追記するようにした(上限・認証失敗と区別できるように)。

design.md §0.3 もこの配置に合わせて差し替えた。

### 修正2(P2): `forbidden_files` の戻り値

`| grep -Fxv -e "$REC" -e "$LOG" -e "$LAST"` は除外後に 1 行も残らないと exit 1 を
返し、`pipefail` の下では関数全体が非ゼロになる。`set -e` が無いため現状は実害がないが、
将来の地雷として `|| true` を付け、その理由をコメントで残した。

### 修正3(P2): 空振り条件の追記

`forbidden_snapshot()` 直前の「空振り条件」コメントに、割り込み(SIGINT/SIGTERM)で
`codex exec` の途中に死んだ場合に検査が働かない点と、`.harness/codex-runs/` が
ローテーションされないことによるハッシュ計算コストの線形増加の 2 点を追記した。

### 修正4: `AGENTS.md` の語の誤り

「委託の終了時に**上記パス**の内容ハッシュが照合され」の「上記パス」が、リストが
文の**下**にあるのに合っていなかった。「以下のパス」に修正した。

### シナリオ4(新規) — 禁止領域を改ざんしたうえで非ゼロ終了する委託

スタブ末尾を `exit "${FAKE_CODEX_EXIT:-0}"` に変更し、
`FAKE_CODEX_EXIT=1 FAKE_CODEX_TOUCH="AGENTS.md"` で実行した。

```
[codex:impl] status=failed id=20260825-235000-6941 exit=2
delegate-codex: 委託禁止領域のファイルが変更されました(出口検査)。
...
該当:
  AGENTS.md
exit=2
```

run record(`.harness/codex-runs/20260825-235000-6941.json`):

```json
{
  "status": "failed",
  "summary": "⚠️ 委託禁止領域が変更されました(出口検査): AGENTS.md\n\n完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass",
  "error": "委託禁止領域が変更されました: AGENTS.md (codex exit=1 / )"
}
```

期待どおり `status=failed` / `exit=2` で、`error` に `AGENTS.md` と `codex exit=1` の
両方が記録された(`ERR3` はスタブがログへエラーらしい文言を書かないため空だが、
`codex exit=1` は明示されている)。修正前(初版のコード配置)であれば `CODEX_EXIT -ne 0`
の分岐が出口検査より先に評価され、`rate-limited` あるいは無印の `failed`(`error` に
`AGENTS.md` を含まない)として静かに記録されていたはずの経路である。

### シナリオ2・3 の再実行(誤検出が増えていないことの確認)

| シナリオ | 結果 |
| --- | --- |
| シナリオ2(禁止領域に触れない) | `status=completed` / `exit=0` |
| シナリオ3(委託前から dirty な `AGENTS.md`) | `status=completed` / `exit=0` |

いずれも修正前と同じ結果で、退行なし。

### 検証時の注意点(前回検収の指摘どおり)

`AGENTS.md` には本チケットの未コミットの設計変更が乗っているため、改ざん後の巻き戻しは
`git checkout -- AGENTS.md` を使わず、`cp` によるバックアップ/リストアで行った
(`git checkout` を使うと `HEAD` の内容まで戻り、未コミットの設計変更ごと消える)。

最終確認(`git status --short`):

```
 M .claude/scripts/delegate-codex.sh
 M AGENTS.md
 M CLAUDE.md
?? .steering/20260825-issue20-codex-exit-check/
```

テスト用の run record・probe 用ステアリング・scratch ファイルはすべて削除済み。
