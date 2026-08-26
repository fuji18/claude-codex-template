<!-- status: ready -->

# 設計: tree_snapshot の未追跡ディレクトリ検出 (Issue #27)

## 1. 変更点(実装はこれだけ)

`.claude/scripts/delegate-codex.sh` 651 行目付近:

```bash
tree_snapshot() { git status --porcelain 2>/dev/null | LC_ALL=C sort; }
```

これを `--untracked-files=all` 付きに変える。**あわせて理由と既知の限界をコメントで残す**
(この 1 行が「なぜ `-uall` なのか」を知らない人に短縮されて元に戻るのを防ぐため)。

置換後の形(コメント含めそのまま採用してよい):

```bash
# --untracked-files=all は必須。既定の -unormal は新規の未追跡ディレクトリを
# `?? dir/` の 1 行に畳むため、そのディレクトリ配下に何ファイル作っても前後の
# スナップショットが一致し、成果のある委託を「成果物が確認できない」として
# failed / exit 2 に誤判定していた(Issue #27。実測は #20 の verification.md §3)。
# 走査量は増えるが .gitignore 済みディレクトリは辿らないため実測差は誤差
# (未追跡 5000 ファイルで約 +0.02 秒 / 呼び出し)。
#
# 既知の限界: これは status 行の比較であって内容の比較ではない。既にある未追跡
# ファイルへの「追記だけ」は前後とも同じ `?? path` 行になるため検出できない。
# 検出が必要になったら内容ハッシュ方式(forbidden_snapshot と同型)へ切り替える。
tree_snapshot() { git status --porcelain --untracked-files=all 2>/dev/null | LC_ALL=C sort; }
```

他の箇所は触らない。`forbidden_snapshot()` / `count_done()` / `HEAD` 比較・出口検査は無変更。

## 2. なぜ `-uall` を選ぶか(検討済み。実装者は再検討しない)

| 案 | 判断 |
| --- | --- |
| **`git status --porcelain -uall`** | **採用。** 1 行の変更で済み、既存の比較ロジックをそのまま使える。ignore 済みディレクトリは辿らないので走査量の増加が実質ゼロ |
| `git ls-files -o` + `git diff` の組み合わせ | 不採用。取得経路が増えるだけで得られる情報は `-uall` と同じ |
| 内容ハッシュ方式(`forbidden_snapshot` と同型) | 不採用。追記のみの検出まで拾えるが、作業ツリー全体のハッシュ計算になりコストが跳ねる。スコープ外(要求「既知の限界」参照) |

## 3. 走査量の実測(司令塔が計画時に実施済み。参考値)

このリポジトリ(WSL2 / `node_modules` 144MB は `.gitignore` 済み)で計測:

| 条件 | `-unormal` 3 回 | `-uall` 3 回 | 出力行数(normal → all) |
| --- | --- | --- | --- |
| クリーンなツリー | 1.330s | 1.353s | 0 → 0 |
| 未追跡 5000 ファイル(5 ディレクトリ) | 1.378s | 1.434s | 1 → 5000 |

1 呼び出しあたりの差は約 0.02 秒。`tree_snapshot` は 1 委託につき 2 回しか呼ばれないため
無視できる。`node_modules` が `.gitignore` にあるため `-uall` でも辿られないことを
`git check-ignore -v node_modules` で確認済み。

**実装者は §5 の手順でこの計測を再実行し、`verification.md` に自分の実測値を記録すること**
(受け入れ条件の 1 つ)。数値がここと大きく食い違う場合(1 呼び出し 1 秒超の増加など)は
停止して報告する。

## 4. 再現テスト(スタブ Codex。実 Codex は呼ばない)

Issue #20 の検証で使ったスタブを流用する。`PATH` の先頭にこのスタブを置き、
`delegate-codex.sh impl` を通す。

### 4-1. スタブの用意

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
[ -n "${FAKE_CODEX_WORK:-}" ] && printf 'fake work\n' >> "$FAKE_CODEX_WORK"
[ -n "$LASTPATH" ] && printf '完了: tasklist 1/1 / 変更 1 ファイル / lint・型・関連テスト pass\n' > "$LASTPATH"
exit "${FAKE_CODEX_EXIT:-0}"
STUBEOF
chmod +x "$STUB/codex"
export PATH="$STUB:$PATH"
```

### 4-2. テスト用ステアリング(入口検査5 を通すため)

`delegate-codex.sh impl` は対象ディレクトリに `design.md`(`<!-- status: ready -->` 付き)と
`tasklist.md` があることを要求する。

```bash
PROBE=".steering/99999999-issue27-probe"
mkdir -p "$PROBE"
printf '<!-- status: ready -->\n# probe\n' > "$PROBE/design.md"
printf -- '- [ ] probe task\n' > "$PROBE/tasklist.md"
```

**注意:** この `$PROBE` 自体が新規の未追跡ディレクトリなので、作成した時点で
`?? .steering/99999999-issue27-probe/` が 1 行出る。委託の**前**に作るため、
これは `TREE_BEFORE` にも入る。したがってシナリオ A の「配下に新規ファイルを作る」
対象は**この `$PROBE` 配下**にすればよい(それがまさに再現したい形)。

### 4-3. シナリオ A — 新規未追跡ディレクトリ配下にだけファイルを作る委託

```bash
FAKE_CODEX_WORK="$PROBE/scratch.txt" \
  .claude/scripts/delegate-codex.sh impl "$PROBE"
echo "exit=$?"
```

| | 期待 |
| --- | --- |
| 修正前 | `status=failed` / `exit 2`(「exit 0 だが成果物が確認できない」) |
| 修正後 | `status=completed` / `exit 0` |

**修正前の挙動も必ず実測して記録すること。** 手順: 先に現行コードのまま実行して
`exit 2` を確認 → 修正を入れる → 再実行して `exit 0` を確認。これが無いと
「そもそも再現していただけ」なのか「直った」のかが記録に残らない。

### 4-4. シナリオ B — 何も変更しない委託(退行チェック)

```bash
.claude/scripts/delegate-codex.sh impl "$PROBE"   # FAKE_CODEX_WORK なし
echo "exit=$?"
```

期待: 修正の前後どちらでも `status=failed` / `exit 2`。

`$PROBE` はシナリオ A で `scratch.txt` が増えているため、B は A の**前**に実行するか、
A の後に `rm -f "$PROBE/scratch.txt"` してから実行する。順序は
**B(何もしない → failed)→ A(作る → completed)** を推奨。

### 4-5. 後片付け(必ず行う)

```bash
rm -rf "$PROBE" "$STUB"
rm -f .harness/codex-runs/*probe*     # 該当しなければ手動で当該 run record を削除
git status --short                    # 意図した差分以外が残っていないこと
```

テストで生まれた run record(`.harness/codex-runs/<id>.json` / `.log`)は
`.gitignore` 済みでコミットには影響しないが、紛らわしいので削除する。
削除対象は実行時に stdout に出る `id=...` を控えて特定する。

## 5. 走査量の再計測手順

```bash
D=".tmp-issue27-stress"
mkdir -p "$D"/{a,b,c,d,e}
for s in a b c d e; do for i in $(seq 1 1000); do : > "$D/$s/f$i.txt"; done; done
time (for i in 1 2 3; do git status --porcelain >/dev/null; done)
time (for i in 1 2 3; do git status --porcelain -uall >/dev/null; done)
git status --porcelain | wc -l; git status --porcelain -uall | wc -l
rm -rf "$D"
```

## 6. 検証記録

`.steering/20260826-issue27-untracked-dir-detection/verification.md` を新規作成し、
以下を記録する:

1. `bash -n .claude/scripts/delegate-codex.sh` の結果
2. シナリオ B の結果(修正前 / 修正後)
3. シナリオ A の結果(**修正前 = exit 2** / **修正後 = exit 0**)
4. §5 の実測値(表形式)
5. 後片付け後の `git status --short`

## 7. ドキュメント更新

**不要。** `CLAUDE.md` / `AGENTS.md` / `docs/` には `tree_snapshot` の実装詳細への言及が
無いことを確認済み(`grep -rn tree_snapshot` の結果は `delegate-codex.sh` のみ)。
実装者は念のため `grep -rn 'tree_snapshot\|porcelain' --include='*.md' .` を実行し、
ヒットが無いことを `verification.md` に 1 行記録する。ヒットがあった場合は停止して報告する。
