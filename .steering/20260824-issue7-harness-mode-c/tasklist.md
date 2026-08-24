# タスクリスト: 段階5 — モード C(縮退)の Codex 単独運用

<!-- 検収完了(2026-08-24): code-reviewer P1×2 対応済み / lint・型・テスト・format 全て pass -->

Issue: #7 / design: `design.md`(§ 番号は design.md のもの)

<!-- main-edit-ok -->
> **なぜ脱出弁が要るか**: タスク1 の `.codex/` は Codex の sandbox が書き込みを拒否する
> (design.md §8 で裏取り済み)。物理的に委託できないため、司令塔が直接書く。
> **タスク2 以降は Codex への委託対象。**

## 司令塔が担当(委託不可)

- [x] 1. `.codex/skills/degraded-mode-ticket/SKILL.md` を作成する(design.md §2 の内容をそのまま)

## Codex へ委託

- [x] 2. `.claude/template-manifest.json` の `owned` に `.codex/skills/` を追加する(design.md §3)
- [x] 3. `README.md` の `.codex/` ディレクトリ説明に `skills/` の行を追加する(design.md §4)
- [x] 4. `docs/template-dev/codex-delegation-plan.md` §7.3 の読み替え注記を確定結果に更新する(design.md §5-1)
- [x] 5. 同 §13 #4 の行を実機確認の結果で更新する(design.md §5-2)
- [x] 6. 同 §13 の表直後の総括文を「未確認事項なし」に更新する(design.md §5-3)
- [x] 7. 同 §12.3 手順5 を実体のパスと起動方法に更新する(design.md §5-4)
- [x] 8. 同ドキュメントに「`.codex/` は Codex 自身が書き込めない」制約を追記する(design.md §8。§9「リスクと注意点」が適切)
- [x] 9. 検証を通す(design.md §6: マニフェストの JSON 構文 / format:check / lint / typecheck / test)

## 追加(design.md §9 / `.git` 書き込み検証の結果)

- [x] 10. SKILL.md に入口検査5(`.git` が書けるか)を追加する — **司令塔担当**(`.codex/` は委託不可)
- [x] 11. 計画ドキュメント §9 の `.git` read-only 項目を検証済みの結果と回避策に更新する
- [x] 12. 同 §12.3 手順5 にモード C の起動コマンド(`-c 'sandbox_workspace_write.writable_roots=[".git"]'`)を明記する
