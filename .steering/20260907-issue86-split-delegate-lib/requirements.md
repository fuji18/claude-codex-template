# 要件: delegate-codex.sh を lib-*.sh に分割する

Issue: #86(P2 / `delegate:codex` なし = `.claude/scripts/` は委託禁止領域)

## 背景

`delegate-codex.sh` は 1,777 行に入口検査 7 系統・禁止領域の定義と抽出・プローブの許可リストと形式検査・プロンプト構築・環境許可リスト・run record・出口検査 2 系統・出口判定が同居している。2026-09-04 のレビューで「どの層がどこを守っているか」を追うのに全文読解が要った(D2)。監査コストが構造的に高く、層が増えるほど悪化する。

分割を阻んでいたのは自己コピー exec の `cp` がファイル名でハードコードされていたこと。`lib-*.sh` は既に CI(非実行 + shebang 無し)と SessionStart hook が機械検査する規約を持つ(#45)ため、グロブ化すれば新しい約束事は要らない。

## やること

1. 自己コピー exec の共有ファイル搬送を `lib-*.sh` のグロブに一般化する(フェイルオープンの方針は変えない)
2. `lib-forbidden.sh` を切り出す — `FORBIDDEN_PATHS` / `PROJECT_FORBIDDEN_PATHS` の抽出 / `forbidden_files()` / `forbidden_snapshot()` / `lifecycle_snapshot()`
3. `lib-probe.sh` を切り出す — `PROBE_ALLOWED_CMDS` / `PROBE_VERIFY_TOKENS` / `_probe_name_ok()` / `probe_format_reason()` / `PROBE_ENV`
4. 3 ファイルに増えた解決順を 1 つのヘルパーに集約する(`lib-record.sh` で確立した「自身の隣 → リポジトリ」の形をそのまま適用する)
5. `--print-forbidden` の短絡経路が壊れていないことを実測で確認する(#65)

**振る舞いは変えない。** 検査の追加・削除・条件変更・順序変更はすべてスコープ外。

## やらないこと

- コメントの削減(この層の保守はコメントで成立している)
- `record_state_snapshot()` の移動(Issue の切り出し一覧に無い。禁止領域ではなく run record の検収状態を見る層なので、`lib-forbidden.sh` とは責務が違う)
- `codex-run.sh` / `check-guard-integrity.sh` の分割
- 入口検査の順序変更

## 受け入れ条件(Issue より)

- [ ] `delegate-codex.sh` の全終了コードが分割の前後で一致する
- [ ] `--print-forbidden` の出力が分割の前後で一致する(`generic` 付きも)
- [ ] 自己コピー exec が `lib-forbidden.sh` / `lib-probe.sh` も一時ディレクトリへ運んでいる
- [ ] コピーに失敗した場合もフェイルオープンで動き、警告が出る
- [ ] `CODEX_DELEGATE_NO_SELF_COPY=1` の経路が従来どおり動く
- [ ] CI の `harness-integrity` が緑(`lib-*.sh` の非実行 + shebang 無し)
- [ ] `check-guard-integrity.sh degraded` と `check-forbidden-paths-doc.sh` が従来どおり動く
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## 調査で確定した事実(design の前提)

| 事実 | 根拠 |
| --- | --- |
| `AGENTS` の初出代入は 305 行、初回参照は 331 行 | `grep -n 'AGENTS' delegate-codex.sh` |
| `FORBIDDEN_PATHS` は 353 / 996(入口検査5-5b)/ 1232 で参照される | 同上 |
| `forbidden_snapshot()` の呼び出しは 1410 / 1573、`lifecycle_snapshot()` は 1416 / 1673 | 同上 |
| `forbidden_files()` は `$RUN_DIR` / `$REC` / `$LOG` / `$LAST` を**呼び出し時**に読む(定義位置を前に動かしても成立する) | 1226-1257 |
| `--print-forbidden` は既に `lib-record.sh` のフェイルクローズを通過してから到達する | 114-145 が 147 の引数解釈より前 |
| 外部から参照されるのは `--print-forbidden` の出力だけ。関数・配列を直接 source する利用者はいない | `check-guard-integrity.sh:378` / `check-forbidden-paths-doc.sh:40` |
| CI に shellcheck は無く `bash -n` のみ。ローカルには shellcheck がある | `.github/workflows/ci.yml:110` / `command -v shellcheck` |
| `npm run format:check`(prettier)は `.claude/` を除外している | `.prettierignore` |
