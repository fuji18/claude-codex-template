# タスクリスト: #81 出口検査の誤爆を止める

設計は `design.md`。**設計判断が必要になったら停止して報告する**(自力で判断しない)。

## 実装

- [x] T1: `forbidden_files()` から `$RUN_DIR` を外す + 関数コメントを書き換える(design §2-1 (a))
- [x] T2: `record_state_snapshot()` を新設する(design §2-1 (b)。コメントを丸ごと入れる)
- [x] T3: BEFORE スナップショットに `RECSTATE_BEFORE` を足す(design §2-1 (c))
- [x] T4: 出口検査ブロックを足す(design §2-1 (d)。位置は禁止領域検査の直後・ライフサイクル警告の直前)
- [x] T5: 実態と食い違ったコメント 7 箇所を直す(design §2-1 (e) の表。**1 行も飛ばさない**)
- [x] T6: `codex-run.sh` に `require_no_running_impl()` を新設する(design §2-2 (a))
- [x] T7: `cmd_accept` / `cmd_set_status` / `cmd_prune` から呼ぶ(design §2-2 (b)。読み取り系には足さない)
- [x] T8: `codex-run.sh` のヘッダと `usage()` を更新する(design §2-2 (c))
- [x] T9: `delegation-policy.md` の並行数の箇条書きに 1 文足す(design §2-3)
- [x] T10: `codex-delegation-plan.md` の 2 箇所を直す(design §2-4)
- [x] T11: `docs/template-dev/CHANGELOG.md` に追記する(design §2-5)

## 検証(design §5 をそのまま回す)

- [x] T12: V1 `bash -n` × 2 と prettier
- [x] T13: V2 `--print-forbidden` の出力が不変 + `check-forbidden-paths-doc.sh`
- [x] T14: V3 `record_state_snapshot()` の jq 式(正常 record と欠損 record)
- [x] T15: V4 並行 explore 相当の BEFORE/AFTER で違反 0 件
- [x] T16: V5 3 ケース(accepted 書き換え / status 詐称 / record 削除)がすべて違反として拾われる
- [x] T17: V6 `codex-run.sh` の実行中ロック(拒否 → `CODEX_RUN_FORCE=1` で通る → 読み取り系は通る → **後始末**)
- [x] T18: V7 `check-guard-integrity.sh` が無出力・exit 0
- [x] T19: 結果を `verification.md` に記録する(実際に走らせたコマンドと出力を貼る)

## 検収の指摘反映(code-reviewer 1 巡目: Critical 0 / Major 0 / Minor 4)

司令塔の判断は下に書き切ってある。**新しい設計判断はしない。**

- [x] T20 (Minor): `codex-run.sh` の `cmd_prune` で **`--dry-run` は実行中ロックの対象外**にする。
      `require_no_running_impl` は現在 `require_jq` の直後(オプション解析より前)にあるため、
      **削除を伴わない `prune --dry-run` まで拒否している**。design §2-2 (b) は
      「読み取り系は止めない」としており、`--dry-run` は実質読み取り系。
      - `cmd_prune` からは `require_jq` 直後の `require_no_running_impl` を**外す**
      - オプション解析の `while` ループの**直後**に `[ "$_dry" -eq 1 ] || require_no_running_impl` を置く
      - **`cmd_accept` / `cmd_set_status` の呼び出し位置は変えない**(あちらは常に書き込む)
      - 理由を 2 行のコメントで書く(「`--dry-run` は何も書かないので止めない。位置がオプション
        解析より後なのはそのため」)

- [x] T21 (Minor): `record_state_snapshot()` の 1 行目トークンから **`.json` を落とす**。
      現状は `${_f##*/}`(例: `20260905-143200-48213.json`)をそのまま識別子にしており、
      違反メッセージがそれを表示する。**メッセージは同じ画面で
      `codex-run.sh show <id>` を案内しているが、`find_record()` は `$RUN_DIR/$_id.json` を
      組み立てるため、表示された文字列をそのまま貼ると `...json.json` を探して必ず外す。**
      入口検査5-5 の `id=$_rid` 表示とも形が揃う。
      - `local` に `_base` を足し、`_base="${_f##*/}"` → `_base="${_base%.json}"` としてから
        `printf '%s %s\n' "$_base" "$_line"` にする
      - BEFORE / AFTER は同じ関数を通るので突き合わせは壊れない。**比較規則は変えない**

- [x] T22 (Minor): `.claude/rules/lead/delegation-policy.md` の追記文の**末尾に句点**を足す
      (`...拒否される` → `...拒否される。`)

- [x] T23 (Minor / 明文化のみ・コード変更なし): `RECSTATE_BEFORE` を取ってから自身の
      `write_record "running"` が走るまでの間は、`codex-run.sh` の実行中ロックがまだ
      効かない(自分の record がまだ存在しないため)。この窓に人間の `accept` が入ると
      出口検査が鳴る。**実害は小さいので塞がない**(窓の中ではまだ委託先が起動しておらず、
      敵対的な書き換えの経路にはならない)。
      `RECSTATE_BEFORE` の代入行の直前に、この既知の限界を 2〜3 行のコメントで残す。
      **`.harness/` のような親ディレクトリが固有パスに書かれた場合の限界**は
      `forbidden_files()` のコメントに既出なので、追記しない

## 再検証

- [x] T24: `bash -n` × 2 と `npx prettier --check`(変更した md を含む)
- [x] T25: T20 の確認 — 実行中 impl record を偽装した状態で
      `codex-run.sh prune --dry-run` が **通る**こと、`prune`(フラグなし)と
      `accept` / `set-status` が **拒否される**こと。**偽装 record は必ず後始末する**
- [x] T26: T21 の確認 — 違反メッセージに出る識別子が `.json` なしになり、その文字列を
      `codex-run.sh show <id>` にそのまま渡して record が引けること
- [x] T27: design §5 の V5(accepted 書き換え / status 詐称 / record 削除)を回し直し、
      3 ケースとも違反として拾われること(T21 で識別子の形を変えたため)
- [x] T28: `check-guard-integrity.sh` が無出力・exit 0
- [x] T29: 結果を `verification.md` に追記する
