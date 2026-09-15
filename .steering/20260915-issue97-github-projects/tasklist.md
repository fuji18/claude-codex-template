# タスクリスト: GitHub Projects による開発管理の導入

<!-- main-edit-ok -->

> **`main-edit-ok` を付けている理由:** この作業はテンプレート自身の改修で、変更対象の大半(`.claude/scripts/` / `AGENTS.md` / `CLAUDE.md` / `.claude/rules/` / `README.md`)が**委託禁止領域**か司令塔の担当にあたる。
> 実装フェーズのブロック(`check-implementation-phase.sh`)を解除しないと司令塔がこれらを書けない。
> **Codex に渡す範囲(フェーズ2)は、この脱出弁とは無関係に委託する。**

Issue: #97 / design: `design.md`(`<!-- status: ready -->`) / requirements: `requirements.md`

---

## フェーズ0: 着手前の前提(人間の判断が要る)

- [x] 0-1. **現ブランチの未コミット変更の退避**(人間の判断)
  - [x] ① `README.md` の再構成 → `feature/readme-current-usage` にコミットし PR #96 として分離
  - [x] ③ この `.steering/` → 本ブランチでコミット
  - [ ] ② `.codex/config.toml` の変更 + `.agents/`(38 ファイル)+ `.codex/agents/` + `.codex/hooks*` → **判断待ち**(マシン固有パスの混入・安全性コメントの消失・prettier 未通過の 3 点。本作業には含めない)
  - [ ] `README.html` / `docs/template-dev/codex-harness-review-20260904.html` → コミットするか `.gitignore` するか未決(未追跡のまま保留)
- [x] 0-2. チケット Issue を 1 枚発行する(#97)(`ticket` + `P1` 相当。**`delegate:codex` は付けない** — 委託禁止領域を含むため。design §15)
- [x] 0-3. `feature/github-projects` を `main` から切る(`.claude/branch-policy.json`: baseBranch=main)

## フェーズ1: Claude Code 側の先行作業(委託禁止領域・要ネットワーク検証)

> **この順序は必須。** フェーズ2 の散文はスクリプトの CLI 契約(design §5.1 / §5.2)を前提に書かれる。

- [ ] 1-1. `gh` を実機で叩き、design §14 の 5 項目(item-list / item-add / field-list / auth status / project create の JSON キー名)を**実測**する。推定で書かない
  - [ ] 検証用 Project の作成が必要なら**ユーザーの承認を得てから**行う(このステアリングの計画時点では作らない)
- [ ] 1-2. `.claude/scripts/projects-sync.sh` を新規作成する(design §5)
  - [ ] `status` / `expected` / `drift` / `set` / `reconcile` / `add` / `--print-config` の 7 経路
  - [ ] 終了コード 0/1/2/3/4 を design §5.2 のとおりに実装する
  - [ ] config 内の秘密キー(`token`/`pat`/`secret`/`privateKey`)検出で exit 2(フェイルクローズ)
  - [ ] `gh auth status` の生出力を出さない(スコープの有無だけを正規化して出す)
  - [ ] 出力は 1 行 1 事実・20 行以内
  - [ ] 実測したキー名をスクリプト内コメントに記録する
  - [ ] `chmod +x` する(source 専用ライブラリではない)
- [ ] 1-3. design §12.1 の V1〜V4 を手元で実行し、無設定・無効・`gh` 不在・秘密キー混入の 4 状態を確認する
- [ ] 1-4. `.claude/settings.json` の `permissions.allow` に `Bash(gh project:*)` と `Bash(gh api users/:*)` を追加する
- [ ] 1-5. `.claude/template-manifest.json` に `owned: .claude/projects-policy.example.json` と `never: .claude/projects-policy.json` を追加する

## フェーズ2: Codex への委託(1 バッチ・禁止領域を含まない)

> 委託は `bash .claude/scripts/delegate-codex.sh impl .steering/20260915-issue97-github-projects/` の 1 回。
> **フェーズ1 が完了してから渡す。** 渡す前に `design.md` が `ready` であることを確認する。

- [ ] 2-1. `.claude/commands/enable-github-projects.md` を新規作成(design §6.1 の 9 ステップ表をそのまま手順にする)
- [ ] 2-2. `.claude/commands/github-projects-status.md` を新規作成(design §6.2。**読み取り専用**・3 値表示・復旧手順の対応表)
- [ ] 2-3. `.claude/commands/github-projects-next.md` を新規作成(design §6.3。**着手しない**・判定材料の優先順位・着手条件 5 項目)
- [ ] 2-4. `.claude/commands/next-ticket.md` に 2 箇所を追記(design §7.1。既存の手順・表は書き換えない)
- [ ] 2-5. `.claude/commands/kickoff.md` に `## フェーズ3.5` を新設し、完了条件に 1 行追加(design §7.2)
- [ ] 2-6. `.claude/commands/status.md` に情報収集 1 項目と表の 1 行を追加(design §7.3)
- [ ] 2-7. `.claude/commands/setup-tickets.md` の完了報告に 1 行追記(design §7.4)
- [ ] 2-8. `.claude/projects-policy.example.json` を新規作成(design §4 のスキーマ。`enabled: false`・秘密キーなし)
- [ ] 2-9. `.claude/docs/github-projects-guide.md` を新規作成(正の所在の表 / ボード操作は正ではないこと / 人間作業の表 = design §1・§10 の要約)
- [ ] 2-10. design §12.1 の V5・V6・V8 を実行して自己チェックする

## フェーズ3: Claude Code 側の仕上げ(委託禁止領域)

- [ ] 3-1. `AGENTS.md` §3 の表に「GitHub Projects の操作: しない / しない」行を追加する(**委託禁止領域の一覧(§4)は変更しない**。design §4 末尾の判断)
- [ ] 3-2. `.claude/rules/lead/branch-and-tickets.md` に「Projects を使う場合の正の所在」を**3 行以内**で追記する(コンテキスト費用のため詳細はガイドへ)
- [ ] 3-3. `CLAUDE.md` のディレクトリ構造節に `.claude/projects-policy.json` の 1 行を追加する
- [ ] 3-4. `.claude/rules/mode/degraded.md` の復帰検収手順の末尾に「`/github-projects-status` → drift を `reconcile`」を 1 項目追加する(design §9)
- [ ] 3-5. `README.md` のコマンド早見表に 3 行、スクリプト早見表に `projects-sync.sh` の 1 行を追加する(**フェーズ0-1 の退避が済んでいることが前提**)

## フェーズ4: 検証

- [ ] 4-1. design §12.1 の V1〜V9 を通す
- [ ] 4-2. `/check`(test-runner に委譲)で lint・型・テスト・フォーマットを 1 回だけ回す
- [ ] 4-3. `bash .claude/scripts/check-guard-integrity.sh` と `check-forbidden-paths-doc.sh` が無出力であることを確認する
- [ ] 4-4. `git diff -- package.json` を目視する(委託を挟んだ差分のライフサイクル系検査。`.claude/rules/lead/review-policy.md`)
- [ ] 4-5. `code-reviewer` で主レビューを 1 巡する(200 行未満・重要変更に当たらないため `delegate-codex.sh review` は使わない)
- [ ] 4-6. **実 GitHub での受け入れ(design §12.2 V10〜V16)は人間の承認を得てから実施する。** 承認が得られない場合は「未実施」として PR ボディに明記し、V1〜V9 だけで PR を出す

## フェーズ5: 記録と PR

- [ ] 5-1. `docs/template-dev/CHANGELOG.md` に項目を追記する(`.claude/` 変更のため CI の `record-hygiene` が要求する)
- [ ] 5-2. `.harness/decisions.jsonl` に 1 行追記する(**PR を出す前**。委託先・往復回数・検収の指摘数・`/usage` の週枠使用率)
- [ ] 5-3. PR を作成する(`--base main` を明示、ボディに `Closes #[番号]`、未実施の受け入れ項目があれば明記)

---

## 委託の区分(一覧)

| フェーズ | 担当 | 理由 |
| --- | --- | --- |
| 0 | **人間 + 司令塔** | 未コミット変更の扱いとチケット発行は人間の判断 |
| 1 | **Claude Code** | `.claude/scripts/` `.claude/settings.json` = 委託禁止領域。かつ実測にネットワークが要る(sandbox は無効) |
| 2 | **Codex(1 バッチ)** | `.claude/commands/` `.claude/docs/` と JSON 1 本。禁止領域外・ネットワーク不要・仕様が design に書き切られている |
| 3 | **Claude Code** | `AGENTS.md` `CLAUDE.md` `.claude/rules/` = 委託禁止領域。`README.md` は未コミット変更との競合回避 |
| 4 | **Claude Code**(検収の委譲先は test-runner / code-reviewer) | 検収の判断は司令塔の仕事 |
| 5 | **Claude Code** | 記録と PR は司令塔の担当 |

**Codex に禁止領域の変更を含む一括タスクを渡さないこと。** フェーズ2 だけを委託し、フェーズ1・3 は司令塔が自分で書く。

---

## 実装後の振り返り

### 実装完了日
{YYYY-MM-DD}

### 計画と実績の差分

**計画と異なった点**:
- {design §14 の実測値が想定と違った点}

**新たに必要になったタスク**:
- {実装中に追加したタスク}

**技術的理由でスキップしたタスク**(該当する場合のみ):
- {タスク名 / スキップ理由 / 代替実装}

### 学んだこと
- {層1(組み込みワークフロー)と層2(コマンド投影)の分担が実運用で妥当だったか}
- {drift が定常的に発生する経路があったか}

### 次回への改善提案
- {層3(Actions 同期)を入れる価値があるかの判断材料}
