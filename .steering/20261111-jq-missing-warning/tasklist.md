# tasklist: jq が無い環境でガードが黙って消えるのを止める

<!-- main-edit-ok -->
<!-- `.claude/scripts/` `.claude/hooks/` は委託禁止領域。司令塔が直接書く。 -->

## 実装

- [x] `session-start.sh` に `jq` 欠落の警告を足す
- [x] `check-protected-branch.sh` が `jq` 欠落で検査を飛ばすとき stderr に 1 行出す
- [x] `check-push-policy.sh` も同じ

## 文書

- [x] `docs/template-dev/CHANGELOG.md` に `## 2026-11-11` を起こす

## 検証

- [x] ホスト(`jq` 無し)で SessionStart に警告が出る(`exit 0`)
- [x] `jq` がある状態では警告が出ない(PATH にダミーの `jq` を置いて確認)
- [x] git hook 層 2 本が `jq` 無しで stderr 1 行 + `exit 0`
- [x] `bash -n`(変更した 3 本)
- [x] `check-guard-integrity.sh`(exit 0)・`prettier --check`(変更した md)
- [x] `check-manifest-coverage.sh`(ラッパー経由の `jq` で exit 0)
- [x] `test-route.sh` / `test-project-sync.sh` / `test-sync-template.sh`(all checks passed)
- [ ] `shellcheck`(ホストに無い。CI の `harness-integrity` で確認)

## 追加: Windows 版 jq の CRLF

- [x] `session-start.sh` が CRLF を出す `jq` を検知して警告する
- [x] CHANGELOG と `jq` 欠落の警告文に Windows の手順(`-b` ラッパー)を書く
- [x] 素の `jq.exe` で CRLF 警告が出る / ラッパー経由では出ない
