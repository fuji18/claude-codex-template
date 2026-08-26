# 設計書

<!-- status: ready -->

## アーキテクチャ概要

**変更は `.claude/codex-denylist.txt` の 1 ファイルのみ。** スクリプト(`delegate-codex.sh`)は
一切触らない。走査機構は既に正しく動いており、パターンを増やすだけで塞がる。

```
delegate-codex.sh 入口検査1(L164-225)
  ├─ .claude/codex-denylist.txt を読む      ← ここだけを変更する
  │    / を含む行 → find -path "./PATTERN"
  │    / を含まない行 → find -name "PATTERN"
  ├─ find . (node_modules/.git/.harness を prune) で該当を探す
  ├─ grep -Ev '\.(example|sample|template)$' で除外
  └─ 該当あり → exit 2(CODEX_DELEGATE_ACK_SECRETS=1 で承認可)
```

## コンポーネント設計

### 1. `.claude/codex-denylist.txt`

**責務**:
- 委託先へ送ってはいけないファイルのパターンを列挙する(単一ソース)

**実装の要点**:
- **冒頭のコメントブロック(1〜19 行目)は書式説明の単一ソースなので、意味を変えない。**
  誤検出の扱いについて 1 段落だけ追記する(下記の全文どおり)
- 節見出しを、追加パターンを含む形に再編する。既存の 10 パターンは
  **1 つも削らない**(受け入れ条件「既存パターンの挙動が変わっていない」)
- 行末コメントは書けない(`#` 以降が切り捨てられる)。注記は必ず**独立した行**に書く

### 2. 追加パターンの選定根拠(設計判断済み。実装者は判断しない)

| パターン | 何を守るか |
| --- | --- |
| `.npmrc` | npm レジストリの `_authToken`。テンプレート既定スタックの最大の穴 |
| `.pypirc` | PyPI のアップロードトークン |
| `.netrc` | machine/login/password 形式の汎用資格情報 |
| `.git-credentials` | git credential store の平文トークン |
| `*-service-account*.json` | GCP サービスアカウント鍵(秘密鍵を含む JSON) |
| `*.tfstate` / `*.tfstate.backup` | Terraform state。リソースの実値(パスワード等)を平文で含む |
| `*.sqlite` / `*.sqlite3` / `*.db` | ローカル DB の実データ |
| `dump*.sql` | 本番/検証データのダンプ |

**採用済みの設計判断(実装者はこれに従うだけでよい):**

1. **`.npmrc` は「トークンが無くてもブロックされる」ことを許容する。** レジストリ設定だけの
   `.npmrc` をコミットしているプロジェクトでは毎回止まるが、この層はフェイルクローズが正しく、
   誤検出は `CODEX_DELEGATE_ACK_SECRETS=1` で通せる。**中身を見る判定には変えない**
   (スクリプト変更はスコープ外)
2. **`*.db` は残す。** `.gitignore` にある `Thumbs.db`(Windows/WSL 環境で湧く)に当たりうるが、
   本テンプレートのワークツリーでは実測 0 件。誤検出時は上記の承認で通せる。この既知の癖は
   denylist のコメントに 1 行残す
3. **`*.sqlite` / `*.sqlite3` / `*.db` / `dump*.sql` は「実データ」節としてまとめる。** これらは
   資格情報ではないが、委託先へ送られると個人情報・本番データが漏れるため同じ層で止める

## 変更後の `.claude/codex-denylist.txt` 全文

以下をそのまま最終形とする(実装者はこの内容でファイルを置き換える):

```text
# Codex 委託の送信禁止パターン(単一ソース)。
#
# .claude/scripts/delegate-codex.sh の入口検査1 がこのファイルを読む。
# Codex の sandbox には読み取りの除外機能が無い(計画 §13 #7 で確定)ため、
# ワークツリーにある機密はそのまま委託先へ送られうる。ここが唯一の層。
#
# 書式:
#   - 1 行 1 パターン。空行と # 始まりの行は無視される
#   - パターンに / を含む   → リポジトリルートからのパス一致(find -path "./PATTERN")
#   - パターンに / を含まない → ファイル名一致(find -name "PATTERN")
#   - シェルの glob がそのまま使える(* ? [])
#   - 先頭に / や ./ は付けない(リポジトリルートからの相対で書く)
#   - パターンに # は使えない(行内の # 以降はコメントとして切り捨てられる)
#
# 末尾が .example / .sample / .template のファイルは常に対象外(プレースホルダ)。
# node_modules / .git / .harness は走査自体をしない。
#
# このファイルが無い、または有効パターンが 0 件のときは委託を止める(フェイルクローズ)。
#
# 誤検出は許容する層。中身を見ずにファイル名だけで止めるため、機密を含まない
# .npmrc(レジストリ設定のみ)や Thumbs.db でも止まる。内容を確認したうえで
# CODEX_DELEGATE_ACK_SECRETS=1 を付けて再実行すれば通せる。通したコスト(機密の送信)が
# 止めたコスト(Sonnet fork への切替)より大きいので、迷ったら止める側に倒す。
#
# 根拠: docs/template-dev/codex-delegation-plan.md §10.2

# --- 実行時シークレット ---
.env
.env.*

# --- 鍵・証明書 ---
*.pem
*.key
id_rsa*
id_ed25519*
*.p12
*.pfx

# --- 資格情報ファイル ---
credentials*
.git-credentials
.netrc
*-service-account*.json

# --- パッケージレジストリの認証 ---
.npmrc
.pypirc

# --- インフラ状態(リソースの実値を平文で含む) ---
*.tfstate
*.tfstate.backup

# --- 実データ(資格情報ではないが、送られると個人情報・本番データが漏れる) ---
# *.db は Thumbs.db 等の OS 生成ファイルにも当たる。誤検出したときは
# 内容を確認して CODEX_DELEGATE_ACK_SECRETS=1 で通す。
*.sqlite
*.sqlite3
*.db
dump*.sql

# --- ローカル固有設定(トークンが入りうる) ---
.claude/settings.local.json
```

## データフロー(検証手順)

**⚠️ 実際の委託を絶対に走らせないこと。** 検証には**存在しないステアリングディレクトリ**を
target に渡す。入口検査の順序は 1(機密) → 2/3(AGENTS.md + probe) → 4(codex CLI) → 5(target 検査)
なので、機密が検出されなかった場合も検査5 で必ず止まり、codex は起動しない。

`CODEX_DELEGATE_ACK_SECRETS` が環境に設定されていると検査が素通しになるため、
**検証コマンドは必ず `env -u CODEX_DELEGATE_ACK_SECRETS` を付けて実行する。**

### 検証1: 追加パターンが検出されること(受け入れ条件1)

```bash
# 空ファイルでよい(find は -type f を見るだけで中身は読まない)。
# 実際のトークン文字列は絶対に書かない(secretlint と pre-commit に引っかかる)。
touch .npmrc .pypirc .netrc .git-credentials \
      gcp-service-account-dev.json terraform.tfstate terraform.tfstate.backup \
      local.sqlite local.sqlite3 app.db dump_20260826.sql

env -u CODEX_DELEGATE_ACK_SECRETS \
  .claude/scripts/delegate-codex.sh impl .steering/__verify_nonexistent__
echo "exit=$?"
```

**期待**: `exit=2` で、stderr に「ワークツリーに機密の可能性があるファイルがあります。」と
**上記 11 ファイルすべて**が列挙される(列挙は `head -20` で切られるため、11 件なら全件出る)。

```bash
rm -f .npmrc .pypirc .netrc .git-credentials \
      gcp-service-account-dev.json terraform.tfstate terraform.tfstate.backup \
      local.sqlite local.sqlite3 app.db dump_20260826.sql
```

### 検証2: 除外規則が効くこと(受け入れ条件2)

```bash
touch .env.example .npmrc.sample app.db.template

env -u CODEX_DELEGATE_ACK_SECRETS \
  .claude/scripts/delegate-codex.sh impl .steering/__verify_nonexistent__
echo "exit=$?"

rm -f .env.example .npmrc.sample app.db.template
```

**期待**: stderr に「機密の可能性があるファイル」が**出ない**(検査1 を通過している)。
止まるのは検査5 の「impl の target は design.md と tasklist.md を持つステアリング
ディレクトリである必要があります」で、`exit=2`。**この違い(メッセージ)で合否を判定する**
— 終了コードだけでは検証1 と区別できない。

なお `.npmrc.sample` は `-name ".npmrc"` にそもそもマッチしないが、`.env.example` は
`.env.*` にマッチしたうえで除外されるため、除外規則そのものの確認になる。

### 検証3: 既存パターンの挙動が変わっていないこと(受け入れ条件3)

```bash
touch .env server.pem deploy.key credentials.json

env -u CODEX_DELEGATE_ACK_SECRETS \
  .claude/scripts/delegate-codex.sh impl .steering/__verify_nonexistent__
echo "exit=$?"

rm -f .env server.pem deploy.key credentials.json
```

**期待**: `exit=2` で 4 件すべてが列挙される。

### 検証4: 通常のワークツリーが常時ブロックされないこと(受け入れ条件4)

一時ファイルを**すべて削除した状態**で:

```bash
env -u CODEX_DELEGATE_ACK_SECRETS \
  .claude/scripts/delegate-codex.sh impl .steering/__verify_nonexistent__
echo "exit=$?"
```

**期待**: 「機密の可能性があるファイル」が出ず、検査5 のメッセージで `exit=2`。

### 検証5: 後始末(受け入れ条件・後始末)

```bash
git status --porcelain
```

**期待**: `.claude/codex-denylist.txt` と `.steering/20260826-issue21-denylist-patterns/` 以外の
エントリが 1 つも無い。検証用ファイルの消し忘れは**誤コミットに直結する**ので必ず確認する。

## エラーハンドリング戦略

該当なし(設定ファイルのパターン追加のみで、コードパスは追加されない)。

## テスト戦略

自動テスト(vitest)は追加しない。**このリポジトリに `tests/` は存在せず、検査対象は
シェルスクリプトの `find` 挙動**であるため、上記の手動検証手順を tasklist の
チェック項目として実行し、結果を tasklist の振り返りに残す形で担保する。

## 依存ライブラリ

追加なし。

## ディレクトリ構造

```
.claude/codex-denylist.txt   (変更: パターン追加 + 節見出し再編 + コメント追記)
```

## 実装の順序

1. `.claude/codex-denylist.txt` を上記「変更後の全文」で置き換える
2. 検証1〜4 を順に実行し、期待どおりであることを確認する
3. 検証5(後始末)で一時ファイルが残っていないことを確認する
4. `/check`(lint / format)を通す

## セキュリティ考慮事項

- **検証用ファイルに実在のトークン・鍵を書かない。** `touch` で空ファイルを作るだけでよい
- **検証用ファイルを消し忘れない。** `.npmrc` や `*.tfstate` は `.gitignore` に無いため、
  残したままコミットすると追跡対象に入る
- 検証は**必ず存在しない target** に対して行う。実在のステアリングディレクトリを渡すと
  検査を全部通過して実際の委託が起動し、Codex の枠を消費する

## パフォーマンス考慮事項

パターンが 10 → 21 に増えるが、`find` の式が長くなるだけで走査対象(prune 済み)は
変わらない。実測で問題になる規模ではない。

## 将来の拡張性

- ホームディレクトリ配下の資格情報(`~/.aws/credentials` 等)は sandbox の外なので
  この層では守れない。別チケットで扱う(スコープ外)
- 中身を見る判定(`_authToken` の有無で分岐する等)に発展させる場合は
  `delegate-codex.sh` の変更が必要 = 委託禁止領域なので司令塔が直接書く
