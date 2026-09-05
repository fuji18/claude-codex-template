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
