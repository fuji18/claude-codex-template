# テンプレート CHANGELOG

テンプレート利用側(このテンプレートから作ったプロジェクト)が **`/sync-template` で更新を取り込むとき** に読む変更履歴です。テンプレート自身の開発メモではなく、**「取り込む側が何をすればよいか」** だけを書きます。

## 記法

- 新しいものを**上**に置く。見出しは `## YYYY-MM-DD` の日付単位
- 各項目の先頭に区分を付ける:
  - **`[auto]`** — `/sync-template` の上書きだけで完結する。取り込む側の作業はゼロ
  - **`[manual]`** — 取り込む側に作業が必要。**何をすればよいかを 1 行で書く**(これが無い `[manual]` は書いた意味がない)
- 破壊的変更(既存の運用が壊れる)は `[manual]` にし、行頭に **⚠️** を付ける
- `/sync-template` は `syncedAt` のコミット日以降の日付見出しだけを読む。**日付を遡って過去の見出しに追記しない**(取り込む側が見落とす)
- **`.claude/` / `.husky/` / `.codex/` / `.github/workflows/` / `AGENTS.md` を変更する PR は、このファイルの更新も必須。** CI(`.github/workflows/record-hygiene.yml`)が機械的に検査し、漏れていれば PR を落とす。追記が不要な変更(リバート・誤字修正など)はラベル `no-changelog` で外す

---

## 2026-09-01

**`core.hooksPath` の判定を 1 本化し、ポリシー空洞化検査を強化した(Issue #59)。** `delegate-codex.sh` 入口検査 5-3 は「空 or 実在しないディレクトリ」だけを見ており、`check-guard-integrity.sh` の D1(モード C 復帰検収)より緩い判定でした。実在する無関係なディレクトリを指す `core.hooksPath` を 5-3 は素通しし、D1 だけが検出する食い違いがありました。

- **[auto]** `core.hooksPath` の判定を `check-guard-integrity.sh` の `check_hooks_path()` に集約し、新しい `hooks-path` サブコマンドを追加しました。`delegate-codex.sh` 5-3 はこのサブコマンドを呼ぶだけになり、D1 と同じ厳しさ(`.husky` 配下かどうかまで判定)に揃いました
- **[auto]** 検査 1(単一ソースの空洞化)に「`baseBranch` が `protectedBranches` に含まれるか」「`allowedPrefixes` が保護ブランチ名に前方一致する接頭辞(`main` や空文字列)を持たないか」を追加しました。`protectedBranches` を差し替える・`allowedPrefixes` に保護ブランチ名相当を紛れ込ませる、という「全層が正常動作したまま保護が消える」2 パターンを検出します
- **[manual]** `AGENTS.md` §1-3 と `.codex/skills/degraded-mode-ticket/SKILL.md` 検査3 の散文から `git config --get core.hooksPath` を自分で読んで判断する手順を削除し、`bash .claude/scripts/check-guard-integrity.sh hooks-path` を実行する導線に統一しました。**取り込む側の作業**: これらのファイルをテンプレートから独自にカスタマイズしていた場合、`core.hooksPath` を直接比較する記述が残っていないか確認してください

## 2026-08-31

**モード C 復帰検査に `.git/config` のホストコマンド実行ベクタ検査(D2.5)を足した(Issue #58)。** 縮退モードは `.git` を writable_roots に渡すため、委託先が `.git/config` を丸ごと書けます。D1(`core.hooksPath`)と D2(`.git/hooks/` 直書き)は見ていましたが、`core.fsmonitor` のように**復帰検収より先に発火する**キーが検査対象外でした。

- **[auto]** `check-guard-integrity.sh degraded` に D2.5 を追加。`core.fsmonitor` / `core.sshCommand` / `core.pager` / `core.editor` / `sequence.editor` / `core.gitProxy` / `credential.*.helper` / `url.*.insteadOf|pushInsteadOf` / `filter.*.clean|smudge` / `diff.*.command` / `merge.*.driver` / `include.path` / `includeIf.*.path` / `alias.*`(`!` 形式のみ)を**値ごと報告**します。D1/D2 と同じく**報告のみで停止はしません**
- **[auto]** 検査範囲は `--local` のみです。devcontainer は `--global` / `--system` に `credential.helper` の `!` 形式を既定で置いているため、混ぜると平常運用で必ず誤爆します(実測)
- **[auto]** `alias.*` は `!` 形式だけが対象です。git は組み込みサブコマンドを上書きするエイリアスを無視するため(実測)、`!` の無いエイリアスは既存コマンドの乗っ取り経路になりません
- **[manual]** **モード C を運用しているプロジェクトは、push の前に `bash .claude/scripts/check-guard-integrity.sh degraded` を回す運用に変えてください。** `core.sshCommand` / `credential.helper` は push の瞬間に発火するため、Claude 復帰時の検収まで待つと検査が間に合いません(§12.3 手順 7 / `.claude/rules/mode/degraded.md` に反映済み)

**委託禁止領域を「実行される実体」から 3 系統に広げ、適用漏れ 3 系統を塞いだ(Issue #56)。** 保護ブランチ検査は判定ロジックを 1 本化して守ってありましたが、**その判定が読むデータ**(`.claude/branch-policy.json`)は禁止領域に無く、委託先が `protectedBranches` を差し替えても出口検査に掛かりませんでした。全層が正常に動作したうえで素通しする形になるため、層を増やしても防げない経路です。同じ理屈で、司令塔のコンテキストへ本文が注入される `.claude/rules/` と `CLAUDE.md` も保護されていませんでした。

- **[auto]** `FORBIDDEN_PATHS` に 5 項目を追加: `.claude/branch-policy.json` / `.claude/rules/` / `CLAUDE.md` / `.mcp.json` / `.codex/`。`AGENTS.md` §4 のマーカー内と `CLAUDE.md` の説明も同時に更新済みです
- **[auto]** 原則を 3 系統に整理しました。**実行される実体**(scripts / hooks / settings.json / `.husky/*` / workflows)、**コンテキストへ注入される実体**(rules / CLAUDE.md / AGENTS.md / .mcp.json)、**全層が読む判定データ**(branch-policy.json)。`skills/` / `commands/` / `agents/` / `docs/` の除外は据え置きです
- **[auto]** `.claude/rules/` はディレクトリ単位です。`lead/` と `mode/` だけを個別列挙すると、`CLAUDE.md` 経由で全サブエージェントに載る `spec-driven.md` が漏れます
- **[manual]** ⚠️ **委託先が `CLAUDE.md` / `.claude/rules/` を編集する運用をしていた場合、その委託は `failed` / `exit 2` になります。** ルールへの追記はもともと司令塔の仕事(`context-management.md`)なので実害は無いはずですが、**取り込む側の作業**: `/kickoff` 以外で Codex に `CLAUDE.md` を書かせる手順を作っていないか確認してください

## 2026-08-30

**econ モードの効果測定の設計を確定し、記録漏れを防ぐ 1 行を注入文に入れた(Issue #47)。** `delegation-policy.md` は委託粒度の閾値を「実測で上下させる」と宣言していますが、モード B の週枠寿命の比較は `decisions.jsonl` に「未実施」と記録されたままでした。宣言だけがあって実測が回らない状態は、#37 が機械化で塞いだ「散文の運用ルールは守られない」と同じ構造です。

- **[auto]** `docs/template-dev/econ-measurement.md` を新規追加(何を・いつ・どう記録し、どの条件で結論を出すか)。記録は **1 チケット 1 点**で、週枠使用率は週次リセットまで単調増加するため、同じ週の隣接エントリの差で per-ticket の消費が出ます。着手時の値を持ち越す必要がないので、セッションが分割される econ モードでも落ちません。`docs/template-dev/` はテンプレート側の開発記録(manifest の `never`)なので同期されません — 設計の背景を読みたいときだけテンプレートリポジトリを参照してください
- **[manual]** `.harness/decisions.jsonl` に任意フィールド `usage`(`mode` / `weekly_pct` / `week_resets_at` / `measured_at` / `raw`)を足せるようにした。**既存キーは変更していない**ため、CI(`check-record-hygiene.sh` 検査2)が見る `"issue": N` の前提は変わりません。`usage` が無い行があってよく、**CI の必須項目にはしません**(`/usage` を読めない経路で全 PR が落ちるため)。`.harness/` は manifest の `never`(`/sync-template` が触らない)なので**自動では反映されません**。**取り込む側の作業**: 次に `decisions.jsonl` を書くときから `usage` を足す
- **[auto]** **`.claude/rules/lead/delegation-policy.md`「実測の記録」の 1 行に `/usage` の週枠使用率を足した**(行数は増えていません)。`usage` のリマインドをここに置くのは、モード別の注入文(`mode/econ.md`)だけだと **normal モードのサンプルが構造的に溜まらず、モード比較が永久に「サンプル不足」で止まる**ためです
- **[manual]** **`.claude/rules/mode/econ.md` の「司令塔の作法」に作法5 を 1 行足した。** econ モードのセッションで `decisions.jsonl` を書く前に、`/usage` の週枠使用率をユーザーへ 1 行で尋ねて記録します(答えが無ければ `null` のまま進み、PR は止めません)。**取り込む側の作業**: econ モードを使っているプロジェクトでは、次回の econ 運用時にこの記録が 1 件残ることを確認する

**中断された委託が残す「出口検査が見えない穴」を、残置 record 検出時に機械確認するようにした(Issue #46)。** `status=running` のまま残った record(強制終了の疑い)はこれまで警告のみで、次の委託の BEFORE スナップショットが禁止領域の改ざんを「元からあったもの」として取り込み、以後恒久的に検出できなくなる穴がありました。

- **[auto]** 入口検査5-5 が `status=running` の残置 record を見つけたとき、委託禁止領域(`FORBIDDEN_PATHS` / `PROJECT_FORBIDDEN_PATHS`)に未コミットの変更(`git diff HEAD` または未追跡ファイル)があれば `exit 2` で止まるようになりました(5-5b)。pathspec は `GIT_LITERAL_PATHSPECS=1` と `:` 始まりの除外で正規化しており、`AGENTS.md` 由来の断片に git の magic pathspec が紛れても検査が無音で空振りしません。**誤爆条件**: 司令塔がハーネス層を改修中に過去の残置 record が残っていると止まります。解除は `bash .claude/scripts/codex-run.sh set-status <id> failed` で record を実態に合わせるだけでよく、編集中の差分を捨てる必要はありません

**run record を読む `rec_field()` の二重実装を共有ファイルに集約した(Issue #45)。** `delegate-codex.sh` と `codex-run.sh` に同じ十数行がコピーされており、jq 不在環境で再入防止がフェイルオープンする Critical(sed フォールバックの末尾カンマ)を**両方で直した実績**がありました。同じバグを 2 回直した時点で「小さいから複製の方が安い」という前提は崩れています。

- **[auto]** `.claude/scripts/lib-record.sh` を新規追加し、両スクリプトが `source` するようにした(#45)。関数の挙動は変えていないので、`/sync-template` の上書きだけで完結します
- **[auto]** `delegate-codex.sh` の自己コピー exec(#15)は、`lib-record.sh` も同じ一時ディレクトリへ**一緒にコピー**して自身の隣から `source` するようにした。共有ファイルをリポジトリ側から読むと「実行中に委託先が書き換えられるファイル」が増え、自己編集ハザード対策に穴が開くためです。コピーに失敗した場合はリポジトリ側へフォールバックし、警告を出します(委託は止めません)
- **[auto]** 共有ファイルが 1 つも見つからない場合は**フェイルクローズ**(`delegate-codex.sh` は `exit 2`、`codex-run.sh` は `exit 2`)。`rec_field` は入口検査5-5 の再入防止が使うため、未定義のまま進むと検査が静かに素通しします
- `lib-record.sh` は `FORBIDDEN_PATHS` の `.claude/scripts/`(ディレクトリ単位・#40)に**自動的に含まれる**ため、委託禁止領域の一覧・`AGENTS.md` §4・`CLAUDE.md` の更新は不要です
- **[manual]** **`.claude/scripts/lib-*.sh` を「source 専用ライブラリ」の命名規約にした**(#45)。CI(`ci.yml` の `harness-integrity`)と SessionStart hook の実行ビット検査が、`lib-*.sh` にだけ**逆の要件**(実行ビットが無いこと・shebang が無いこと・git index が `100644`)を課します。「`lib-` に改名すれば実行ビット検査を逃れられる」抜け道を塞ぐため、免除ではなく別の縛りを課す形にしています。**取り込む側の作業**: `.claude/scripts/` に `lib-` で始まる名前の**実行されるスクリプト**がある場合は改名する(そのままだと CI が落ちます)

## 2026-08-29

**委託禁止領域に CI/hook の判定実体を含めた(Issue #40)。** `.github/workflows/` は守られていたのに、**そのワークフローが `bash` で呼ぶ判定スクリプトの本体は守られていませんでした**。定義を守っても、定義が実行する実体が書き換え可能なら防御は成立しません。

- **[manual]** ⚠️ **`FORBIDDEN_PATHS` に `.claude/scripts/` / `.claude/hooks/` / `.claude/settings.json` を追加した**(#40)。個別ファイル列挙(`delegate-codex.sh` / `check-protected-branch.sh`)は**ディレクトリ単位**に置き換え。#37 で足した `check-record-hygiene.sh` は冒頭に `exit 0` を 1 行書くだけで全 PR の記録漏れ検査を無効化できる状態でしたし、`check-guard-integrity.sh` を骨抜きにすると「husky 層が消えたことに気づけない」状態になります。`.claude/` 全体は禁止にせず、対象は**実行される実体**(scripts / hooks / settings.json)に限っています(`skills/` / `commands/` / `agents/` / `rules/` は従来どおり委託可)。**取り込む側の作業**: `AGENTS.md`(`merge` 区分)§4 のマーカー内に `.claude/scripts/` / `.claude/hooks/` / `.claude/settings.json` の 3 項目を足し、既存の `.claude/scripts/delegate-codex.sh` / `.claude/scripts/check-protected-branch.sh` の行を整理する。`CLAUDE.md`(`never` 区分)の禁止領域リストにも同じ変更を反映する
- **[auto]** ハーネス改修を Codex に委託していたプロジェクトでは、`.claude/scripts/` 配下を触る impl 委託が今後 `status=failed` / `exit 2` で止まります。ハーネス改修はもともと委託しない方針(`.claude/rules/lead/delegation-policy.md`)なので、通常の運用で失うものはありません

**CHANGELOG 検査のトリガに `.github/workflows/` を追加した(Issue #41)。** `/sync-template` の同期対象(`owned`)にワークフロー 5 本が載っているのに、検査のトリガは 4 項目のままでした。**ワークフローだけを変更した PR は CHANGELOG 未更新でも緑**で、#37 が塞いだはずの穴が同期対象の一部で残っていました。

- **[auto]** **`check-record-hygiene.sh` の `CHANGELOG_TRIGGERS` に `.github/workflows/` を追加した**(#41)。今後は `.github/workflows/` 配下だけを変更した PR も CHANGELOG の追記が必要になります(不要な変更ならラベル `no-changelog` で外せます)。`.github/` 全体ではなく `workflows/` に絞っており、`.github/ISSUE_TEMPLATE/` 等は対象外です。あわせて、**manifest の `owned` / `merge` に面を足すときはこの配列も同時に直す**という運用をスクリプト側のコメントに明記しました(manifest からの動的生成はしません)

**モード C(縮退)復帰時のガードレール健全性を機械検査するようにした(Issue #42)。** 縮退モードは `delegate-codex.sh` を通らない唯一の経路で、入口検査も出口検査も掛かりません。さらに `.git` を `writable_roots` に渡す設計のため、**委託先自身が `core.hooksPath` を書き換えて husky 層を無効化できる**状態でした。復帰時検収に機械的な確認ステップが無く、人間が読み飛ばせば検出機会が消えます。

- **[auto]** **`check-guard-integrity.sh` に `degraded` サブコマンドを追加した**(#42)。`core.hooksPath` が `.husky` 配下を指しているか / `.git/hooks/` に直書きフックが無いか / `Codex-authored` コミットの差分が委託禁止領域に触れていないかを検査します。**引数なしの既存呼び出し(SessionStart hook / CI の `harness-integrity`)の挙動は変わりません**(CI の fresh checkout では `core.hooksPath` 未設定が正常なため、既定に混ぜると恒常的に赤くなる)
- **[auto]** **`delegate-codex.sh` に `--print-forbidden` を追加した**(#42)。委託禁止領域の一覧を 1 行 1 パスで出力するだけの read-only モードです。`check-guard-integrity.sh degraded` がこれを読むことで、パス一覧の単一ソースが `delegate-codex.sh` のまま保たれます(配列は複製していません)。あわせて `FORBIDDEN_PATHS` の定義位置を入口検査より前へ移しました(codex CLI が無くても一覧を引けるようにするため)
- **[auto]** `.claude/rules/mode/degraded.md` の復帰手順の先頭に上記コマンドを組み込み、`.codex/skills/degraded-mode-ticket/SKILL.md` §5 に「`.git/` 配下を改変しない」を明記しました

**`verify-probe` のホスト実行に形式検査と環境遮断を入れた(Issue #43)。** 入口検査3 は `AGENTS.md` の `<!-- verify-probe: ... -->` から抽出した文字列を、そのままホスト上の `bash -c` に渡していました。`AGENTS.md` は `merge` 区分でプロジェクトが自由に書き換えるため、悪意または誤りのある内容がそのままホスト実行に化ける経路が残っていました。

- **[auto]** `delegate-codex.sh` に `probe_format_reason()` を追加し、**プローブ全体が 3 つの固定形(`<cmd> <verify>` / `npx --no-install <pkg> <verify>` / `python -I -m <module> <verify>`)のいずれかに完全一致すること**を機械検査するようにしました(#43)。`npm install ... --version` のようなサブコマンド付きは通りません(ホスト側にはネットワークがあり、依存取得と postinstall がそのまま走るため)。形式外は**実行せず警告のみ**で委託は続行します(フェイルオープン)。形式適合時は実行内容を stderr に表示したうえで `env -i` + 最小の環境変数(`PATH` / `HOME` / `TMPDIR`)で実行し、親プロセスの環境変数に依存した意図しない挙動を遮断します。なお `python -m` 形は `-I` を必須にしています(付けないとカレントディレクトリのファイルがモジュールとして読まれるため)。形式検査が守るのは「文字列が任意コマンドに化けること」までで、ワークツリーに置かれた実行ファイル(`node_modules/.bin/` 等)は出口ハッシュ検査と `check-guard-integrity.sh degraded` の担当です。確認フラグは `--version` に限定しています(ダッシュなしの `version` は多くの処理系で「カレントディレクトリの `version` というファイルを実行する」意味になり、実測で任意コード実行に到達しました。`java -version` のみ従来形も通します)。許可コマンドは実測で「ワークツリーの設定ファイルに影響されない」ことを確認した 8 つ(`node` `npm` `npx` `python3` `ruby` `java` `rake` `gradle`)に限定しました(`python` は未検証のため除外)。`yarn`(`.yarnrc` の `yarn-path`)・`mvn`(`.mvn/jvm.config`)・`pnpm`(`package.json` の `packageManager`)は、`--version` でもワークツリーの設定で実行されるコードが変わることを実測で確認したため除外しています。他の処理系のプロジェクトではプローブが警告つきでスキップされます(委託は止まりません)
- **[manual]** ⚠️ `AGENTS.md`(`merge` 区分)§2 に形式制約の説明を追記しました。独自の `verify-probe` を書いているプロジェクトは、取り込み後に形式適合を確認してください(適合しない場合は実行されず警告が出るだけで委託自体は止まりません)

**PostToolUse の lint hook を編集ファイル単位に絞った(Issue #44)。** 編集のたびに全体 eslint と
全体 tsc を回し、`tail -20` の中身が毎回コンテキストへ載っていました。

- **[auto]** `.claude/scripts/lint-on-edit.sh` を書き換え。eslint は編集した 1 ファイルだけに掛け、
  呼び出しを `npm run` から `node_modules/.bin/eslint` へ変更(実測 25.5 s → 14.2 s。差分の大半は
  npm ラッパの起動コスト)。型チェックは全体検査を維持したまま、**出力を編集ファイルの行だけに絞り、
  それ以外は件数 1 行に畳む**(型は 1 ファイルでは決まらないため検査は絞れないが、
  コンテキストに載る量は絞れる)
- **[auto]** 同 hook の多重起動対策を、自前の `mkdir` ロックから **`flock` による待ち合わせ**に変更。
  旧実装は実行中に入った編集を**無検査で捨てて**おり、連続編集の最後の 1 本が常に無検査だった。
  `flock` はプロセスが強制終了されてもカーネルが解放するため、`timeout` で kill されたロックが
  残り続けて以降ずっと無検査になる事故も起きない(`flock` が無い環境ではロックなしで実行する)

## 2026-08-27

**チケット完了時の記録漏れを CI で機械的に検出するようにした(Issue #37)。** この CHANGELOG は #20〜#29 の 8 件連続で追記されず、`/sync-template` を使う側が `[manual]` 項目に気づけない状態になっていました。散文の運用ルールだけでは 2 度守られなかった(4 回連続 → 8 回連続と悪化した)ため、機械的な層を足しています。

- **[manual]** **記録漏れの CI 検査を追加した**(#37)。`.github/workflows/record-hygiene.yml`(新規)と `.claude/scripts/check-record-hygiene.sh`(新規)が、PR に対して 2 つの検査を行い、漏れがあれば **PR を落とします**(annotation + Job Summary に理由が出ます)。**取り込む側の作業**: リポジトリに逃げ道ラベルを 2 つ作る — `gh label create no-changelog` と `gh label create no-decision-record`。作らないとラベルを付けられず、検査を外せません
  - **検査1(CHANGELOG)**: `.claude/` / `.husky/` / `.codex/` / `AGENTS.md` を変更した PR で `docs/template-dev/CHANGELOG.md` が未更新なら落とす。逃げ道は `no-changelog`
  - **検査2(decisions.jsonl)**: `ticket` ラベル付き Issue を `Closes #N` でクローズする PR で `.harness/decisions.jsonl` に `"issue": N` の行が無ければ落とす。逃げ道は `no-decision-record`
  - **Codex 委託を使わないプロジェクトでは検査2 は実質空振りします**(`.harness/decisions.jsonl` が無い場合は「記録できません」で落ちるため、使わないなら `no-decision-record` を常用するか、ワークフローを削除してください)
- **[auto]** `.claude/rules/lead/delegation-policy.md`「実測の記録」に、**記録を書くのは PR を出す前**(検収が終わり往復回数と指摘数が確定した時点)であることと、逃げ道ラベルの表を明記した(#37)。従来の「チケット完了時」は実運用と食い違っており、マージ後に回すと記録そのものが落ちていました

## 2026-08-26

**委託経路そのものの堅牢化(Issue #20〜#29)。** 2026-08-25 の実装レビュー(`docs/template-dev/codex-harness-review-20260825.html`)で挙がった穴を塞ぐ回。対象は「委託先が触れる境界」(出口検査・禁止パス・環境変数・denylist)と「記録の増え方」(run record)で、**新機能ではなく既存の委託経路の防御と誤検出の修正**です。**Codex を使わないプロジェクトには影響しません**。

- **[manual]** ⚠️ **impl 委託に出口検査を追加した**(#20)。委託の前後で禁止パスの内容ハッシュを突き合わせ、差分があれば委託全体を `status=failed` / `exit 2` にする(委託先の報告内容にかかわらず)。あわせて禁止パスに **`AGENTS.md` / `.github/workflows/` / `.harness/mode` / `.harness/codex-runs/`** を追加した。この 4 つは**サンドボックスの中で書けてしまうが、書いた結果が後でサンドボックスの外で実行される**類型 — `AGENTS.md` の `<!-- verify-probe: ... -->` は次回委託時にホスト上の `bash -c` へそのまま渡り、`.github/workflows/` は非 fork PR で `CLAUDE_CODE_OAUTH_TOKEN` に触れられる。**取り込む側の作業**: `AGENTS.md`(`merge` 区分)§4「委託禁止領域(パス)」に、テンプレート側の **(a) 機械検査される旨の一文**と **(b) マーカー内の 3 項目(`AGENTS.md` 自身 / `.github/workflows/` / `.harness/*`)** を手で足す。`CLAUDE.md`(`never` 区分)の禁止領域リストにも同じ 3 項目を足す
- **[manual]** **委託送信禁止リストにトークン置き場の定番パターンを追加した**(#21)。有効パターンは **10 → 21**。追加分は `.npmrc` / `.pypirc` / `.netrc` / `.git-credentials` / `*-service-account*.json` / `*.tfstate`(+ `.backup`)/ `*.sqlite` / `*.sqlite3` / `*.db` / `dump*.sql`。**テンプレート既定が npm スタックなのに、認証トークンの定番置き場である `.npmrc`(`_authToken`)が入っていなかった**。あわせて**誤検出を許容する層**であること(中身を見ずファイル名だけで止めるため、機密を含まない `.npmrc` でも止まる。内容を確認したうえで `CODEX_DELEGATE_ACK_SECRETS=1` を付けて再実行すれば通せる)を冒頭コメントに明記した。**取り込む側の作業**: `.claude/codex-denylist.txt`(`merge` 区分)にテンプレート側の追加パターンをマージする。npm 以外のスタックなら、自分のスタックのトークン置き場に読み替えて足す
- **[auto]** **read-only 委託(`explore` / `review`)の run record を auto-accept するようにした**(#22)。「検収して accept する」対象が残るのは impl だけなのに全モードが `accepted: false` で記録され、`codex-run.sh pending` が SessionStart のたびにそれを注入し続けていた(7 日経っても消えない)。**コンテキストを削るための read-only 委託が、毎セッションの固定コンテキストを単調増加させていた**。異常終了(`failed` / `unavailable` 等)はモードによらず従来どおり `accepted: false` で pending に出る
- **[manual]** ⚠️ **委託先へ渡る環境変数を許可リスト方式にした**(#23)。`codex exec` を**親プロセスの環境ごと継承**して起動していたため、`LOCAL_GH_TOKEN`(gh CLI のトークン)や `CLAUDE_CODE_MESSAGING_TOKEN` が委託先へそのまま渡っていた(devcontainer で実測)。入口検査1 は `find .` でリポジトリ内しか走査しないので、**これらは検査対象にすらなっていなかった**。`env -i` + 明示した変数だけを渡す形に変更し、加算のみの逃げ道として `CODEX_DELEGATE_ENV_ALLOW`(カンマ区切りの変数名)を用意した(**全バイパスは置かない**)。**取り込む側の作業**: (a) `.claude/codex-denylist.txt`(`merge` 区分)冒頭の「ここが唯一の層」を、テンプレートの新しい文面(**守るのはワークツリー内だけ**。ホーム配下の `~/.config/gh/hosts.yml`・`~/.claude/` は検査対象にすらならず sandbox でも止められない)に差し替える。(b) 独自のツールチェーンが必要とする環境変数があって委託が動かなくなった場合のみ、`CODEX_DELEGATE_ENV_ALLOW` で足す
- **[auto]** **impl 入口検査の穴を 2 つ塞いだ**(#24)。**5-1**: target が `.steering/` 配下に限定されておらず、外の任意ディレクトリでも `design.md` + `tasklist.md` さえあれば通っていた(run record の `steering` と SessionStart の現在地判定が静かにずれる)。**5-5**: 再入防止が「同一ステアリング」しか見ておらず、別ステアリングへの並行 impl 委託が素通りしていた → 判定軸を `mode=impl` に変え、`delegation-policy.md` の「並行数は 1 本まで」が**機械的に効く**ようになった。read-only の `explore` / `review` は従来どおり並行可
- **[auto]** **成果実在確認の誤検出を直した**(#27)。`git status --porcelain` は**新規の未追跡ディレクトリを 1 行に畳む**ため、その配下にだけファイルを作る委託(`.steering/` の新規作成、新規モジュールを 1 ディレクトリにまとめて作るタスク)が、成果が確実にあるのに `status=failed` / `exit 2`(「exit 0 だが成果物が確認できない」)になっていた。**フェイルオープンではなくフェイルクローズ側の誤検出** = 正常な委託が失敗と誤判定される経路。`-uall` を付けて畳まないようにした(走査量の増加は未追跡 5000 ファイルで +0.02 秒と実測)
- **[manual]** **出口検査が `AGENTS.md` のプロジェクト固有パスも見るようになった**(#28)。#20 の出口検査はスクリプト内の**汎用項目だけ**を見ており、`/kickoff` フェーズ4 が `AGENTS.md` §4 のマーカー内へ書く**プロジェクト固有パス(認証・決済・データ移行など)は散文の指示だけ**で守られていなかった — テンプレート自身は固有パスを持たないため表面化しないが、**`/kickoff` を通った下流のプロジェクトでは初日からこの状態**になる。委託の開始時にマーカー内のバックティック囲みを 1 回だけ抽出し、汎用項目とマージして検査する(委託中にマーカーを書き換えても、その回の検査対象は開始時点のまま)。**取り込む側の作業**: (a) `AGENTS.md`(`merge` 区分)のマーカー直下の説明文を、テンプレートの新しい文面(機械検査される旨 + 表記ルール)に差し替える。(b) マーカー内には**実在するパス**を `src/auth/` または `src/auth/**` の形で書く。**実在しない語をバックティックで囲んでも無視される**ため、抽出はされるのに 1 件も保護されない状態になりうる
- **[auto]** **run record のローテーションを整備した**(#29)。`codex-run.sh prune`(`--dry-run` / `--keep N`(既定 20)/ `--include-unaccepted`)。**未検収(`accepted != true`)・実行中(`status=running` かつ pid 生存)・直近 N 本は既定で残す**。削除は `<id>.json` / `<id>.log` / `<id>.last.txt` の 3 点セット単位。`delegate-codex.sh` は起動時に件数が閾値を超えていたら**警告だけ**出す(自動削除はしない)。#20 で `.harness/codex-runs/` が出口検査の対象になり、**run 数に比例して委託 1 本あたりのハッシュコストが線形に増える**ようになったため

## 2026-08-25

Codex 併用ハーネスの**モード C(縮退運用)** と**チケット丸ごとの委託**、および委託経路自身の堅牢化。これで段階0〜6 がすべて揃った。**Codex を使わないプロジェクトには影響しません**(ラベルを付けなければ従来どおり Sonnet fork で実装フェーズが回る)。

- **[manual]** **`.codex/skills/degraded-mode-ticket/` を新設**(新規 / `owned` 区分)。**モード C = Claude の枠が尽きている期間**に、Codex が `delegate-codex.sh` を経由せず単独でチケット 1 件を計画〜コミットまで完走する手順書。入口検査 5 項目(モード確認 / 保護ブランチ / `core.hooksPath` / 依存プローブ / **`.git` に書けるか**)を Codex 自身に実行させる。**取り込む側の作業**: `.claude/template-manifest.json`(`merge` 区分)の `owned` から **`.codex/prompts/` を削除**し、代わりに **`.codex/skills/` を追加**する。`.codex/prompts/` は Codex CLI に存在しないことが実機で確定したため登録を撤回した(2026-08-20 の項の記述はこの時点のもの)
- **[manual]** ⚠️ **モード C は `.git` が書けないと成立しない**。Codex の `workspace-write` sandbox は既定で `.git` を読み取り専用にするため、`git add` の時点で失敗する(実機確認済み)。モード C で起動するときだけ `codex --sandbox workspace-write -c 'sandbox_workspace_write.writable_roots=[".git"]'` を使う。**`.codex/config.toml` には書かないこと**(モード A・B はコミット禁止の運用で、`.git` が書けないこと自体が防衛線)。**取り込む側の作業**: 縮退運用を使う場合のみ、この起動コマンドを人間の手順として控えておく
- **[manual]** **`AGENTS.md` に「1-5. `.git` に書き込めるか」と「委託禁止領域(パス)」の節を追加**(`merge` 区分)。後者は `<!-- kickoff:delegation-forbidden-paths -->` 〜 `<!-- /kickoff:delegation-forbidden-paths -->` のマーカーで囲ってあり、**中の汎用項目(`delegate-codex.sh` / `.husky/*` / `codex-denylist.txt`)は消さずにプロジェクト固有のパスを追記する**(消すとプロダクト側でガードレール保護が最初から欠落する)。**取り込む側の作業**: テンプレート側の該当節を自分の `AGENTS.md` に手で足す
- **[manual]** **`delegate:codex` ラベルを導入**。付いている Issue は「tasklist を分割せず 1 回の委託で全体を流す」、無ければ「3 項目前後のバッチに割り、各バッチの検収を通してから次を委託する」。判定基準の全文は `.claude/rules/lead/delegation-policy.md`(新規 / `owned`。**司令塔にのみ注入**され、サブエージェントには載らない)。`/setup-tickets` が発行時に、`/next-ticket` が着手時に判定する。**取り込む側の作業**: 既にチケット運用中のプロジェクトは `gh label create delegate:codex --color 6F42C1 --description "Codex にチケット丸ごと委託する"` を 1 回実行する(`/setup-tickets` を再実行する場合は不要)
- **[manual]** `CLAUDE.md`(`never` 区分)に「Codex への委託禁止領域(パス)」節を追加した。**取り込む側の作業**: 自分の `CLAUDE.md`「プロジェクト固有ルール」節に、委託しないパス(ガードレール本体・`delegate-codex.sh`・`codex-denylist.txt` + 自プロジェクトの認証/決済/データ移行のモジュール)を列挙する
- **[auto]** ⚠️ **`delegate-codex.sh` の自己編集ハザードを塞いだ**。bash はスクリプトを逐次読み込みするため、実行中に自分自身のファイルが書き換わると**無関係な行で構文エラーになって死ぬ**。委託先がハーネス層を触るのはテンプレート開発では常態なので、起動直後に自身を一時ディレクトリへコピーして `exec` する形にした(`exec` は PID もカレントディレクトリも変えないため `$$` を使う run record はそのまま成立する)。コピーに失敗しても委託は止めない(堅牢化の層であって安全検査ではないため、ここだけフェイルオープン)。`CODEX_DELEGATE_NO_SELF_COPY=1` は**再現テスト専用の逃げ道**で、設定すると警告を出したうえで旧挙動に戻る
- **[auto]** `/kickoff` フェーズ0 に**ブランチ保護が使えるプランかの確認**を追加(`gh api repos/{owner}/{repo}/rulesets` が 403 なら 3 択を提示)。ローカルのガードレールはセキュリティ境界ではなく、権限境界は GitHub 側のルールセットで張る必要があるため

## 2026-08-24

**実装委託(段階3)とモード B(段階4)**。ここから Claude の枠が実際に温存され始める。

- **[auto]** **`delegate-codex.sh` に `impl` モードを追加**(`--sandbox workspace-write`)。終了コード契約は `0` 完了 / `1` 判断待ち / `2` 失敗 / `3` Codex 利用不可 / `4` レート上限 / **`5` 計画が未完成**(`design.md` が `<!-- status: ready -->` でない)。割り込みは 130 / 143 で、これは契約とは別枠(「委託の結果」ではなく「委託が中断された」)
- **[auto]** ⚠️ **`codex exec` の `exit 0` は「タスクが成功した」を意味しない**(実測。sandbox が起動せず何一つ達成できなかった委託が `exit 0` を返した)。`impl` では事前スナップショット(作業ツリー・HEAD・`tasklist.md` の `[x]` 数)と突き合わせ、**どれも変化していなければ `exit 2` に落とす**。サマリーの文面から成否を推測しないこと
- **[auto]** **`.claude/scripts/codex-run.sh` を新設**。run record(`.harness/codex-runs/*.json`)の `list` / `pending` / `show` / `accept` / `set-status`。**検収が通ったら `accept` する**運用(立て忘れると未検収の記録が残り続ける)
- **[auto]** **`.claude/scripts/harness-mode.sh` を新設**。ハーネスモード(`normal` / `econ` / `degraded`)の唯一の読み取り経路。読む順序は `CODEX_HARNESS_MODE` > `.harness/mode` > `normal` に固定。読み手が Claude 側と Codex 側の 2 系統あるため、判定の実体をここに集約する
- **[auto]** **`.claude/rules/mode/econ.md` / `degraded.md` を新設**。SessionStart hook が**モードが `normal` 以外のときだけ**注入する(既定モードで毎回数十行を注入すると、モード B が節約しようとしているコンテキストそのものを食う)
- **[auto]** SessionStart hook に **未検収の Codex 委託の注入**を追加。`/clear` や resume だけでなく通常の `startup` でも出す(モード B の既定経路は「司令塔がセッションを閉じる → 人間が委託 → 新セッションを開く」であり、再開が `/clear` とは限らないため)
- **[auto]** `/add-feature` ・ `/next-ticket` ・ `/fix-issue` の実装ステップを**委託経路**に改訂。**既定は Codex、`exit 3` を一度受けたらそのセッションは以降ずっと `implement-ticket`(Sonnet fork)**(恒久フォールバック。同じ環境欠落を毎回試さない)
- **[manual]** **モード B(節約)の運用を追加**。`design.md` を書き切ったらセッションを閉じ、検収は CI に預け、**PR は `--draft` で積んでマージしない**。draft は作法ではなく節約の実体で、`claude-code-review.yml` は `draft == false` のときだけ走る一方 `ci.yml` は draft でも走る(同一 PR で実測)。**取り込む側の作業**: `.harness/mode` は gitignore 済みなので、使うときは人間が `echo econ > .harness/mode` する。**Claude には書き換えさせない**(切替の宣言は人間の担当)
- **[auto]** `claude-code-review.yml` / `claude.yml` に**スキップの可視化**を追加。`CLAUDE_CODE_OAUTH_TOKEN` 未設定のときは run の annotation と Summary に「未実行」を出す。**ジョブの `success` はレビュー通過を意味しない** — この取り違えは実際にドキュメントの誤記録を生んでいる

## 2026-08-23

Codex 併用ハーネスの**前提環境(段階0)**。Codex を使わないプロジェクトには影響しません。

- **[manual]** **`.claude/codex-denylist.txt` を新設**(新規 / `merge` 区分)。委託前の機密ファイル検査のパターンを、スクリプトから**プロジェクト側に外出し**した。**このファイルが無いと `delegate-codex.sh` は `exit 3` で止まる**(検査が成立しないなら委託しない = フェイルクローズ)。**取り込む側の作業**: テンプレート側をコピーし、自分のプロジェクトの機密ファイル名を足す。**モジュールパス(委託禁止領域)をここに書かないこと** — 該当ファイルが存在するだけで全委託が止まる、性質の違う層
- **[manual]** ⚠️ **`.devcontainer/devcontainer.json` に `"runArgs": ["--security-opt", "seccomp=unconfined"]` を追加**。Docker 既定の seccomp プロファイルが非特権 user namespace を禁じるため、**Codex の sandbox(bubblewrap)が起動せずファイルを 1 つも読めない**(委託は完走するのに中身が空、という最も気づきにくい壊れ方をする)。**取り込む側の作業**: `.devcontainer/` は `never` 区分なので手で足し、リビルド後に `codex sandbox echo hello` が exit 0 になることを確認する
- **[manual]** **`.devcontainer/post_create.sh` に Codex CLI の導入を追加**。単純な `npm install -g @openai/codex` では不足で、プラットフォーム別バイナリが optional dependency のため**取得失敗が握り潰され実行時に落ちる**。成否は npm の終了コードではなく `codex --version` で判定し、失敗したら 1 回再試行する。**取り込む側の作業**: `never` 区分なので手でコピーする。認証(`codex login`)は**初回とリビルドのたびに人間が実行**する(`~/.codex` は永続化しない方針)

## 2026-08-20

Codex 併用ハーネスの**最小構成(読み取り委託)**。実装委託(書き込み)はまだ入っていないので、取り込んでも既存の運用は変わりません。**Codex を使わないプロジェクトは、取り込んでも何も起きません**(`delegate-codex.sh` は `codex` コマンドが無ければ exit 3 で止まるだけ)。

- **[manual]** ⚠️ **`AGENTS.md` を新設**(新規ファイル / `merge` 区分)。Codex は `CLAUDE.md` も hooks も permissions も読まないため、**規約の写像がこのファイルだけ**になる。検証コマンド・モード別の禁止事項・スコープガード・コミットメッセージ規約・起動時手順を含む。**取り込む側の作業**: `merge` 対象なので手作業。テンプレート側の `AGENTS.md` をコピーし、**「2. 検証コマンド」の表と `<!-- verify-probe: ... -->` の 1 行を自分のスタックに書き換える**(既定は Node.js / TypeScript)。`verify-probe` は「依存が入っているか」だけを見る速いコマンドで、`--no-install` 相当を外さないこと(sandbox はネットワーク無効なので取得を試みた時点で失敗する)
- **[manual]** **`.codex/config.toml` を新設**(新規ファイル / `merge` 区分)。sandbox は `workspace-write` + ネットワーク無効が既定。**このファイルは防衛線ではない** — CLI フラグが優先し、プロジェクトを untrusted にすると `.codex/` レイヤは丸ごと読まれない。位置づけは「人間が `codex` を直接叩くときの既定」。**取り込む側の作業**: テンプレート側をコピーし、`model` / `model_reasoning_effort` を使うなら自分で設定する
- **[auto]** **`.claude/scripts/delegate-codex.sh` を新設**。Codex への委託経路の唯一の入口。今回入るのは読み取り専用の 2 モード(`explore` / `review`)だけで、`impl` / `fix-ci` / `--background` は明示的に「段階3 で実装します」と返す。終了コード契約は `0` 完了 / `2` 失敗 / `3` Codex 利用不可(恒久フォールバック)/ `4` レート上限(一時フォールバック)。**`3` と `4` を混ぜないこと**(前者は環境の欠落、後者は枠切れで回復手段が違う)
- **[auto]** `delegate-codex.sh` は**委託前に機密ファイル**(`.env` / `*.pem` / `id_rsa*` / `credentials*`)を検出し、`CODEX_DELEGATE_ACK_SECRETS=1` が無ければ止まる。**Codex にはパス単位の読み取り除外が存在しない**(公式仕様を確認済み。sandbox は書き込みの制限のみ)ため、この入口検査が機密の送信を止める唯一の層になる。`.env.example` 等は除外される
- **[manual]** `.gitignore` に `.harness/mode` と `.harness/codex-runs/` を追加。**`.harness/` を丸ごと無視しないこと** — `.harness/decisions.jsonl` は「削除禁止・追記のみ」の永続ログで追跡対象に残す。**取り込む側の作業**: `.gitignore` は `merge` 対象なので、自分の `.gitignore` に該当 2 行を足す
- **[manual]** `.prettierignore` に `.harness/` と `AGENTS.md` を追加。Prettier は `.gitignore` を参照しないため、gitignore 済みでも run record の JSON を検査対象にして**ローカルの `format:check` だけが落ちる**(CI はクリーンなクローンなので影響を受けず、原因が分かりにくい)。**取り込む側の作業**: 自分の `.prettierignore` に 2 行を足す
- **[auto]** `.claude/template-manifest.json` に Codex 関連を登録(`AGENTS.md` と `.codex/config.toml` は `merge`、`.codex/prompts/` は `owned`、`.harness/` は `never`)
- **[auto]** `/sync-docs` の検査対象に「`CLAUDE.md` ↔ `AGENTS.md` の乖離」を追加。`AGENTS.md` が古いと**Codex だけが古い規約で動く**のに、Claude 側は何も壊れないため気づけない

> **この段階で検証できていないこと**: Codex CLI 自体はまだ導入していないため、確かめられたのは「委託経路が正しく壊れること」(入口検査・終了コード契約・run record・スタブ 6 シナリオ)までです。**Codex が実際に有用なサマリーを返すか = 委託の品質は未検証**で、判定は実装委託(段階3)に持ち越しています。

## 2026-08-19

保護ブランチへの直接コミットを止める層の**ベンダー非依存化**。従来この層は Claude の PreToolUse hook だけが持っており、Codex・手動 `git`・その他のツールからのコミットには一切効かなかった。

> **同日中の追補(レビューで発見した欠陥の修正)**: 下の 6 項目は上記の実装そのものの不具合修正と、実測で見つかった取りこぼしの追補です。**上の `.husky/pre-commit` 移植を取り込む場合は、必ずセットで取り込んでください**(単体では「保護ブランチ以外でもコミットが止まる」状態になりえます)。

- **[manual]** ⚠️ **`.husky/prepare-commit-msg` を新設**(新規ファイル)。`pre-commit` フックは `git commit` と `git commit --amend` でしか発火せず、**`git revert` / `git cherry-pick` では発火しない**(git の仕様)。どちらも保護ブランチへの直接コミットそのものなので、全操作で発火する `prepare-commit-msg` 側にも同じ検査を置いた。`git merge` / `git pull` の取り込みだけを通す(**`.git/MERGE_HEAD` があるときだけ素通し**。第 2 引数が `merge` かどうかで判断すると `git revert -e` / `git cherry-pick -e` もすり抜けるため — git 2.53 で実測)。**副次効果として `git commit --no-verify` も塞がる** — `--no-verify` が無効化するのは `pre-commit` と `commit-msg` だけで、このフックは迂回できない。**取り込む側の作業**: `merge` 対象なので手作業。テンプレート側の `.husky/prepare-commit-msg` をコピーする。無いと CI の `harness-integrity` が落ちる
- **[auto]** ハーネス自壊検知の実体を **`.claude/scripts/check-guard-integrity.sh` に集約**(新規)。SessionStart hook と CI が別々の判定を持つとずれるため。あわせて 2 つの穴を修正: **(1)** 従来は `if [ -f .husky/pre-commit ]` で囲っており、**フックごと消すと検査全体がスキップされて緑になった**(husky を使う構成かは `package.json` の依存でも判定するようにした)。**(2)** 呼び出しの検査が単なる文字列一致で、**説明コメントにファイル名があるだけで通った**(コメントでない行からの `bash` / `sh` / `source` 起動を要求する形に変更)
- **[auto]** `check-branch-policy.sh`(PreToolUse hook)の検査対象に `git revert` / `git cherry-pick` を追加。git hook 層と Claude 経由で判定がずれないようにするため。`--abort` / `--quit` / `--skip` / `--continue` は除外する(止めると revert 途中の保護ブランチから抜け出せなくなる)
- **[manual]** `.husky/pre-commit` の `lint-staged` 起動を 2 段構えに変更(`command -v lint-staged` → 無ければ `npx --no-install lint-staged`)。husky が `node_modules/.bin` を PATH に足さない構成(husky v8 形式など)では直呼びが 127 で落ち、**検査ではなくコミット自体が死ぬ**ため。**取り込む側の作業**: `merge` 対象なので手で置き換える
- **[manual]** ⚠️ `.husky/pre-commit` の**フェイルオープンが機能していなかった**。husky はこのファイルを `sh -e` で実行するため、`bash "$GUARD"` が非ゼロを返した時点でシェルごと終了し、`case $? in 1) exit 1 ;; esac` に制御が渡らない。結果として**内部エラー(`bash` 不在 = 127・共有スクリプトの構文エラー = 2・権限落ち = 126)でも全コミットがブロックされる**状態だった。終了コードを `&& / ||` のリスト内で受ける形に修正(リスト内は `set -e` が発火しない)。**取り込む側の作業**: `merge` 対象なので手作業。自分の `.husky/pre-commit` が `bash "$GUARD"` の直後に `case` / `if` を単独行で置いている場合は、テンプレート側の新しい形に置き換える
- **[auto]** 保護ブランチ検査の**ポリシー空洞化検知**を追加(実体は `check-guard-integrity.sh`、SessionStart hook と CI の `harness-integrity` から呼ぶ)。全層(PreToolUse / `.husky/*` / CI の `branch-policy`)はいずれも `protectedBranches` という同じ配列を読むため、ここが空になると**全層が「正常に動作したうえで素通し」という形で同時に無効化される**。呼び出しの有無だけを見る従来の自壊検知では検出できなかった経路

- **[manual]** ⚠️ 保護ブランチ検査を `.husky/pre-commit` に移植。判定の実体は新設の `.claude/scripts/check-protected-branch.sh` に一本化し、git hook(ベンダー非依存)と PreToolUse hook(Claude 専用)の両方から呼ぶ。**取り込む側の作業**: `.husky/pre-commit` は `merge` 対象なので自動では反映されない。テンプレート側の `.husky/pre-commit` を見て、`npx lint-staged` の**前**に guard 呼び出しブロックを手で足す。足さないと CI の `harness-integrity` ジョブが落ちる
- **[manual]** 保護ブランチへの直接コミットが**人間の手動 `git commit` でも止まる**ようになる。これは意図した挙動だが、`main` に直接コミットする運用が残っているプロジェクトは先に運用を変えるか、`.claude/branch-policy.json` の `protectedBranches` を実態に合わせること。**取り込む側の作業**: `git config core.hooksPath` が空でないことを確認する(空なら husky が無効で、この層は動かない。`npm ci` で有効化される)
- **[auto]** CI に `harness-integrity` ジョブを追加(`quality` から分離)。lint やテストの失敗で fail-fast すると自壊検知が実行されずに終わるため独立させた。`.husky/pre-commit` の構文検査と、ベンダー非依存層(スクリプトの存在 + 呼び出し)の検証を行う
- **[auto]** SessionStart hook に、ベンダー非依存層の自壊検知と `core.hooksPath` 未設定(husky 無効)の警告を追加
- **[auto]** `design.md` に完成マーカー(`<!-- status: draft -->` / `<!-- status: ready -->`)を導入。書きかけの設計が実装に渡るのを入口で止める。**印が無い `design.md` は検査対象外**なので、既存のステアリングは影響を受けない
- **[auto]** `check-implementation-phase.sh` の通過パスに `.husky/` を追加(ハーネスの一部になったため、司令塔が編集できる必要がある)
- **[manual]** ⚠️ `core.fileMode=false` の環境で新規シェルスクリプトを追加すると、ディスクが `+x` でも **git の index には 100644 で入る**。CI の `harness-integrity` は実行権限を必須にしているため、**その PR は必ず落ちる**。SessionStart hook に index 側の権限検知を追加し、CI のエラーメッセージにも復旧コマンドを載せた。**取り込む側の作業**: `git ls-files -s .claude/scripts/ .claude/hooks/` で 100755 以外が無いか確認し、あれば `git update-index --chmod=+x [パス]`(`chmod +x` だけでは index に反映されない)
- **[auto]** `implementer` エージェント定義にも完成マーカーの入口検査を追加(スキル側だけに書くと、エージェントの手順書と食い違う)。`/add-feature` の `判断待ち` 分岐にも「マーカーを `ready` に変えないと同じところで止まる」を明記
- **[auto]** `/kickoff` フェーズ5 のテンプレート由来 `.steering/` 削除を、名前パターンではなく `grep -l 'main-edit-ok' .steering/*/tasklist.md` による機械的検出に変更。テンプレート側の改修記録は増えていくため、名前で数え上げると取りこぼす
- **[manual]** `.gitignore` に `.devcontainer/devcontainer-lock.json` を追加。devcontainer CLI が features 解決時に生成するファイルで、環境ごとに内容が揺れる。**取り込む側の作業**: `.gitignore` は `merge` 対象なので、自分の `.gitignore` に同じ 1 行を足す(既にコミット済みなら `git rm --cached .devcontainer/devcontainer-lock.json` も要る)

## 2026-08-12 (2)

fork 委譲構成の点検で見つかった欠陥の修正。**同日の初回同期分(下の「2026-08-12」)を取り込む場合は、こちらもまとめて取り込むこと**(単体では実装フェーズが動かない欠陥を含む)。

- **[auto]** ⚠️ `implement-ticket` スキルの `allowed-tools` を削除。Bash の限定パターンだけを列挙しており Read / Edit / Write が含まれていなかったため、fork 先の実装エージェントが編集できず全チケットが失敗しうる状態だった。権限の担保は `settings.json` の `permissions.allow` と `implementer` の `tools:` に一本化する
- **[auto]** 最新ステアリングディレクトリの判定を `.claude/scripts/latest-steering.sh` に集約。従来の `ls -1d .steering/*/ | sort -r | head -1` は**ディレクトリ名全体**の降順のため、同日に複数の作業があると機能名の文字順で決まり、hook・fork・SessionStart が別々のディレクトリを指すことがあった。新規則は「日付プレフィックス降順 → 同日は mtime 降順」
- **[manual]** テンプレート由来の `.steering/*/` をプロジェクト側に残さないこと。これらの `tasklist.md` には実装フェーズのブロックを解除する `<!-- main-edit-ok -->` が入っており、残ったまま「最新」と判定されると**強制委譲が効かない状態で開発が始まる**。**取り込む側の作業**: `ls -1d .steering/*/` を確認し、テンプレート開発の作業記録(`*-fork-implementation-phase` / `*-rule-defect-fixes`)が残っていたら削除する(`/kickoff` フェーズ5 に手順を追加済み)
- **[auto]** PreToolUse hook の誤爆を修正。`check-branch-policy.sh` / `block-dangerous-cmds.sh` の検出をコマンド位置(行頭・`;`・`&&`・`||`・パイプの直後)に限定した。従来は `grep "gh pr create" docs/` のように**引用符の中に文字列が現れただけ**の調査コマンドがブロックされていた。あわせて破壊的 SQL の検査を DB クライアント経由の実行に限定し、`git push -f origin main`(フラグが第一引数に来る形)の取りこぼしを修正
- **[auto]** `/fix-issue` の検証ステップに `code-reviewer` を追加(従来は `/check` のみでレビューが走らず、`develop` 運用では PR 時の自動レビューも走らないためレビューゼロで PR に到達しうる経路だった)。コミットも `Skill('commit')` に統一
- **[manual]** `.claude/settings.json` の `permissions.allow` に `Bash(git fetch:*)` / `Bash(git merge:*)` / `Bash(gh pr create:*)` を追加。**取り込む側の作業**: `merge` 対象のため、自分の allow 配列に同じ 3 つを追記する(無いと `/add-feature` の「無停止」フローが毎回 permission prompt で止まる)
- **[auto]** 品質チェックの三層の役割分担を明記(fork = 変更ファイルの自己修復 / `test-runner` = フルスイート 1 回 / CI = 最終ゲート)。CI のトリガー範囲の記述も実態(PR は全ベース、push は main・develop のみ)に修正

## 2026-08-12

- **[manual]** ⚠️ 実装フェーズを `implement-ticket` スキル(`context: fork` / `model: sonnet`)への委譲に変更。司令塔はモデルを切り替えず、実装は Sonnet の subagent が行う。**取り込む側の作業**: `/next-ticket` / `/add-feature` / `/fix-issue` をカスタマイズしている場合、実装ステップを `Skill('implement-ticket')` の呼び出しに置き換える(戻り値 `完了` / `判断待ち` / `失敗` で分岐)。手動の `/model sonnet` 運用をドキュメント化している箇所があれば削除する
- **[manual]** ⚠️ `.claude/rules/` を 2 層に分割。全エージェント共通は `.claude/rules/*.md`(CLAUDE.md が `@` インポート)、司令塔専用は `.claude/rules/lead/*.md`(SessionStart hook が注入)。**取り込む側の作業**: `CLAUDE.md` の `@.claude/rules/...` 行を `@.claude/rules/spec-driven.md` の 1 行だけに減らす(残り 4 本は `lead/` へ移動済みで、hook が注入するため `@` インポートは不要)。カスタム subagent を追加している場合、モデル切替や `/check` 委譲の指示が効かなくなる点に注意する
- **[manual]** PreToolUse hook `check-implementation-phase.sh` を追加(実装フェーズ中のメインセッションからの実装コード編集をブロック)。**取り込む側の作業**: `.claude/settings.json` の `hooks.PreToolUse` に `matcher: "Edit|Write"` のエントリを追加する。テンプレート自体の改修など司令塔が実装すべき作業では、`tasklist.md` に `<!-- main-edit-ok -->` を書いて解除する
- **[auto]** `.claude/agents/implementer.md` / `.claude/skills/implement-ticket/SKILL.md` を新設
- **[auto]** `docs/template-dev/cost-model.md` を新設。ルールファイルは subagent 起動のたびに全量ロードされるため、判断の根拠(実測値・単価)はルールから分離してここに置く

## 2026-08-11

- **[manual]** ⚠️ CLAUDE.md の共通ルールを `.claude/rules/*.md`(モデル運用方針 / スペック駆動 / ブランチ・チケット / コンテキスト管理 / レビュー使い分け)に分割し、CLAUDE.md からの `@` インポートに変更。**取り込む側の作業**: CLAUDE.md の該当節を削除し、代わりに 5 つの `@.claude/rules/...` 行を追記する。プロジェクト固有の追記(MCP の使いどころ・スポーク構成ルールへの参照・ハーネス節)は CLAUDE.md に新設した「プロジェクト固有ルール」節へ移す
- **[manual]** テンプレート追従の仕組みを追加(`.claude/template-manifest.json` / `/sync-template` / 月次 `template-update-check` ワークフロー)。**取り込む側の作業**: マニフェストの `syncedAt` に、いまテンプレートから取り込んだ commit SHA を記入する(以降は `/sync-template` が自動更新する)
- **[auto]** `docs/template-dev/CHANGELOG.md` を新設(このファイル)。`/sync-template` がリモートから直接読むため、`docs/template-dev/` を削除済みのプロジェクトでも動作する
