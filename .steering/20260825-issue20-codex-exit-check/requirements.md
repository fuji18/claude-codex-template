# 要件: Codex 委託の出口検査 — 禁止領域への差分を機械的に止める

- Issue: #20(P0 / `delegate:codex` なし = 対象が委託禁止領域そのもの)
- 根拠: `docs/template-dev/codex-harness-review-20260825.html` 指摘1・指摘4・指摘6

## 背景

impl 委託(`--sandbox workspace-write`)中の Codex は、ワークツリー内なら**禁止領域も含めて書ける**。
書き換えた先の一部は、**後でサンドボックスの外で実行される**:

- `AGENTS.md` の `<!-- verify-probe: ... -->` は、次回の委託時に `delegate-codex.sh` が
  入口検査3 で**ホスト上の `bash -c` にそのまま渡す**。「サンドボックス内で 1 行書く →
  次回起動時にホストで任意コマンド実行」という脱出経路が成立する
- `.husky/*` / `.claude/scripts/*` も、ホストの git・Claude セッションが実行する
- `.github/workflows/*` は、非 fork PR で `CLAUDE_CODE_OAUTH_TOKEN` にアクセスできる
  ワークフロー定義そのもの

現状この類型への防御は **AGENTS.md §4 の散文と司令塔の検収レビューだけ**。
入口検査は 5 系統あるのに、出口が素通しになっている。

## やること

1. `delegate-codex.sh` の impl 実行後に**出口検査**を追加する(該当あれば `failed` + `exit 2`)
2. 禁止パスリストに `AGENTS.md` / `.github/workflows/` / `.harness/mode` / `.harness/codex-runs/` を追加する
3. 散文(`CLAUDE.md` / `AGENTS.md` §4 マーカー内)を同期する
4. 出口検査の「空振り条件」をコメントで明示する(既存の入口検査群と同じ作法)

## やらないこと

- denylist(送信側)のパターン追加 → #21
- 環境変数のサニタイズ → #23
- explore / review モードへの出口検査(read-only なので差分は原理的に出ない)

## 受け入れ条件

- [ ] impl 委託中に `AGENTS.md` / `.husky/pre-commit` / `.github/workflows/ci.yml` のいずれかを
      変更させたシナリオで、`status=failed` かつ `exit 2` になり、該当パスが summary/error に出る
- [ ] 禁止領域に触れない通常の impl 委託が、これまで通り `completed` / `exit 0` で終わる(誤検出なし)
- [ ] 委託前から dirty なファイル(禁止領域内)がある場合に誤検出しない
- [ ] `CLAUDE.md` と `AGENTS.md` の禁止領域リストが、スクリプト内のリストと一致している
- [ ] 再現テスト手順が `.steering/` に記録されている
