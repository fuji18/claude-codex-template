# 要求: モード C(縮退)復帰時にガードレール健全性を機械検査する(Issue #42)

## 背景

モード C(`.harness/mode` = `degraded`)は人間がターミナルから `codex` を直接起動する運用で、
**`delegate-codex.sh` を通らない唯一の経路**。入口検査(denylist・依存導通)も出口検査
(禁止領域の内容ハッシュ)も一切掛からない。

さらに縮退モードは `writable_roots` に `.git` を渡す設計のため、委託先自身が

- `.git/config` の `core.hooksPath` 書き換え / `.git/hooks/` 直書きで **husky 層を無効化**できる
- 禁止領域(`AGENTS.md` の `verify-probe` を含む)への変更をコミットに紛れ込ませられる

現在の復帰時検収(`.claude/rules/mode/degraded.md`)は「`codex-log.md` を読む → `/check` →
`code-reviewer`」で、**ガードレール自体の無事を確かめるステップが無い**。人間が読み飛ばせば
検出機会が消える。

- 根拠: Codex 併用ハーネス実装レビュー(2026-08-29)S-2 / 優先順位 3 位
- 参照: `docs/template-dev/codex-delegation-plan.md` §2.3 / §12.3
- depends: なし

## スコープ

1. `check-guard-integrity.sh` に縮退復帰用の検査を足す(既存の自壊検知とはサブコマンドで分ける)
   - `core.hooksPath` が `.husky` 配下を指しているか
   - `.git/hooks/` に直書きされた実行可能フックが無いか(git 同梱の `*.sample` は除く)
   - 縮退中コミット(`Codex-authored` トレーラー)の差分が委託禁止領域に触れていないか
2. `.claude/rules/mode/degraded.md` の復帰手順に **1 コマンド**で組み込む(散文の注意書きを増やさない)
3. `.codex/skills/degraded-mode-ticket/SKILL.md` に「縮退中に `.git/` 配下を触らない」を明記する

## スコープ外

- 縮退モード自体の設計変更(`writable_roots` から `.git` を外す等)
- `.harness/mode` を Claude が書き換えられるようにすること
- **禁止領域の判定ロジック・パス一覧を `delegate-codex.sh` から複製すること**
  (単一ソースを保つため、参照用の出力口を `delegate-codex.sh` 側に足す)

## 受け入れ条件

- [ ] `core.hooksPath` を書き換えた状態で検査が落ちる(使い捨て git リポジトリで実測)
- [ ] `.git/hooks/pre-commit` を直書きした状態で検査が落ちる(`*.sample` では鳴らない)
- [ ] 禁止領域を触った `Codex-authored` コミットがある状態で検査が落ちる
- [ ] 正常な縮退復帰シナリオで誤検知しない
- [ ] **引数なしの既存呼び出し(SessionStart hook / CI の harness-integrity)の挙動が変わらない**
- [ ] `degraded.md` の手順どおりに実行して結果が読めることを確認した
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
