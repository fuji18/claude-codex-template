# 要求内容

## 概要

Codex 委託の入口検査1 が読む `.claude/codex-denylist.txt` に、Node スタックを含む
一般的な「認証トークン・資格情報・実データの置き場」パターンを追加し、委託先へ機密が
そのまま送られる穴を塞ぐ。

対象 Issue: #21(P0)

## 背景

`.claude/codex-denylist.txt` は「ワークツリーにある機密が委託先へそのまま送られる」ことを
止める唯一のフェイルクローズ層。Codex の sandbox には読み取りの除外機能が無いため、
`.gitignore` されていてもディスク上にあれば委託先から読まれうる。

現行パターンは `.env*` / 鍵類 / `credentials*` / `.claude/settings.local.json` のみで、
**テンプレート既定が npm スタックであるにもかかわらず、認証トークンの定番置き場である
`.npmrc`(`_authToken`)が入っていない**。走査機構自体は正しく動いているため、
パターン追加だけで塞がる。

根拠: `docs/template-dev/codex-harness-review-20260825.html` 指摘3 / 推奨アクション P0

## 実装対象の機能

### 1. denylist へのパターン追加

`.claude/codex-denylist.txt` に以下を追加し、節見出しを合わせて整理する:

- パッケージ/レジストリ: `.npmrc` / `.pypirc` / `.netrc`
- git 資格情報: `.git-credentials`
- クラウド: `*-service-account*.json` / `*.tfstate` / `*.tfstate.backup`
- 実データ入りダンプ: `*.sqlite` / `*.sqlite3` / `*.db` / `dump*.sql`

### 2. 追加パターンの動作確認

該当ファイルを置いた状態で `delegate-codex.sh impl` が `exit 2` で止まることを確認し、
既存パターン・除外規則(`*.example` / `*.sample` / `*.template`)の挙動が変わらないことを確認する。

## 受け入れ条件

### denylist へのパターン追加

- [ ] 追加した各パターンについて、該当ファイルを置いた状態で委託が `exit 2` で止まる(最低でも `.npmrc` と `*.tfstate` の 2 種で確認)
- [ ] `*.example` / `*.sample` / `*.template` の除外がこれまで通り効く
- [ ] 既存パターンの挙動が変わっていない(`.env` / `*.pem` 等)
- [ ] `.db` / `*.sqlite` の追加で通常の開発ワークツリーが常時ブロックされない

### 後始末

- [ ] 検証で作成した一時ファイルがワークツリーに 1 つも残っていない(`git status` がクリーン + 未追跡ファイル無し)

## 成功指標

- 追加パターン 11 種すべてがファイル名一致で検出される
- 検証後のワークツリーに検証用ファイルが残らない(誤コミットゼロ)

## スコープ外

以下はこのチケットでは実装しません:

- 走査機構・フェイルクローズ判定の変更(現行のままで正しい)
- ホームディレクトリ配下の資格情報(sandbox の外なので denylist では守れない。別チケット)
- 出口検査(`FORBIDDEN_PATHS`)側の変更

## 参照ドキュメント

- `CLAUDE.md`「Codex への委託禁止領域(パス)」 — `codex-denylist.txt` は委託禁止領域
- `.claude/scripts/delegate-codex.sh` 入口検査1(L164-225)
- `docs/template-dev/codex-delegation-plan.md` §10.2
