# 要件: 委託経路で jq を必須化し、sed フォールバック経路を削除する

- Issue: #63(P2 / `delegate:codex` なし = 対象が `.claude/scripts/` = 委託禁止領域)
- 根拠: Codex 併用ハーネス実装レビュー(2026-08-31)A2

## 背景

run record の読み書きには `jq` 不在時の **sed フォールバック経路**がある。この経路は実バグを 2 回出しており、費用対効果が逆転している。

- `rec_field` の sed 経路(`lib-record.sh`): 末尾カンマを飲み込んで `kill -0 "82711,"` が常に失敗 → **再入防止(入口検査5-5)が静かにフェイルオープン**していた Critical(#29 検収で検出、#45 で共有化)
- `write_field` の sed 経路(`codex-run.sh`): 壊れた JSON を検知するための**独自検査**(先頭 `{` / 末尾 `}` / キーの実在)を抱えている

一方この環境(devcontainer / CI)は `jq` を保証しており、sed 経路が本当に走るのは想定外の環境だけ。そして「フェイルクローズにしない理由」が**委託経路には無い** — 委託が止まっても Sonnet fork にフォールバックする、と `model-strategy.md` が宣言している。

## スコープ

1. **委託経路**(`delegate-codex.sh` の委託モード / `codex-run.sh` の書き込み系)を `jq` 必須にし、不在なら止める(`delegate-codex.sh` は **`exit 3`** = Codex 利用不可 → Sonnet fork)
2. sed 経路(`rec_field` / `write_field` の非 jq 分岐)と、それを補うための独自 JSON 検査を**削除**する
3. **止めてはいけない層はフェイルオープンを残す** — SessionStart 注入(`codex-run.sh pending`)は `jq` が無ければ注入をスキップして黙って続行する
4. `lib-record.sh` を読む全呼び出し元を洗い、どちらの層に属するかを 1 箇所ずつ判定し、**コメントに書く**

## スコープ外

- `check-protected-branch.sh` / `check-implementation-phase.sh` など**フェイルオープンが意図的な検査層**の変更
- `session-start.sh` 自身の `jq` 使用箇所(ブランチポリシー読み出し)の変更
- `check-guard-integrity.sh` の `jq` 使用箇所の変更
- run record のフォーマット変更
- `jq` を devcontainer / CI に追加する作業(すでに入っている)

## 受け入れ条件

- [ ] `PATH` から `jq` を外した状態で `delegate-codex.sh impl` が **`exit 3`** で止まる(実測)
- [ ] 同じ状態で SessionStart が**セッションを壊さない**(注入が減るだけ / `exit 0`)
- [ ] 同じ状態で `delegate-codex.sh --print-forbidden` が **exit 0 で 15 項目**を返す(`check-guard-integrity.sh degraded` の依存先を巻き込まない)
- [ ] `lib-record.sh` の呼び出し元がすべて「止める層 / 止めない層」のどちらかに分類され、コメントに書かれている
- [ ] 削除後も既存の run record が正しく読める(`pending` / `accept` を実測)
- [ ] 自己コピー exec 経路(`lib-record.sh` 同梱)が従来どおり動く(実測)
- [ ] `bash -n` / `shellcheck` / `/check` が通る
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
