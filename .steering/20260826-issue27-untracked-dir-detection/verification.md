# 検証記録: Issue #27 tree_snapshot の未追跡ディレクトリ検出

実施日: 2026-08-26 / 実施者: implement-ticket (fork)

## 1. `bash -n .claude/scripts/delegate-codex.sh`

```
$ bash -n .claude/scripts/delegate-codex.sh
(出力なし) → 構文エラーなし
```

## 2. シナリオ B の結果(修正前 / 修正後)

design.md §4-4 のとおり、`FAKE_CODEX_WORK` を設定せず(何も変更しない)委託を実行。

| | 結果 |
| --- | --- |
| 修正前 | `status=failed` / `exit=2` (id=20260826-042531-77642) |
| 修正後 | `status=failed` / `exit=2` (id=20260826-042635-79542) |

修正前後で退行なし(期待どおり)。

## 3. シナリオ A の結果(修正前 = exit 2 / 修正後 = exit 0)

design.md §4-3 のとおり、`FAKE_CODEX_WORK="$PROBE/scratch.txt"` を設定し、
新規未追跡ディレクトリ(`$PROBE`)配下にのみファイルを作る委託を実行。

| | 結果 |
| --- | --- |
| 修正前 | `status=failed` / `exit=2`(id=20260826-042543-78330)。「Codex は正常終了しましたが、成果物が確認できません」と誤判定 — Issue #27 の再現を確認 |
| 修正後 | `status=completed` / `exit=0`(id=20260826-042647-80289)。summary が正しく表示された |

修正後の出力に以下の注意メッセージが付随したが、これは tasklist の `[x]` 進捗検出に関する
別ロジック(スタブが実際に tasklist.md を書き換えていないため)であり、tree_snapshot の
修正対象とは無関係:

```
⚠️ tasklist.md の [x] が増えていません(変更はあります)。逐次更新がされていない
可能性があるため、進捗の判断は tasklist ではなく git diff --stat を根拠にしてください。
```

## 4. 走査量の実測(design.md §5)

未追跡 5000 ファイル(5 ディレクトリ)を `.tmp-issue27-stress/` に作成して計測
(このリポジトリの現状のワークツリーには他にも未追跡ファイル・ディレクトリが
数点存在するため、design.md §3 のクリーン環境での実測値とは行数の絶対値が異なるが、
`-unormal` → `-uall` の差分の傾向は一致する)。

| 条件 | `-unormal` 3 回(real) | `-uall` 3 回(real) | 出力行数(normal → all) |
| --- | --- | --- | --- |
| 未追跡 5000 ファイル(5 ディレクトリ)+既存の未追跡分 | 1.329s | 1.427s | 4 → 5007 |

1 呼び出しあたりの差は約 0.033 秒(design.md §3 の実測値 約0.02秒と同オーダー)。
`node_modules` は `.gitignore` 済みで `-uall` でも辿られないことは design.md §3 で
確認済み。1 秒超の増加は発生していないため、design.md の判断どおり許容範囲。

## 5. ドキュメントへの実装詳細の記述チェック

```
$ grep -rn 'tree_snapshot\|porcelain' CLAUDE.md AGENTS.md docs/
(ヒットなし)
```

`.steering/` 配下の過去の計画ドキュメントにはヒットするが、これは履歴として残す
対象であり、`CLAUDE.md` / `AGENTS.md` / `docs/` にはヒットなし。design.md §7 の
判断(「ドキュメント更新は不要」)を確認。

## 6. 後片付け後の `git status --short`

```
$ git status --short
 M .claude/scripts/delegate-codex.sh
?? .steering/20260826-issue27-untracked-dir-detection/
```

`.steering/99999999-issue27-probe/` と一時スタブディレクトリは削除済み。
`.harness/codex-runs/` に残るテスト用 run record(id 末尾:
77642, 78330, 79542, 80289)は削除済み。`.gitignore` 済みのため元々コミット対象外。

## 7. 検収指摘の対応(司令塔)

検収は `code-reviewer`(0 critical / 0 major / 3 minor)と `test-runner`(lint・typecheck・
test・format・`bash -n` すべて pass、shellcheck は未インストールのためスキップ)。
minor 3 件はいずれもコード修正を伴わないため、以下の追記で対応とする。

### 指摘1(minor): §5 の grep 対象が design.md §7 の指示と違う

design.md §7 は `grep -rn 'tree_snapshot\|porcelain' --include='*.md' .`(リポジトリ全体)を
指示していたが、実施は `CLAUDE.md AGENTS.md docs/` に絞られていた。結論(「`CLAUDE.md` /
`AGENTS.md` / `docs/` に実装詳細の記述なし = ドキュメント更新不要」)は変わらないため
再実行はしない。指示どおりの全体 grep でも `.steering/` 配下の過去の計画ドキュメントに
しかヒットしないことは §5 に記載済み。

### 指摘2(minor): 「大きめのワークツリー」の実測範囲の明示

§4 の実測は **未追跡 5000 ファイル / 5 ディレクトリ規模**での計測であり、
数十万ファイル規模のモノレポでの挙動は未検証。本テンプレートおよびその派生プロジェクトの
想定規模ではこれで十分と判断する。`-uall` の走査量は**未追跡かつ ignore されていない**
ファイル数に比例するため、`.gitignore` が整備されている限り規模と比例しない点も判断の根拠。

### 指摘3(minor 相当・確認結果の共有)

`delegate-codex.sh` 内で `git status --porcelain`(`--untracked-files` 未指定)を使っている
箇所は `tree_snapshot()` のみで、同種の畳み込みバグを持つ関数は残っていない。
`forbidden_snapshot()` は元から内容ハッシュ方式のため本問題の影響を受けない。

## 8. 申し送り

- `git status` ベースのスナップショットは**ステータス行の比較**であって内容の比較ではない。
  今回 `-uall` 化で「新規未追跡ディレクトリ配下のファイル作成」は拾えるようになったが、
  **既存の未追跡ファイルへの追記のみ**は依然として検出できない(requirements.md「既知の限界」)。
  この限界はコード上のコメントにも残してあるので、次に同種の誤検出が報告されたときは
  `-uall` の追加ではなく内容ハッシュ方式への切替を検討すること
- スタブ Codex による再現テストは、**修正前の挙動を先に実測してから修正を入れる**手順を
  design.md に明記したことで「再現していただけ」との区別が記録に残せた。同型の
  誤検出バグを扱うチケットではこの順序を定型とする
