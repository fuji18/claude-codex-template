# 要件: hooksPath 判定を一本化し、ポリシー空洞化検査を強化する(Issue #59)

## 背景

Codex 併用ハーネス実装レビュー(2026-08-31)の A1 / A5。優先度 P1。

### A1 — 「husky が有効か」の判定が 4 箇所に分散し、厳しさが揃っていない

| 箇所 | 判定内容 |
| --- | --- |
| (1) `delegate-codex.sh` 入口検査 5-3 | 空 or 実在しないディレクトリ |
| (2) `check-guard-integrity.sh` D1 | 上記 + **`.husky` 配下かまで確認** |
| (3) `AGENTS.md` §1-3 | 散文 |
| (4) `.codex/skills/degraded-mode-ticket/SKILL.md` 検査 3 | 散文 |

(1) は (2) より緩く、**実在する無関係なディレクトリを指す `core.hooksPath` を素通しする**。
このリポジトリは「判定の実体を 1 ファイルに集約する」という原則を
`check-protected-branch.sh` / `latest-steering.sh` / `harness-mode.sh` で 3 回適用済みで、
ここだけ未適用になっている。

### A5 — ポリシー検査が「空」以外の空洞化を見ない

`check-guard-integrity.sh` の検査 1 は `protectedBranches` が**空かどうか**しか見ない。

- `protectedBranches: ["develop"]`(`baseBranch` が `main` のまま)への差し替え
- `allowedPrefixes` に保護ブランチ名そのもの(または空文字列)を入れる改変

はいずれも、**全層が正常に動作したうえで素通しする**形で保護を消す。#56 で
`branch-policy.json` を委託禁止領域に入れたことで委託経路は塞がったが、
**人間の手による誤編集**には効かない。両方入って初めて両面が埋まる。

## スコープ(やること)

1. **hooksPath 判定の一本化** — `check-guard-integrity.sh` に判定の実体を集約し、
   `delegate-codex.sh` 入口検査 5-3 から呼ぶ。5-3 の判定が D1 と同じ厳しさに揃う。
   5-3 の終了コード(`exit 3` = Codex 利用不可扱い)の意味は変えない
2. **ポリシー整合検査の強化** — 検査 1 に次の 2 つを追加する
   - `baseBranch` が `protectedBranches` に含まれるか
   - `allowedPrefixes` に保護ブランチ名へ前方一致する接頭辞が入っていないか
3. **散文の導線化** — `AGENTS.md` §1-3 と `degraded-mode-ticket` 検査 3 を、
   判定の実体の再掲ではなく「検査を回せ」への導線に書き換える(散文が
   3 つ目・4 つ目のソースにならないようにする)

## スコープ外(やらないこと)

- `check-protected-branch.sh` の統合(すでに一本化済み)
- ポリシーファイルのスキーマ検証全般。**保護が空洞化する 2 パターンに絞る**
- `releaseBase` / `releasePrefixes` / `remoteSessionPrefix` の整合検査
- D2 / D2.5 / D3(縮退復帰検査の他ブロック)への変更
- `core.hooksPath` の自動修復。検査は「有効かどうかを確認する」までで、復旧は人間の担当

## 受け入れ条件

- [ ] `git config core.hooksPath /tmp`(実在するが無関係)の状態で、5-3 と D1 が**同じ判定**になる
- [ ] `baseBranch: main` / `protectedBranches: ["develop"]` の状態で guard-integrity が反応する
- [ ] `allowedPrefixes` に `main` を入れた状態で guard-integrity が反応する
- [ ] 正常な設定で誤爆しない(devcontainer / CI の fresh checkout 双方)
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## 制約

- CI の fresh checkout では `core.hooksPath` 未設定・`.git/hooks/` が sample だけ、という
  既存の非誤検知条件を壊さないこと(`check-guard-integrity.sh` 冒頭のコメント)
- `.codex/skills/degraded-mode-ticket/SKILL.md` は `.prettierignore` の対象外 =
  **prettier の整形対象**。`AGENTS.md` / `.claude/` / `docs/` は対象外
- 対象が `.claude/scripts/` = **委託禁止領域**のため `delegate:codex` は付けない
