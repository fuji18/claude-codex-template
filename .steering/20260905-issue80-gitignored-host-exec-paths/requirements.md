# 要求: 禁止領域から抜けている「gitignore 済みのホスト実行経路」を塞ぐ

- Issue: #80(P0 / `delegate:codex` なし = 委託禁止領域が対象のため委託しない)
- 根拠: Codex 併用ハーネス実装レビュー(2026-09-04)S1 / S3、対応順序 1

## 解く問題

禁止領域の列挙が「**git 追跡下のファイル**」を暗黙の前提にしており、`.gitignore` 済みだが
ホストが実行する経路が 2 つ抜けている。

### S1: `.husky/_/` が抜けている

`core.hooksPath` は `.husky/_`。git が起動するのは `.husky/_/pre-commit` で、それが
`.husky/_/h` を source し、`h` が最後に `sh -e ".husky/pre-commit"` を呼ぶ。
**守られている `.husky/pre-commit` はチェーンの末端で、実際の入口は `.husky/_/` の側。**
`.husky/_/.gitignore` が `*` なので追跡外であり、`FORBIDDEN_PATHS` が 2 ファイルしか
持たないため全層(出口検査 / `git diff` / `check-guard-integrity.sh` / CI)が同時に素通しする。

成立する攻撃は 2 つ:

1. **ガードレールの無音化** — `.husky/_/pre-commit` を `exit 0` に潰すと、ベンダー非依存の
   保護層が消えるのに `check-guard-integrity.sh` は健全と報告し続ける
2. **ホストコード実行** — `.husky/_/h` は人間や Claude が `git commit` を叩くたびに
   ホスト上・ネットワーク有効・サンドボックス外で走る

根本原因は原則の適用漏れ。`CLAUDE.md` は「個別列挙は漏れるのでディレクトリ単位で禁止する」と
`.claude/scripts/` について明言している(#40)のに、`.husky/` にだけ適用されていない。
しかも `CLAUDE.md` の「3 系統」の説明は実体を `.husky/*` と書いており、**散文(ディレクトリ)と
配列(2 ファイル)がすでに食い違っている**。

### S3: `.claude/settings.local.json` が抜けている

`.claude/settings.json` は禁止領域にあるが `.claude/settings.local.json` は無い。hooks と
permissions を定義でき、`.gitignore` 済みで `git diff` にも出ない。委託先が新規作成すると、
**次に人間が Claude セッションを開いた瞬間に SessionStart hook としてホストコマンドが走る**。
denylist による緩和はあるが、止まるのは「次の委託」であって「次のセッション開始」ではない。

## 受け入れ条件(Issue 転記)

- [ ] `bash .claude/scripts/delegate-codex.sh --print-forbidden` が `.husky/` と `.claude/settings.local.json` を出力する
- [ ] `.husky/_/pre-commit` を書き換えた状態で impl 委託を回すと、出口検査が `failed` / `exit 2` を返す(再現テストで確認する)
- [ ] `.claude/settings.local.json` を新規作成した状態で impl 委託を回すと、出口検査が `failed` / `exit 2` を返す
- [ ] `check-guard-integrity.sh` が `.husky/_/pre-commit` の無音化を検出する
- [ ] `CLAUDE.md` / `AGENTS.md` §4 の記述が配列と一致している
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## スコープ外

- `node_modules/` を禁止領域に入れること(S2 のチケット #82 で別に扱う)
- `.harness/codex-runs/` の扱いの変更(B1)
- `.husky/_/h` の内容を husky 同梱版と完全一致で検証すること(husky のバージョン更新で毎回落ちる)
