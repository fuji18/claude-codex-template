# タスクリスト: verify-probe のホスト実行に形式検査と環境遮断を入れる

Issue: #43 / design: `design.md`

## 実装

- [x] `delegate-codex.sh` 入口検査3 に許可リスト定数(`PROBE_ALLOWED_CMDS` / `PROBE_VERIFY_TOKENS`)を追加する(design §2)
- [x] `probe_format_reason()` を追加する(design §3。判定 5 項目 = 長さ / 文字・区切り / 第1トークン / 導通確認トークン / npx の --no-install)
- [x] `PROBE_ENV` 配列を追加する(design §4)
- [x] `PROBE=` 以降の分岐を 3 分岐に書き換える(design §5。形式外 = 警告 + スキップ、適合 = 実行前に stderr 表示 → `env -i` 実行)
- [x] 174 行付近のコメントに 1 行足す(design §6)

## ドキュメント

- [x] `AGENTS.md` §2 に形式制約を追記する(design §7)
- [x] `AGENTS.md` §7 の `AGENTS.md` の項に 1 文足す(design §7)
- [x] `CLAUDE.md` の禁止領域 `AGENTS.md` の項に追記する(design §8)
- [x] `docs/template-dev/CHANGELOG.md` の `## 2026-08-29` に追記する(design §9)

## 検証(design §10。V1-V7 をすべて実行し結果を記録する)

- [x] V1 現行プローブが通る(`検証プローブを実行します:` が出る)
- [x] V2 `curl ...` が実行されず警告
- [x] V3 `; rm -rf ...` が実行されない(`/tmp/probe-canary` が残る)
- [x] V4 `rm -rf --version` が「許可されていないコマンド」で弾かれる
- [x] V5 `npx eslint --version`(`--no-install` 欠落)が弾かれる
- [x] V6 `npm run lint` が導通確認トークン不足で弾かれる
- [x] V7 `node --version` が通る
- [x] `AGENTS.md` を復元し、`git status` で意図した差分だけになっていることを確認する
- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る

## 改訂: 検収 round 1 の Critical 対応(design §12)

- [x] `probe_format_reason()` に改行の明示的な排除 (a2) を足す(design §12.3)
- [x] `probe_format_reason()` の (c)(d)(e) を固定形マッチ(P1/P2/P3)に置き換える(design §12.3)。定数 `PROBE_ALLOWED_CMDS` / `PROBE_VERIFY_TOKENS` は変更しない
- [x] `AGENTS.md` §2 の形式制約の箇条書きを差し替える(design §12.4)
- [x] `docs/template-dev/CHANGELOG.md` の `[auto]` 項の説明を差し替える(design §12.5)
- [x] V1〜V7 を再実行し、期待どおりであることを確認する(V6 は理由文言のみ変化。V4/V5 も新方式ではトークン数不一致で汎用理由文に変わったが、いずれも「実行されない」という要件は満たす)
- [x] V8 `npm install left-pad --version` が実行されない + `git status --short` がきれい
- [x] V9 `pip install requests --version` が実行されない
- [x] V10 `go run example.com/evil --version` が実行されない
- [x] V11 `python3 -m pytest --version` が形式検査を通る
- [x] V12 `cargo --version` が形式検査を通る
- [x] V13 `npx --no-install eslint`(末尾が確認フラグでない)が実行されない
- [x] `AGENTS.md` を復元し、`git diff` が意図した差分だけであることを確認する
- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る

## 改訂2: 検収 round 2 の Critical 対応(design §13)

- [x] P3 を 5 トークン形(`python|python3 -I -m <module> <verify>`)に変える(design §13.4 (1))。`n = 4` ブロックは P2 のみにする
- [x] (c) のコメントの P3 の行と、末尾の汎用エラーメッセージを `-I` 付きに直す(design §13.4 (1)(2))
- [x] 残存リスクのコメントを許可リスト説明の末尾に足す(design §13.4 (3))
- [x] `AGENTS.md` §2 の P3 の行を `-I` 付きに変え、残存リスクの箇条書きを 1 項目足す(design §13.5)
- [x] `docs/template-dev/CHANGELOG.md` の `[auto]` 項の末尾に 1 文足す(design §13.6)
- [x] V14 `python3 -I -m pytest --version` が通る(形式検査は合格。pytest 未インストール環境のため実行自体は失敗するが `検証プローブを実行します:` は出る)
- [x] V15 `python3 -m pytest --version`(`-I` なし)が実行されない
- [x] V16 `evilmod.py` を置いて `python3 -I -m evilmod --version` を流し、`EVIL PY EXECUTED` が出ないことを確認 → `evilmod.py` を削除
- [x] V1〜V10 / V12 / V13 を再実行して退行が無いことを確認する
- [x] `AGENTS.md` を復元し、`git status --short` に想定外のファイルが無いことを確認する
- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る

## 改訂3: 検収 round 3 の Critical 対応(design §14)

- [x] `_probe_name_ok()` ヘルパーを `probe_format_reason()` の直前に足す(design §14.2 (3))
- [x] P2 のパッケージ名検査を `^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$` + `..` 排除に変える(design §14.2 (1))
- [x] P3 のモジュール名検査も `_probe_name_ok()` 経由にする(design §14.2 (2))
- [x] `docs/template-dev/CHANGELOG.md` の 3 形の列挙を `python -I -m <module> <verify>` に直す(design §14.3)
- [x] V17 `npx --no-install docs/../../../../../../../bin/sh --version` が実行されない(`Illegal option` が出ない)
- [x] V18 `npx --no-install ../eslint --version` が実行されない
- [x] V19 `npx --no-install @scope/pkg --version` が形式検査を通る
- [x] V20 `npx --no-install eslint --version` が通る(退行なし)
- [x] V21 `python3 -I -m ..evil --version` が実行されない
- [x] V1〜V16 を再実行して退行が無いことを確認する
- [x] `AGENTS.md` を復元し、`git status --short` に想定外のファイルが無いことを確認する
- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る

## 改訂4: 検収 round 4 の Critical 対応(design §15)

- [x] `PROBE_VERIFY_TOKENS` を `"--version -version"` に絞り、理由をコメントに書く(design §15.2 (1))
- [x] `go version` の完全一致特例を、末尾トークン検査より**前**に置く(design §15.2 (2))
- [x] (c) のコメントの P1 の例を `node --version / java -version` に直す(design §15.2 (3))
- [x] `AGENTS.md` §2 の確認フラグの記述・P1 の例・`go version` の注記を差し替える(design §15.3)
- [x] `docs/template-dev/CHANGELOG.md` の `[auto]` 項の末尾に 1 文足す(design §15.3)
- [x] V22 `node version` + `version` ファイルで `/tmp/pwned` が作られない → `version` ファイルを削除
- [x] V23 `python3 version` / `ruby version` / `rake version` / `gradle version` がすべて実行されない
- [x] V24 `go version` が形式検査を通る
- [x] V25 `java -version` が形式検査を通る
- [x] V26 `node -v` / `node --help` が実行されない
- [x] V27 現行プローブ 3 種に退行が無い
- [x] V1〜V21 を再実行して退行が無いことを確認する(V16 も併せて再確認。すべて期待どおり)
- [x] `AGENTS.md` を復元し、`git status --short` に想定外のファイル(`version` / `Rakefile` 等)が無いことを確認する
- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る

## 改訂5: 検収 round 5 の Critical 対応(design §16)

- [x] `PROBE_ALLOWED_CMDS` を `"node npm npx python python3 ruby java rake gradle"` に差し替え、選定理由と追加時の検証手順をコメントに書く(design §16.3 (1))
- [x] `go version` の完全一致特例を削除する(design §16.3 (2))
- [x] `PROBE_ENV` に `COREPACK_ENABLE_NETWORK=0` を足す(design §16.3 (3))
- [x] `AGENTS.md` §2 の許可コマンドの記述を差し替え、`go version` の項目を削除、P1 の例を直す(design §16.4)
- [x] `docs/template-dev/CHANGELOG.md` の `[auto]` 項の末尾に 1 文足す(design §16.4)
- [x] V28 `yarn --version` / `pnpm --version` / `mvn --version` がすべて実行されない
- [x] V29 `go version` が実行されない
- [x] V30 `node --version` / `java -version` / `rake --version` / `gradle --version` / `python3 --version` / `ruby --version` が通る
- [x] V31 `npx --no-install eslint --version` / `python3 -I -m pytest --version` が通る
- [x] V32 `cargo --version` / `deno --version` が実行されない
- [x] V1〜V27 を再実行して退行が無いことを確認する(V24・cargo 系は期待値が変わる。curl / rm / npx欠落 / npm run lint / パストラバーサル / スコープ付きパッケージ / node version / node -v / node --help を代表サンプルとして再実行し、すべて期待どおり)
- [x] `AGENTS.md` を復元し、`git status --short` に想定外のファイルが無いことを確認する
- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る

## 改訂6: 検収 round 6 の Major 対応(design §17)— 最終

- [x] `PROBE_VERIFY_TOKENS` を `"--version"` に絞り、理由をコメントに書く(design §17.1)
- [x] `java -version` の完全一致特例を、末尾トークン検査より**前**に置く(design §17.1)
- [x] `PROBE_ALLOWED_CMDS` から `python` を削除して 8 個にし、理由をコメントに書く(design §17.2)
- [x] P3 の第 1 トークン判定を `python3` のみにする(design §17.2)
- [x] `docs/template-dev/CHANGELOG.md` の「例外は `go version` のみ」を削除し、確認フラグと許可コマンド数(8)の記述を直す(design §17.3)
- [x] `AGENTS.md` §2 の確認フラグ・許可コマンド・P3 の例を差し替える(design §17.4)
- [x] V33 `java -version` が通る / V34 `java --version` が通る
- [x] V35 `ruby -version` / `rake -version` / `python3 -version` / `node -version` がすべて実行されない
- [x] V36 `python --version` / `python -I -m pytest --version` が実行されない
- [x] V37 `python3 -I -m pytest --version` / `python3 --version` が通る
- [x] V38 主要な正当プローブ 6 種に退行が無い
- [x] V1〜V32 を再実行して退行が無いことを確認する(司令塔が検収として直接実行。fork が枠上限で中断したため)
- [x] `grep -rn 'go version' AGENTS.md docs/template-dev/CHANGELOG.md .claude/scripts/delegate-codex.sh` が空になる
- [x] `AGENTS.md` を復元し、`git status --short` に想定外のファイルが無いことを確認する
- [x] `bash -n .claude/scripts/delegate-codex.sh` が通る
