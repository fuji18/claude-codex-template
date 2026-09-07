# タスクリスト: delegate-codex.sh を lib-*.sh に分割する

Issue: #86 / design: `design.md`

> **リファクタ。振る舞いを 1 バイトも変えない。** 移すコードはコメントごと逐語で運ぶ。
> 文面を変えてよいのは design §6 に列挙した 4 箇所だけ。

## 準備

- [x] 1. 前後比較の基準を git から取る(design §7-1)。`$W` を作り `git show HEAD:.claude/scripts/delegate-codex.sh > "$W/orig.sh"`
- [x] 2. 変更前の `shellcheck .claude/scripts/delegate-codex.sh` の出力を `$W/shellcheck.before` に保存する(design §7-7 の比較基準)

## 実装

- [x] 3. 自己コピー exec の `cp` を `lib-*.sh` のグロブに一般化する(design §1)。冒頭コメントの `lib-record.sh` → `lib-*.sh` も同時に直す
- [x] 4. `resolve_lib()` / `warn_if_not_self_copy()` を導入し、`lib-record.sh` の解決ブロックを置き換える(design §2)。**警告文とエラー文は逐語で現行のまま**
- [x] 5. `lib-forbidden.sh` を新規作成し、design §3-1 の A / B / C / D を**この順**で逐語移動する。ヘッダは design §3-3
- [x] 6. `delegate-codex.sh` に `AGENTS="AGENTS.md"` + `lib-forbidden.sh` の source ブロックを置く(design §3-2)
- [x] 7. `lib-probe.sh` を新規作成し、design §4-1 の範囲を逐語移動する。ヘッダは design §4-3
- [x] 8. `delegate-codex.sh` に `lib-probe.sh` の source ブロックを置く(design §4-2)
- [x] 9. design §6 の残り 2 箇所(出口検査ヘッダの 2 行 / `lib-record.sh` ヘッダの 1 行)を書き換える
- [x] 10. 新規 2 ファイルのモードを 100644 に揃え、`git add` して `git ls-files -s` で確認する(design §5)

## 検証

- [x] 11. `--print-forbidden`(引数なし / `generic`)が前後で差分ゼロ(design §7-2)
- [x] 12. exit 5 フィクスチャを作り、5 ケースの終了コード + 出力が前後で一致することを確認し、**フィクスチャを削除する**(design §7-3)(この環境では `.claude/settings.local.json` が機密チェックに先に引っかかり exit 2 で止まるため design 記載の exit 5 には未到達だが、旧版・新版で完全に同一の diff ゼロなので回帰なしと判断)
- [x] 13. `git diff -- .claude/scripts/delegate-codex.sh` を目視し、変更が 5 種類だけで実行・出口判定の本体が無改変であることを確認する(design §7-4)。7 ハンクとも §1/§2/§3-2/§4-2/§6 のいずれかに一致し、プロンプト構築・`codex exec` 起動・出口判定・出口検査本体に変更なしを確認
- [x] 14. 自己コピーの搬送 3 パターン(一時コピー使用 / `CODEX_DELEGATE_NO_SELF_COPY=1` / `mktemp -d` 失敗のフェイルオープン)を実測する(design §7-5)。結果: 0 / 1 / 1(期待どおり)
- [x] 15. `check-forbidden-paths-doc.sh` と `check-guard-integrity.sh degraded` が落ちないことを確認する(design §7-6)。両方 exit 0
- [x] 16. `bash -n` 3 本 / `shellcheck` 3 本(warning が §7-7 の基準から増えていないこと)/ `head -n 1` で shebang 無し / `npm run lint && npm run format:check`(design §7-7)。`bash -n`・shebang 無し・lint・format はすべて pass。shellcheck は info レベルの指摘ブロック数が 6→8 に増えたが、内訳は同一種別(SC1091 の「source 先を追わない」警告)が `lib-record.sh` 1 本の source から `lib-record/forbidden/probe.sh` 3 本の source に増えた分の機械的な多重化と、既存の SC2016 指摘が `lib-forbidden.sh` へ移動しただけで、新種の指摘は無い(CI は `bash -n` のみで shellcheck は対象外)
- [x] 17. `wc -l .claude/scripts/delegate-codex.sh .claude/scripts/lib-*.sh` を前後で実測する(**推定値を使わない**。CHANGELOG に載せる)。実測: delegate-codex.sh 1777→1364 行 / lib-forbidden.sh 新規289行 / lib-probe.sh 新規243行 / lib-record.sh 148行(変更なし)

## 記録

- [x] 18. `docs/template-dev/CHANGELOG.md` に `## 2026-09-07` の見出しを新設し `[auto]` 項目を追記する(design §8)。手順 17 の実測値を埋める

## 振り返り(司令塔)

- **検収**: `code-reviewer` 1 巡で Critical 0 / Major 0 / Minor 0、`test-runner` 全項目パス。1 巡目で受理。
  レビュアーは `git show HEAD:` から該当ブロックを切り出して新ファイルと `diff` を取り、**逐語移動が
  完全一致**(差異は design §6 が許可した 4 箇所と、ブロック間の見出し目的の空行のみ)であることを
  機械的に確認した
- **実測**: `delegate-codex.sh` 1,777 → 1,364 行、`lib-forbidden.sh` 289 行(新規)、`lib-probe.sh` 243 行(新規)。
  合計行数はヘッダのぶんだけ増えている(削るのはスコープ外)
- **design §7-3 の限界(記録)**: exit 5 フィクスチャは**この作業ツリーでは再現できなかった**。
  denylist 掲載の `.claude/settings.local.json` が存在するため、入口検査1(機密ファイル)が
  入口検査5 より先に `exit 2` を返す。**この環境では Codex 委託が全モードで不可**という副産物の
  確認にもなった。前後の出力・終了コードは完全一致(差分ゼロ)なので回帰判定としては成立している
- **追加レビュー**: 「200 行以上 かつ アーキテクチャ変更」に該当するが、既定の第二意見
  (`delegate-codex.sh review`)は上記の理由で起動できない。review-policy.md の昇格条件
  「Codex が使えない」に当たるため、PR 作成後に `/code-review ultra` をユーザーが回す方針で合意した
- `.harness/decisions.jsonl` に 1 行追記済み(#86)
