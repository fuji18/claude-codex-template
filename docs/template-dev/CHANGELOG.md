# テンプレート CHANGELOG

テンプレート利用側(このテンプレートから作ったプロジェクト)が **`/sync-template` で更新を取り込むとき** に読む変更履歴です。テンプレート自身の開発メモではなく、**「取り込む側が何をすればよいか」** だけを書きます。

## 記法

- 新しいものを**上**に置く。見出しは `## YYYY-MM-DD` の日付単位
- 各項目の先頭に区分を付ける:
  - **`[auto]`** — `/sync-template` の上書きだけで完結する。取り込む側の作業はゼロ
  - **`[manual]`** — 取り込む側に作業が必要。**何をすればよいかを 1 行で書く**(これが無い `[manual]` は書いた意味がない)
- 破壊的変更(既存の運用が壊れる)は `[manual]` にし、行頭に **⚠️** を付ける
- `/sync-template` は `syncedAt` のコミット日以降の日付見出しだけを読む。**日付を遡って過去の見出しに追記しない**(取り込む側が見落とす)

---

## 2026-08-19

保護ブランチへの直接コミットを止める層の**ベンダー非依存化**。従来この層は Claude の PreToolUse hook だけが持っており、Codex・手動 `git`・その他のツールからのコミットには一切効かなかった。

> **同日中の追補(レビューで発見した欠陥の修正)**: 下の 6 項目は上記の実装そのものの不具合修正と、実測で見つかった取りこぼしの追補です。**上の `.husky/pre-commit` 移植を取り込む場合は、必ずセットで取り込んでください**(単体では「保護ブランチ以外でもコミットが止まる」状態になりえます)。

- **[manual]** ⚠️ **`.husky/prepare-commit-msg` を新設**(新規ファイル)。`pre-commit` フックは `git commit` と `git commit --amend` でしか発火せず、**`git revert` / `git cherry-pick` では発火しない**(git の仕様)。どちらも保護ブランチへの直接コミットそのものなので、全操作で発火する `prepare-commit-msg` 側にも同じ検査を置いた。`git merge` / `git pull` の統合コミットは通す(第 2 引数が `merge` のとき素通し)。**副次効果として `git commit --no-verify` も塞がる** — `--no-verify` が無効化するのは `pre-commit` と `commit-msg` だけで、このフックは迂回できない。**取り込む側の作業**: `merge` 対象なので手作業。テンプレート側の `.husky/prepare-commit-msg` をコピーする。無いと CI の `harness-integrity` が落ちる
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
