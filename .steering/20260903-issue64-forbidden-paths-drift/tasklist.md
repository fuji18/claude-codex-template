# タスクリスト

## 🚨 タスク完全完了の原則

**このファイルの全タスクが完了するまで作業を継続すること**

- 全てのタスクを `[x]` にすること
- 未完了タスク(`[ ]`)を残したまま作業を終了しない
- 技術的理由で不要になった場合のみ `- [x] ~~タスク名~~(理由)` でスキップを記録する

---

## フェーズ1: 検査スクリプトの追加

- [x] `.claude/scripts/check-forbidden-paths-doc.sh` を新規作成する
  - [x] `design.md`「コンポーネント設計 1」のコードブロックの内容をそのまま書く(コメントも含めて)
  - [x] `bash -n .claude/scripts/check-forbidden-paths-doc.sh` が通ることを確認する
  - [x] `chmod +x` した上で `git add` → `git update-index --chmod=+x .claude/scripts/check-forbidden-paths-doc.sh` を実行し、`git ls-files -s .claude/scripts/check-forbidden-paths-doc.sh` が `100755` であることを確認する

- [x] 現状のリポジトリで誤検知が無いことを確認する
  - [x] `bash .claude/scripts/check-forbidden-paths-doc.sh; echo "exit=$?"` の出力が 0 行・`exit=0` であること

## フェーズ2: CI への配線と受け入れ条件の再現確認

- [x] `.github/workflows/ci.yml` の `harness-integrity` ジョブに、`design.md`「コンポーネント設計 2」のステップを既存の "Validate harness integrity" ステップの直後へ追加する

- [x] 受け入れ条件を手元で再現確認する(**確認後は一時変更を必ず戻す**)
  - [x] `.claude/scripts/delegate-codex.sh` の `FORBIDDEN_PATHS` 配列に `"README.md"` を一時追加し、検査が `README.md` の 1 行を報告して `exit=1` になることを確認する
  - [x] その状態で `CLAUDE.md` の「### Codex への委託禁止領域(パス)」節にも `README.md` を一時追記し、出力が 0 行・`exit=0` に戻ることを確認する
  - [x] `git checkout -- .claude/scripts/delegate-codex.sh CLAUDE.md` で戻し、`git status --short` にこの 2 ファイルが現れないことを確認する
  - [x] 3 パターンの実行結果(出力行・終了コード)を最終報告に含める

- [x] 節が見つからない場合の分岐を確認する
  - [x] `CLAUDE.md` の見出しを一時的に改名して 1 行だけ報告されること(パス単位の警告が出ないこと)を確認し、戻す

## フェーズ2.5: 検収指摘の反映(司令塔の実測で発覚)

- [x] `.github/workflows/ci.yml` の追加ステップを `design.md`「コンポーネント設計 2」の**更新後**の内容に差し替える(`set +e` / `RC` / 異常終了の警告 1 行 / 末尾 `exit 0`)
  - 背景: Actions の既定シェル `bash -e` では、検査が**出力なしで非ゼロ終了**すると `while` ループの最後の `[ -n "$line" ]` が偽になり、**警告 1 行も出ないままジョブが赤くなる**
- [x] `bash -e` で 4 パターンを再現確認し、結果を最終報告に含める
  - [x] ずれあり(出力 2 行 / rc=1) → `::warning::` 2 行 + ステップ rc=0
  - [x] ずれなし(出力 0 行 / rc=0) → 出力なし + ステップ rc=0
  - [x] 出力なしで rc=127(スクリプト欠落を模す) → 「検査が働いていません」の警告 1 行 + ステップ rc=0
  - [x] 実物の `check-forbidden-paths-doc.sh` を呼ぶ形 → 出力なし + ステップ rc=0
  - 確認にはスクラッチパッドの一時ファイルを使い、リポジトリ内にテスト用ファイルを残さない

## フェーズ3: 品質チェックと修正

- [x] `.github/workflows/ci.yml` が YAML として妥当であることを確認する(インデント崩れの目視 + `harness-integrity` ジョブ内の既存ステップが壊れていないこと)
- [x] `/check`(test-runner に委譲)の全チェックがパスすることを確認
  - 検証コマンドは `docs/development-guidelines.md` の定義が正

## フェーズ4: ドキュメント更新

- [x] `docs/template-dev/CHANGELOG.md` に `- **[auto]** ...` で 1 行追記する(`design.md`「コンポーネント設計 3」)
- [x] 実装後の振り返り(このファイルの下部に記録)

---

## 実装後の振り返り

### 実装完了日
2026-09-03

### 計画と実績の差分

**計画と異なった点**:
- 節見出しリネームの再現確認(フェーズ2 最後の項目)は、design.md 通り「見出しの直後にテキストを付け足す」だけの改名だと `awk` の `index($0, h) == 1` が前方一致でヒットし続けてしまい、`exit=0` のまま「節あり」判定になった。改名後の見出しが元の見出し文字列を接頭辞として含まない形(`### Delegation Forbidden Paths (renamed)`)に変えて再検証し、期待どおり 1 行報告・`exit=1` を確認した。スクリプト自体は design.md のコード通りで変更していない(検証手順の解釈のみの差分)
- フェーズ2.5: design.md「コンポーネント設計 2」の更新後コードをそのまま `bash -e` で 4 パターン再現したところ、「ずれあり(出力 2 行)」パターンで 1 行目しか警告に出ないバグを検出した。原因は `printf '%s' "$DRIFT"`(末尾改行なし)を `while IFS= read -r line` にパイプすると、コマンド置換で末尾改行が失われた最終行が `read` の失敗行として読み捨てられるため。`printf '%s\n' "$DRIFT"` に直すと今度は空 `DRIFT`(ずれなしパターン)で `read` が空行を 1 回読み、ループ本体の `[ -n "$line" ] && echo ...` が偽を返して `set -e` 下でステップが `exit 0` に到達する前に打ち切られる(step rc=1)副作用が出た。`&&` 形を `if [ -n "$line" ]; then echo ...; fi` に変更し(`if` の非該当分岐は終了コード 0)、`printf '%s\n'` と組み合わせて 4 パターン全てが期待どおりになることを確認した。この 2 点(`printf '%s\n'` / `if` 文への変更)は design.md のコードブロックそのままではなく、tasklist フェーズ2.5 の受け入れ基準を満たすための実装レベルのバグ修正として実施した

**新たに必要になったタスク**:
- なし

### 学んだこと

- `awk` の `index($0, h) == 1` による見出し一致は前方一致なので、見出しの「改名」を検証するときは元の文字列を接頭辞に含まない見出しで試す必要がある
- `bash -e` 下で `while IFS= read -r line; do [ -n "$line" ] && echo ...; done` は、`$line` が空文字のときに `&&` の右辺が実行されず複合コマンドが非ゼロを返し、ループ内でスクリプト全体が早期終了する。空判定を挟む場合は `&&` ではなく `if ... ; then ... ; fi` を使う
- コマンド置換 `$(...)` は末尾の改行をすべて取り除くため、複数行の出力を再度 `printf` で `while read` に渡すときは `printf '%s\n'`(末尾改行を復元)にしないと最終行が欠落する

### 次回への改善提案
- 特になし
