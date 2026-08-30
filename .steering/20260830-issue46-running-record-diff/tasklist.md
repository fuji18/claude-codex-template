# タスクリスト: Issue #46

## 実装

- [x] `delegate-codex.sh` の 5-5 ループに `_stale_ids` の初期化と収集を足す(design §2-1)
- [x] `delegate-codex.sh` に検査ブロック 5-5b を挿入する(design §2-2 の全文。コメント込み)
- [x] `bash -n .claude/scripts/delegate-codex.sh` を通す(`shellcheck` があれば併せて通す)(結果: bash -n OK。shellcheck は環境に未インストールのためスキップ)

## ドキュメント

- [x] `docs/template-dev/codex-delegation-plan.md` §12.7 の 5-5 段落に、止める条件・誤爆条件・空振り条件を追記する(design §3)
- [x] `docs/template-dev/CHANGELOG.md` の既存 `## 2026-08-30` 見出しに追記する(design §4。新しい日付見出しを作らない)

## 実測(design §5)

- [x] 変更をコミットする(clean ケースの実測に必要)(実装フェーズはコミットしない方針のため、実測は本ブランチにコミットせず `git worktree add --detach` の使い捨てワークツリーへ変更 3 ファイルをコピーし、そこだけでコミットして実施。本ブランチは作業ツリーのまま未コミット)
- [x] 5-1: 残置 record あり + 禁止領域 clean → 警告のみで先へ進むことを確認し、結果を 1 行で記録する(結果: 「status=running のまま残っています」警告のみ出力され、5-5b の停止メッセージは出ずに先へ進んだ → スタブが何もしないため成果物未検出で exit=2(想定どおり、5-5b とは別の検査))
- [x] 5-2: 残置 record あり + 禁止領域 dirty → `exit 2` とメッセージを確認し、結果を 1 行で記録する(結果: exit=2。残置 record id・該当パス `.claude/scripts/check-protected-branch.sh`・`set-status` 回復手順を含むメッセージが出力され、codex スタブは呼ばれずに run record が新規作成されないことを確認)
- [x] 5-3: 後片付け(使い捨てステアリング・テスト用 run record・スタブを削除し、`git status` が意図した状態であることを確認)(結果: 使い捨てワークツリーごと `git worktree remove --force` で削除。本ブランチの `git status --porcelain` は実装3ファイルの変更と `.steering/20260830-issue46-running-record-diff/` のみで意図どおり)

## 検収 1 巡目の指摘反映(design §6)

- [x] 5-5b に pathspec 正規化(`_forb_specs`)を足し、`:` 始まりを落とす(design §6-3)
- [x] git 呼び出しを `GIT_LITERAL_PATHSPECS=1` + 正規化後配列に差し替え、空配列ガードと警告文・`unset` を直す(design §6-3)
- [x] 空振り条件のコメントに `:` 始まり断片を捨てる旨を足す(design §6-3)
- [x] `codex-delegation-plan.md` §12.7 と `CHANGELOG.md` に 1 文ずつ追記する(design §6-4)
- [x] `bash -n` を通す(結果: bash -n OK。shellcheck は環境に未インストールのためスキップ)
- [x] 追加の実測(magic pathspec を混ぜても dirty を検出する)を行い、結果を 1 行で記録する(design §6-5)(結果: シェル直接比較で確認 — `GIT_LITERAL_PATHSPECS=1` 無しだと `git diff HEAD --name-only -- ".claude/scripts/" ":(exclude)...delegate-codex.sh"` が出力なし(無音の空振り)、付けると dirty ファイルが出力される。さらに使い捨て `git worktree` 上で `AGENTS.md` のマーカー内に `:(exclude).claude/scripts/delegate-codex.sh` を追記・コミットし、残置 record + `delegate-codex.sh` dirty の状態で `delegate-codex.sh impl` を実行 → `exit=2` で停止し該当パスに `.claude/scripts/delegate-codex.sh` が正しく列挙されることを確認。使い捨てワークツリーは `git worktree remove --force` で削除済み、本ブランチの `AGENTS.md` は無変更)
