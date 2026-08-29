# 要求: CHANGELOG 検査のトリガに `.github/workflows/` が入っていない(Issue #41)

## 背景

`check-record-hygiene.sh:33` の CHANGELOG 検査トリガは 4 項目しかない。

```
CHANGELOG_TRIGGERS=(".claude/" ".husky/" ".codex/" "AGENTS.md")
```

一方 `.claude/template-manifest.json` の `owned` には `.github/workflows/` 配下の 5 本
(`ci.yml` / `claude.yml` / `claude-code-review.yml` / `record-hygiene.yml` / `template-update-check.yml`)が載っている。
つまり**同期対象でありながら、ワークフローだけを変更した PR は CHANGELOG 未更新でも緑になる**。
#37 が塞ごうとした穴 —「`/sync-template` で取り込む側が `[manual]` 項目に気づけない」— が、同期対象の一部でそのまま残っている。

- 根拠: Codex 併用ハーネス実装レビュー(2026-08-29)O-1 / 優先順位 2 位
- depends: なし(#40 で `.claude/scripts/` が委託禁止領域になったため、**このチケットは Codex に委託しない**)

## やること

1. `CHANGELOG_TRIGGERS` に `.github/workflows/` を追加する
2. manifest の owned 一覧とトリガの対応が今後ずれないよう、スクリプト側にコメントで根拠と運用(owned 追加時に 2 箇所直す)を残す
3. `.claude/rules/lead/delegation-policy.md` の検査表(落ちる条件)を実態に合わせる
4. `docs/template-dev/CHANGELOG.md` の「記法」節にある同じトリガ列挙も実態に合わせ、変更を追記する

## やらないこと

- `template-manifest.json` からトリガを動的に生成すること(manifest の構造変更に検査が引きずられる方が高くつく)
- 逃げ道ラベル(`no-changelog`)の仕様変更
- `record-hygiene.yml` の変更(CI 側の配管は #37 で実 PR 実測済み。今回触らない)

## 受け入れ条件

- `.github/workflows/ci.yml` だけを変更し CHANGELOG を変更しない入力で検査が落ちる
- `no-changelog` ラベルで逃げられる
- 既存 4 トリガの挙動が変わっていない
- `.github/` 配下でも `workflows/` 以外(例: `.github/ISSUE_TEMPLATE/`)は鳴らない
- `docs/template-dev/CHANGELOG.md` に追記済み
