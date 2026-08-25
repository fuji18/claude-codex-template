---
description: initial-requirements.mdを起点にプロジェクト開始フロー全体(スタック整合→ドキュメント→チケット→ハーネス→最初のチケット)を一気通貫でガイドする
---

# プロジェクトキックオフ

テンプレートから作った新リポジトリで、`docs/ideas/initial-requirements.md` に書かれたアイデアを起点に、開発開始までの全セットアップを対話的に進めるコマンドです。各フェーズの完了をユーザーに確認してから次へ進みます。

**引数:** なし

---

## フェーズ0: 前提確認

1. `docs/ideas/initial-requirements.md` を読む。
   - 存在しない、またはテンプレートの雛形のまま(プロダクト名が `[プロダクト名]` のまま等)の場合は、「アイデアを記入してから再実行してください。記入例: `docs/template-dev/initial-requirements.example.md`」と案内して終了する。
2. `docs/ideas/` 内の他のファイルも読む(`*.example.md` と `docs/template-dev/` は読み込み対象外)。
3. `docs/` に正式版ドキュメントが既にある場合は、`/kickoff` ではなく通常の開発フロー(`/next-ticket` 等)を案内して終了する。
4. **Step 0 チェック**: README の Step 0 で案内している手動セットアップの実施状況をユーザーに確認する(フェーズ5で README を書き換えると案内が消えるため、ここで拾う):
   - Actions シークレット `CLAUDE_CODE_OAUTH_TOKEN` の設定(未設定の間、PR 自動レビューと `@claude` メンションはスキップされる)
   - Settings → Code security の Secret scanning + Push protection の有効化
   - **ブランチ保護(ルールセット)が使えるプランか**を実際に叩いて確かめる:
     ```bash
     gh api "repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/rulesets" --jq 'length'
     ```
     - **数値が返る**(200): 使える。返り値が `0` ならルールセットが未設定なので、`main` に対して「直接 push の禁止 / PR 必須 / force push・削除の禁止」+ required status checks(`branch-policy`・`harness-integrity`・`quality`)+ bypass list を空、の設定を促す
     - **コマンドが失敗する**(非ゼロ終了。stderr に `gh: Forbidden (HTTP 403)`。`--jq` は適用されない): private + Free プランでブランチ保護もルールセットも使えない。**Codex にコミット権を渡すモード C の前提が崩れる**ため、以下の 3 択をユーザーに提示して選ばせる(選んだ結果をフェーズ6 の完了報告に記載する):
       1. **リポジトリを public にする** — ルールセットが無料で使える。公開して困る資産が無いなら最も安い
       2. **GitHub Pro / Team に上げる** — private のままブランチ保護 + required checks が使える(課金)
       3. **ローカル hook が唯一の層だと認める** — 追加コストゼロだが、`git push` の直接実行を止める層が無く、CI を required check にできない(赤くなるだけでマージを止められない)。この場合は**モード C(Codex にコミットさせる運用)を使わない**ことを併せて合意する
   - 未実施の項目があっても中断はせず、フェーズ6の完了報告に**残課題として明記**する。
5. **テンプレート追従の基準 SHA を記録する**(以降 `/sync-template` が差分の起点に使う。ここで刻まないと初回同期が全ファイル比較になる):
   - `.claude/template-manifest.json` の `syncedAt` が `null` の場合のみ実行する
   - `git remote add template <templateRepo> && git fetch template <templateBranch> --quiet` でテンプレートを取得し、`git rev-parse template/<templateBranch>` の SHA を `syncedAt` に、今日の日付を `syncedDate` に書き込む
   - 取得に失敗した場合(ネットワーク・権限)は中断せず、残課題として「後で `/sync-template` を実行して基準 SHA を記録する」と伝える

## フェーズ1: 技術スタックの整合チェック

1. アイデアの「技術的な検討事項」とテンプレート既定(Node.js / TypeScript / npm / vitest / eslint / prettier)を突き合わせる。
2. **異なるスタック**(モバイルアプリ、Python 等)の場合、以下をユーザーに提示して承認を得る:
   - 検証コマンドの置換方針(例: Android なら `./gradlew lint` / `./gradlew test`)
   - `.devcontainer/` の更新方針(必要なランタイム・SDK)。**Node feature は異スタックでも残す**(post_create.sh の Claude Code インストール `npm install -g` と、npx 起動の MCP(Context7)が依存するため)
   - TS ツールチェーン(package.json / tsconfig.json / vitest.config.ts / eslint.config.js / .prettierrc / src/ プレースホルダ)の削除または置換
   - `.gitignore`(Node 専用エントリを新スタックの成果物・キャッシュの ignore に置換。漏れると生成物がコミット候補に混入する)
   - **CI とハーネスの npm 前提部分**の置換(漏れると CI が常に赤になる・hook が無言で動かなくなる):
     - `.github/workflows/ci.yml`(`npm ci` / `npm run lint` 等の各ステップと Node セットアップ)
     - `.github/dependabot.yml`(`npm` / `devcontainers` ecosystem と ignore ルールを新スタックの ecosystem に置換)
     - `.husky/pre-commit` + package.json の `lint-staged` / `prepare`(pre-commit フックを新スタックのツールで再構成。secretlint の実行手段も含める)
     - `.claude/scripts/lint-on-edit.sh`(`npm run lint` / `npm run typecheck` の直書きと対象拡張子 `*.ts|*.js` を新スタックに合わせる)
     - `.claude/settings.json` の PostToolUse インライン hook(`npx --no-install prettier` の直書き。新スタックのフォーマッタに置換する。放置すると `|| true` で黙って空振りし、Edit/Write 直後の自動フォーマットが静かに無効になる)
     - `.claude/hooks/session-start.sh`(リモート環境の依存インストールが `npm install` 固定 → 新スタックのインストールコマンドに置換。serena 規模検知の対象拡張子 `*.ts / *.tsx` も新スタックの拡張子に合わせる)
     - `.claude/settings.json` の `permissions.allow` / `ask`(npm / npx 前提の allowlist を新スタックの検証コマンドに置換。放置すると死に設定+新コマンドが毎回 permission prompt になる)
   - `CLAUDE.md` の技術スタック節の更新
3. 承認された置換作業を実行する(この置換自体も `.steering/` に記録する)。
4. 同じスタックの場合は `src/` のプレースホルダ(`index.ts` / `index.test.ts`)を最初の実装時に削除する旨だけ伝えて次へ。

## フェーズ1.5: 効率化 MCP・UI ツールの提案

1. `.claude/docs/mcp-introduction-guide.md` を読む。
2. アイデアとフェーズ1で確定した技術スタックから、プロジェクト特性に合致する MCP を「条件付き」の表から選んで提案する(該当なしなら「既定の Context7 のみで開始」と伝えて次へ):
   - 例: Web フロントエンドあり → Playwright MCP、DB あり → DB 系 MCP(読み取り専用)
   - 提案時は「何に使うか」「ツールスキーマの固定費(毎セッションのコンテキスト消費)」の両方を伝え、**開発初期から使う確度が高いものだけ**を勧める(後からの追加は容易。迷ったら入れない)
3. ユーザーが承認した MCP のみ導入する(ガイドの「導入・削除の手順」に従う: `.mcp.json` 追記 + CLAUDE.md に使いどころ 1〜2 行 + 必要なら `post_create.sh` にインストール処理)。
4. 導入した場合、反映には Claude Code の再起動が必要である旨を伝える(再起動は /kickoff 完了後でよい)。
5. **UI/画面作成の有無を判定し、ある場合のみ UI 品質の導線を用意する**(バックエンド専用・CLI・ライブラリで画面が無いなら省略し、「後で UI を追加する際は `docs/ui-design-guidelines.md` を参照」とだけ伝える):
   - `docs/ui-design-guidelines.md` の **§7「実装への翻訳」表を記入**する(UI フレームワーク・コンポーネントライブラリ・トークン実装形式・アイコン・参照デザイン)。**コンポーネントライブラリの採用は実装品質の最大レバー**なので必ず決める。
   - **Design プラグインの導入を提案**する(`/design:critique` `/design:handoff` `/design:accessibility` `/design:ux-copy`)。§6 のレビューゲートとして使う。**画面作成があるプロジェクトのときだけ判断して導入**し、承認された場合のみ入れる(無い場合は入れない)。
   - 将来 Figma で design-first に移行する可能性があれば、`docs/ui-design-guidelines.md` §8 の導線(Figma MCP)を紹介するに留める(この時点では導入しない)。

## フェーズ2: 永続ドキュメントの作成

`Skill('setup-project')` 相当のフロー(`/setup-project`)を実行し、6 つの永続ドキュメントを 1 ファイルずつ承認を取りながら作成する。initial-requirements.md の内容(特に P0/P1/P2 の優先度・非機能要件・成功指標)を最大限反映する。

## フェーズ2.5: スポーク開発構成ルール(ハブ&スポーク構成のときのみ)

フェーズ2で確定したドキュメントが **ハブ&スポーク構成**(一覧する「ハブ」+ そこから飛ぶ独立サイト/ゲーム=「スポーク」)を示している場合のみ、`/setup-spoke-standards` のフローを実行する。

- 判断がつかないときはユーザーに確認し、該当しなければスキップして次へ進む
- **必ずフェーズ3(チケット分割)より前に実行する**。構成ルールの MUST 項目(セキュリティヘッダ・SEO・レジストリメタデータ等)がチケットの受け入れ条件になるため、後回しにすると発行済みチケットの作り直しになる
- 実行するのは**ハブ側リポジトリ**(= このプロジェクト)。スポーク側の独立リポジトリでは実行せず、生成された `docs/playbook/spoke-development-standards.md` を読んで従わせる

## フェーズ3: 実装チケットへの分割

`/setup-tickets` のフローを実行し、GitHub Issues に段階的な実装チケットを発行する(`ticket` + 優先度ラベル)。**P0 機能のみをチケット化**し、P1/P2 は backlog として区別する(スコープガード)。

## フェーズ4: ハーネス層の追加

1. `/harness-setup` のフローを実行する。フェーズ1で確定した検証コマンドを hooks に反映する。
2. **Dependabot をプロダクト向けに再チューニングする**: テンプレート既定の `.github/dependabot.yml` は「テンプレートの鮮度維持」を目的に週次(weekly)更新をかける設定で、実プロダクトにそのまま引き継ぐと毎週の依存更新PRがレビュー・CIコストになる。`docs/template-dev/dependabot-product.example.yml` を参照し、プロダクト向けプロファイル(monthly + minor/patch グループ化 + major は個別PR)に置き換える提案をユーザーに提示して承認を得る。
   - セキュリティ更新は interval と無関係に即時PRが出るため、monthly に落としてもセキュリティ対応は遅れないことを補足する
   - フェーズ1で TS 以外のスタックに置換した場合は、`package-ecosystem` と `ignore` の依存名を実態に合わせて調整する(不要なエコシステム節は削除する)
3. **委託禁止領域をパスで具体化する**(Codex 併用時。フェーズ2 で `docs/architecture.md` / `docs/repository-structure.md` が確定した後だからここで行う):
   - 認証・決済・データ移行・ガードレールに相当するモジュールを**実際のパス**で洗い出す(例: `src/auth/**`・`src/billing/**`・`db/migrations/**`)
   - `CLAUDE.md`「プロジェクト固有ルール」節に「Codex への委託禁止領域(パス)」として列挙する(判断ルールの正)
   - `AGENTS.md` の `<!-- kickoff:delegation-forbidden-paths -->` 〜 `<!-- /kickoff:delegation-forbidden-paths -->` の中に**追記する**(実装者への指示)。**既存の汎用項目(`delegate-codex.sh`・`.husky/` 等)は消さない** — これらはテンプレートからすべてのプロジェクトに配布されるため、どのプロジェクトでも成立する。マーカーの行自体も消さない
   - **`.claude/codex-denylist.txt` には書かない。** あちらは「該当ファイルが存在するだけで委託を止める」機密送信のフェイルクローズ検査で、そこにモジュールパスを入れると全委託が常に止まる

## フェーズ5: リポジトリのプロダクト化

1. `README.md` をプロダクトの README(プロダクト名・概要・開発方法)に書き換える。
2. テンプレートの手順書としての旧内容は削除してよい(原本はテンプレートリポジトリに残っている)。
3. **package.json のメタデータ**を書き換える: `name`(テンプレートの `claude-code-template` のまま残さない)・`description`・`keywords`。書き換え後に `npm install` を実行して package-lock.json の name を同期する。
4. **`.devcontainer/devcontainer.json` の `name`** をプロダクト名に書き換える。
5. **ライセンス方針**をユーザーに確認して反映する:
   - 公開(OSS): `LICENSE` の Copyright 名義を自分のものに書き換える(package.json の `license` は `MIT` のまま)
   - 非公開: `LICENSE` を削除し、package.json を `"license": "UNLICENSED"` に変更する
6. **`CLAUDE.md` の整合**を取る(**編集するのは CLAUDE.md 本体だけ。`.claude/rules/*.md` はテンプレート所有なので触らない** — 触っても `/sync-template` で失われる):
   - 「開発プロセス」の**初回セットアップ節を削除**し、日常的な使い方だけを残す(完了済みのテンプレート利用手順を毎セッション読み込ませない)。「テンプレート更新の取り込み」節は**残す**
   - 技術スタック節の「※ テンプレート既定値。…」注記を削除する(フェーズ1で実態確認済みのため)
   - README への参照(「コマンド早見表」「詳細は README.md を参照」等)を書き換え後の README と整合させる(コマンド早見表をプロダクト README に残すか、CLAUDE.md 側の参照を削除する)
   - ディレクトリ構造節から、削除するもの(`docs/template-dev/` 等)への言及を除去する。`.claude/rules/` の行は**残す**
   - フェーズ1.5 で導入した MCP の使いどころなど、これまでのフェーズで発生したプロジェクト固有ルールが「プロジェクト固有ルール」節に集約されているか確認する(共通ルール側に紛れ込んでいたら移す)
7. `docs/template-dev/` の削除を提案する(記入例が不要になったら。恒久参照されるガイドは `.claude/docs/` にあるため丸ごと削除してよい。`CHANGELOG.md` も `/sync-template` がテンプレートのリモートから直接読むため、ローカルに残す必要はない)。
8. **テンプレート由来の `.steering/*/` を削除する**(必須。提案ではなく実行する):

   ```bash
   ls -1d .steering/*/                          # 残っている作業記録を確認する
   grep -l 'main-edit-ok' .steering/*/tasklist.md 2>/dev/null   # 脱出弁つき = テンプレート由来
   ```

   **ディレクトリ名で判断しない。** テンプレート側の改修記録は増えていくため、名前のパターン(`*-fork-implementation-phase` 等)で数え上げると取りこぼす。**`main-edit-ok` を含む `tasklist.md` を持つディレクトリは、例外なくテンプレート由来なので全部削除する**(プロダクト側でこの脱出弁を常用することはない)。名前に頼らずこの grep の結果を正とする。理由は 2 つ:
   - これらの `tasklist.md` には `<!-- main-edit-ok -->`(実装フェーズのブロックを解除する脱出弁)が入っている。プロジェクト側に残ったまま「最新のステアリング」と判定されると、**実装フェーズの強制委譲が効かない状態で開発が始まる**
   - `/resume-work` や SessionStart の現在地表示が、プロダクトと無関係な作業を拾う

   このプロジェクトの最初の作業記録は `/next-ticket` が新しく作る。テンプレートの記録を履歴として残す必要はない(原本はテンプレートリポジトリにある)。

## フェーズ6: 開始

1. チケット Issue(`gh issue list --label ticket`)から最初に着手すべきもの(依存なし・最優先)を 1 つ提示する。
2. フェーズ0の Step 0 チェックで未実施だった項目があれば、**残課題として再掲**する。ブランチ保護の 3 択は、解決済み(public 化 / プラン変更)の場合も**どれを選んだかを明記**する。
3. `/next-ticket` で着手する方法を案内して終了する。

## 完了条件

- フェーズ1の置換(必要な場合)が完了し、検証コマンドが実行可能
- `docs/` に 6 つの永続ドキュメントが存在し、チケット Issue が発行されている(ハブ&スポーク構成の場合は `docs/playbook/spoke-development-standards.md` がチケット発行より前に作成されている)
- ハーネス層(hooks / permissions / subagents)が設定済み。Dependabot がプロダクト向け(monthly)に再チューニング済み
- ブランチ保護の可否が確認済み(不可の場合は 3 択の選択結果が記録されている)。Codex 併用時は委託禁止領域が `CLAUDE.md` と `AGENTS.md` にパスで書かれている
- README・package.json・devcontainer 名・ライセンスがプロダクト用になっている
- 次の一手(最初のチケット)と Step 0 の残課題(あれば)が提示されている
