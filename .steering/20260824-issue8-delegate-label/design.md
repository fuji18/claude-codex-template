<!-- status: ready -->

# 設計: 段階6 — チケット統合(`delegate:codex` ラベルと委託導線)

## 0. 確定した設計判断(実装者は判断しない)

| # | 論点 | 決定 | 根拠 |
| --- | --- | --- | --- |
| 1 | ラベル名・色・説明 | `delegate:codex` / color `6F42C1` / description `Codex にチケット丸ごと委託する` | 既存ラベルと重複しない色(`in-progress`=1D76DB, `blocked`=5319E7 と区別できる紫) |
| 2 | ラベルを付ける主体とタイミング | **既定は付けない。** `/setup-tickets` は条件が明らかなチケットにだけ付ける。通常は `/next-ticket` で `design.md` を書き切った時点で司令塔が付ける | 発行時点では参照実装も検収インフラも無く、委託の成立条件(§10.4)を満たしているか判定できないため |
| 3 | ラベルの有無が変える**実際の挙動** | **ラベルあり = tasklist を分割せず 1 回の `delegate-codex.sh impl` で全体を委託する。ラベルなし = §6 のバッチ運用(3 項目前後で区切り、各バッチの検収を挟む)** | 「委託経路に流れる」を観測可能な差分として定義する。委託先そのものは元々 Codex 既定(§4.1)なので、ここを差分にしないとラベルが飾りになる |
| 4 | ラベルは選定順序に影響するか | **しない。** 優先度・依存・フェーズ順の選定規則は変更しない | 委託可否は着手順の理由にならない。混ぜると P0 より委託しやすい P2 が先に消化される |
| 5 | `exit 3`(Codex 利用不可)のときラベルを外すか | **外さない。** Sonnet fork にフォールバックするだけ | 環境の欠落であってチケットの属性ではない(§9「Codex 未導入でも全フローが成立すること」) |
| 6 | §6 の運用ルールの置き場 | **`.claude/rules/lead/delegation-policy.md`(新規)** | 委託の振り分けは司令塔だけの判断。`.claude/rules/` 直下に置くと全サブエージェントに毎回ロードされ、spawn ごとに課金される |
| 7 | 委託禁止領域(§10.3)の置き場 | **判断ルール = `CLAUDE.md`「プロジェクト固有ルール」(同期区分 `never`)/ 実装者への指示 = `AGENTS.md` §4(同期区分 `merge`)の 2 か所**。`.claude/codex-denylist.txt` には**書かない** | denylist は「該当ファイルが存在するだけで委託を止める」フェイルクローズ検査。禁止領域のパスを入れると、そのファイルが在るだけで全委託が止まる。層が違う |
| 8 | 禁止領域を `/sync-template` から守る方法 | `AGENTS.md` の該当ブロックを `<!-- kickoff:delegation-forbidden-paths -->` / `<!-- /kickoff:delegation-forbidden-paths -->` で挟む | `AGENTS.md` は `merge` 区分。統合時にプロジェクト固有の行がどこかを機械的に示せる |
| 9 | 本リポジトリ自身の禁止領域 | `.claude/scripts/delegate-codex.sh` / `.claude/scripts/check-protected-branch.sh` / `.husky/pre-commit` / `.husky/prepare-commit-msg` / `.claude/codex-denylist.txt` | 1 つ目は自己編集ハザード(§9・実測済み)、残りはガードレール本体と送信禁止リストそのもの |
| 10 | ブランチ保護可否の判定コマンド | `gh api "repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/rulesets" --jq 'length'` | 実機で確認済み(200 + 配列)。Free の private では 403 を返す(§8 の実測) |
| 11 | 「機械的な項目が 2 つ以下なら司令塔が直接書く」(§6 原文) | **`implement-ticket` の fork に渡すと読み替える** | 司令塔の Edit/Write は `check-implementation-phase.sh` がブロックする。原文のままでは hook と矛盾する |
| 12 | 自己編集ハザード(§9 の「段階6 までに判断する」) | **方針は (b) 起動時に自身を一時ディレクトリへコピーして `exec` する を採用。実装は別 Issue に切り出す** | 委託の唯一の入口を本チケットの委託自身が書き換えるのは危険。判断は記録し、実装は独立した検収単位に置く |
| 13 | `--background` | 実装しない。§6 の表の `impl --background` に「未実装。現状は前景実行」と注記する | 段階4 で見送られたまま。本チケットのスコープ外 |

## 1. 成果物一覧

| # | ファイル | 区分 |
| --- | --- | --- |
| 1 | `.claude/rules/lead/delegation-policy.md` | 新規 |
| 2 | `.claude/commands/setup-tickets.md` | 変更 |
| 3 | `.claude/commands/next-ticket.md` | 変更 |
| 4 | `.claude/commands/kickoff.md` | 変更 |
| 5 | `AGENTS.md` | 変更 |
| 6 | `CLAUDE.md` | 変更 |
| 7 | `README.md` | 変更 |
| 8 | `docs/template-dev/codex-delegation-plan.md` | 変更(申し送りの消し込みと注記のみ) |

**`.claude/scripts/` 配下は 1 行も変更しない**(決定 12)。`.harness/decisions.jsonl` と §11 の完了記録は司令塔が振り返りで書くので、実装者は触らない。

---

## 2. 成果物1: `.claude/rules/lead/delegation-policy.md`(新規)

以下を**そのままの内容で**作成する。

````markdown
<!-- テンプレート所有ファイル: /sync-template で上書きされます。プロジェクト固有のルールは CLAUDE.md の「プロジェクト固有ルール」節に書いてください。 -->
<!-- 司令塔専用: SessionStart hook がメインセッションにのみ注入します。サブエージェントには読み込まれません。 -->

## 委託の振り分け(どの単位で Codex に渡すか)

**委託先の既定**は `model-strategy.md` に書いてある(既定 = Codex の `delegate-codex.sh`、`exit 3` なら `implement-ticket` の Sonnet fork)。**このファイルが決めるのは「どの単位で渡すか」**。判定軸はモデルの賢さではなく**往復コスト**で、「仕様が書き切れているか × 途中で設計判断が発生するか」で決める。

| 粒度 | 経路 | 適する作業 | 判定基準(when X) |
| --- | --- | --- | --- |
| **tasklist 1〜3 項目** | `delegate-codex.sh impl` | 定型 CRUD・既存パターンの横展開・リネーム/移行リファクタ・仕様確定済みのテスト追加 | `design.md` に手順まで書けている / 受け入れ確認が `/check` で機械的に済む |
| **チケット 1 枚**(1 Issue = 1 PR) | 同上 + **`delegate:codex` ラベル** | 依存なし(`depends:` 全 closed)・受け入れ条件が Issue に完結・想定差分 300 行以下・**委託禁止領域に触れない**定型機能 | Issue を読んだ第三者が質問なしで実装できると司令塔が判断したとき |
| **行き詰まり調査** | `delegate-codex.sh explore` | 根本原因不明のバグで 2 回連続で修正に失敗したもの | 仮説を書き出してから委譲する |
| **重要変更のレビュー** | `delegate-codex.sh review` | 200 行以上かつ認証・決済・データ移行・アーキテクチャ変更 | `/code-review ultra` の発動条件と同一 |
| **委託しない** | — | **委託禁止領域**(`CLAUDE.md` にパスで列挙)/ **新規依存の追加**(sandbox はネットワーク無効)/ **`.git` を書き換えるタスク**(`workspace-write` では index 操作が必ず失敗する) | ユーザー承認や設計判断の往復が予想されるなら粒度を下げるか fork に残す |

- **最小は「tasklist 1 項目」より下げない。** 関数単位の委託は起動 + 検収コストが生成コストを上回る
- **最大は「1 Issue」で止める。** 複数チケットの一括委託は検収単位が PR 1 本を超え、レビュー精度もマージ判断も破綻する
- 並行数は **1 本まで**(同一ワーキングツリーを共有するため)

### 損益分岐(粒度を満たしていても常に得ではない)

> **「`design.md` を書き切るコスト」<「実装ループのコスト」を満たすときだけ委託する。**

- **既存パターンの横展開**は設計記述が薄くて済む(「A と同じ形で B を作る」)ので成立しやすい
- **新規パターンの 1 例目**は設計記述が厚くなるので成立しない。「参照実装は司令塔が書く」(`model-strategy.md`)と同じ結論になる

### バッチ運用と `delegate:codex`

| チケットの状態 | 実装フェーズの流し方 |
| --- | --- |
| **`delegate:codex` あり** | tasklist を**分割せず 1 回の委託で全体を流す**。検収は PR 単位で 1 回 |
| ラベルなし | 機械的な項目が **3 つ以上連続したら 3 項目前後のバッチ**で委託し、**各バッチの検収を通してから次を委託する**(検収を挟まずに流すと前バッチの欠陥の上に次バッチが積まれる) |
| 機械的な項目が 2 つ以下 | Codex に渡さず `implement-ticket` の fork に渡す |

### ラベルの付け外し(司令塔の判断)

- **付ける**: `/setup-tickets` の発行時(条件が明らかなときだけ)、または `/next-ticket` で `design.md` を書き切った時点
- **外す**: 計画中に禁止領域・新規依存・未確定の設計判断が判明したとき → `gh issue edit [番号] --remove-label delegate:codex`
- **外さない**: `exit 3`(Codex 利用不可)。環境の欠落であってチケットの属性ではない。Sonnet fork にフォールバックするだけ
- **委託が効き始めるのは「真似できる既存パターンが揃った後」**。P0 の基盤チケットには原則付けない。ただし司令塔が参照実装を作り `/check` の検証コマンドが確立した時点からは、P0 の残りの同型タスクにも付けてよい(実質条件はフェーズ名ではなく「参照実装と検収インフラの有無」)

### 実測の記録

チケット完了時に `.harness/decisions.jsonl` へ 1 行追記する(委託先・往復回数・検収の指摘数)。**上の閾値は初期値**であり、この実測で上下させる。
````

---

## 3. 成果物2: `.claude/commands/setup-tickets.md`

### 3-1. ステップ1 の末尾に箇条書きを 1 項目追加する

`- **テンプレートのプレースホルダの回収**: ...` の**次の行**に、同じ階層で以下を追加する。

```markdown
- **委託候補の判定**: 次を**すべて**満たすチケットには `delegate:codex` ラベルを付ける(判定基準の全文は `.claude/rules/lead/delegation-policy.md`)。判断がつかないものには**付けない**(着手時に `/next-ticket` が判定する)。
  - 依存が無い(`depends:` が空、または全て先に完了する)
  - 受け入れ条件が Issue 本文だけで完結している(第三者が質問なしで実装できる)
  - 想定差分が 300 行以下
  - 委託禁止領域(`CLAUDE.md`「プロジェクト固有ルール」)に触れない
  - **P0 の基盤チケットではない**(参照実装と検収インフラが揃うまで委託は成立しない)
```

### 3-2. ステップ2 の表に列を足す

現在の表を次に置き換える(ヘッダと区切り行、例の行すべて)。

```markdown
| # | タイトル | 概要 | フェーズ | 依存 | 優先度 | 委託 |
|---|---|---|---|---|---|---|
| 1 | ... | ... | 1 | - | P0 | - |
```

「委託」列には `delegate:codex` を付ける予定のものに `codex`、付けないものに `-` を書く。

### 3-3. ステップ3-1 のラベル作成に 1 行追加する

`gh label create in-progress ...` の**次の行**に追加する(コードブロック内)。

```bash
gh label create delegate:codex --color 6F42C1 --description "Codex にチケット丸ごと委託する" 2>/dev/null || true
```

### 3-4. ステップ3-2 の `gh issue create` 例の直後に注記を追加する

コードブロックの閉じ `` ``` `` の**次の行**(ステップ4 の見出しより前)に空行を挟んで追加する。

```markdown
   委託候補と判定したチケットには `--label delegate:codex` を追加する(ステップ1 の判定に従う。付けないのが既定)。
```

### 3-5. ステップ4 の完了報告テンプレートに 1 行追加する

`✅ backlog(P1/P2): M 件...` の次の行に追加する(コードブロック内)。

```
✅ delegate:codex 付き: K 件(着手時に Codex へチケット丸ごと委託)
```

### 3-6. 完了条件に 1 項目追加する

最後の箇条書きの後に追加する。

```markdown
- 委託候補と判定したチケットに `delegate:codex` が付いている(該当が 0 件でもよい。判断がつかないものには付けない)。
```

---

## 4. 成果物3: `.claude/commands/next-ticket.md`

### 4-1. ステップ1 の項目 4 を差し替える

現在の

```markdown
4. 選定結果(Issue 番号・タイトル・理由)を 1〜2 行でユーザーに提示してから着手する。
```

を次に置き換える。

```markdown
4. 選定した Issue に **`delegate:codex` ラベルが付いているか**を確認する(ステップ1-1 で取得済みの `labels` を見る。追加の API 呼び出しは不要)。**ラベルの有無は選定順序に影響しない** — 変わるのはステップ3 の実装フェーズの流し方だけ。
5. 選定結果(Issue 番号・タイトル・理由・`delegate:codex` の有無)を 1〜2 行でユーザーに提示してから着手する。
```

### 4-2. ステップ3 の表の直後に節を追加する

「フェーズごとの担当が分かれている点に注意する」の表の直後、`- **司令塔は実装コードを書かない。**` で始まる箇条書きの**前**に、以下を挿入する。

```markdown
**`delegate:codex` ラベルによる実装フェーズの流し方**(判定基準の全文は `.claude/rules/lead/delegation-policy.md`):

| 状態 | 流し方 |
| --- | --- |
| **ラベルあり** | `design.md` を書き切ったら、**tasklist を分割せず 1 回の `delegate-codex.sh impl` で全体を委託する**(バッチに割らない)。検収は PR 単位で 1 回 |
| ラベルなし | 機械的な項目が 3 つ以上連続する部分を 3 項目前後のバッチで委託し、**各バッチの検収を通してから**次を委託する。機械的な項目が 2 つ以下なら Codex に渡さず `Skill('implement-ticket')` に渡す |

- **計画中(steering)に委託の前提が崩れたらラベルを外す**: 委託禁止領域(`CLAUDE.md`「プロジェクト固有ルール」)に触れる / 新規依存の追加が要る / `design.md` に書き切れない設計判断が残る、のいずれかに当たったら `gh issue edit [番号] --remove-label delegate:codex` を実行し、理由を 1 行でユーザーに伝えてから通常経路に落とす
- **`exit 3`(Codex 利用不可)ではラベルを外さない。** 環境の欠落でありチケットの属性ではないため、Sonnet fork にフォールバックするだけでよい
- ラベルが付いていないチケットを委託候補だと判断した場合は、`gh issue edit [番号] --add-label delegate:codex` を実行してから流す(判断の記録が Issue に残る)
```

---

## 5. 成果物4: `.claude/commands/kickoff.md`

### 5-1. フェーズ0 の項目 4(Step 0 チェック)に確認項目と分岐を追加する

`   - Settings → Code security の Secret scanning + Push protection の有効化` の**次の行**に、同じ階層で以下を追加する(その下にある「未実施の項目があっても中断はせず〜」の行はそのまま残す)。

```markdown
   - **ブランチ保護(ルールセット)が使えるプランか**を実際に叩いて確かめる:
     ```bash
     gh api "repos/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/rulesets" --jq 'length'
     ```
     - **数値が返る**(200): 使える。返り値が `0` ならルールセットが未設定なので、`main` に対して「直接 push の禁止 / PR 必須 / force push・削除の禁止」+ required status checks(`branch-policy`・`harness-integrity`・`quality`)+ bypass list を空、の設定を促す
     - **403 が返る**: private + Free プランでブランチ保護もルールセットも使えない。**Codex にコミット権を渡すモード C の前提が崩れる**ため、以下の 3 択をユーザーに提示して選ばせる(選んだ結果をフェーズ6 の完了報告に記載する):
       1. **リポジトリを public にする** — ルールセットが無料で使える。公開して困る資産が無いなら最も安い
       2. **GitHub Pro / Team に上げる** — private のままブランチ保護 + required checks が使える(課金)
       3. **ローカル hook が唯一の層だと認める** — 追加コストゼロだが、`git push` の直接実行を止める層が無く、CI を required check にできない(赤くなるだけでマージを止められない)。この場合は**モード C(Codex にコミットさせる運用)を使わない**ことを併せて合意する
```

### 5-2. フェーズ4 に手順 3 を追加する

フェーズ4 の項目 2(Dependabot)の後に、以下を追加する。

```markdown
3. **委託禁止領域をパスで具体化する**(Codex 併用時。フェーズ2 で `docs/architecture.md` / `docs/repository-structure.md` が確定した後だからここで行う):
   - 認証・決済・データ移行・ガードレールに相当するモジュールを**実際のパス**で洗い出す(例: `src/auth/**`・`src/billing/**`・`db/migrations/**`)
   - `CLAUDE.md`「プロジェクト固有ルール」節に「Codex への委託禁止領域(パス)」として列挙する(判断ルールの正)
   - `AGENTS.md` の `<!-- kickoff:delegation-forbidden-paths -->` 〜 `<!-- /kickoff:delegation-forbidden-paths -->` の**中身を差し替える**(実装者への指示。マーカー自体は消さない)
   - **`.claude/codex-denylist.txt` には書かない。** あちらは「該当ファイルが存在するだけで委託を止める」機密送信のフェイルクローズ検査で、そこにモジュールパスを入れると全委託が常に止まる
```

### 5-3. 完了条件に 1 項目追加する

`- ハーネス層(hooks / permissions / subagents)が設定済み。Dependabot が...` の行の次に追加する。

```markdown
- ブランチ保護の可否が確認済み(不可の場合は 3 択の選択結果が記録されている)。Codex 併用時は委託禁止領域が `CLAUDE.md` と `AGENTS.md` にパスで書かれている
```

---

## 6. 成果物5: `AGENTS.md`

§4「スコープガード」の箇条書き 4 項目の直後、`### design.md の完成マーカー` の**前**に以下の節を挿入する。

````markdown
### 委託禁止領域(パス)

以下のパスに触れる変更は**委託の対象外**です。タスクがこれらの変更を求めている場合、**変更せずに停止して報告してください**(モード C では `codex-log.md` に記録して、その項目だけ飛ばします)。

<!-- kickoff:delegation-forbidden-paths -->
- `.claude/scripts/delegate-codex.sh` — 実行中のあなた自身の起動元。書き換えると親プロセスが構文エラーで死にます
- `.claude/scripts/check-protected-branch.sh` / `.husky/pre-commit` / `.husky/prepare-commit-msg` — ガードレール本体
- `.claude/codex-denylist.txt` — 委託先が自分の送信禁止リストを書き換えることはできません
<!-- /kickoff:delegation-forbidden-paths -->

> プロダクト側のプロジェクトでは、上のマーカーの中身が `/kickoff` フェーズ4 で**そのプロジェクトの実際のモジュールパス**(認証・決済・データ移行など)に差し替えられます。マーカーの行自体は消さないでください。
````

---

## 7. 成果物6: `CLAUDE.md`

「## プロジェクト固有ルール」節の `(まだありません)` を、以下に**置き換える**。

````markdown
### Codex への委託禁止領域(パス)

以下は Codex に委託しない(司令塔または `implement-ticket` の fork が直接書く)。振り分けの判断基準は `.claude/rules/lead/delegation-policy.md`。

- `.claude/scripts/delegate-codex.sh` — 委託の実行中に自分自身が書き換わると、bash の逐次読み込みで親プロセスが死ぬ(2026-08-23 に実測。`docs/template-dev/codex-delegation-plan.md` §9)
- `.claude/scripts/check-protected-branch.sh` / `.husky/pre-commit` / `.husky/prepare-commit-msg` — ベンダー中立ガードレールの本体
- `.claude/codex-denylist.txt` — 委託先が自分の送信禁止リストを編集できてはならない

**機密の送信禁止(`.claude/codex-denylist.txt`)とは別の層。** denylist は該当ファイルが存在するだけで委託を止めるフェイルクローズ検査、こちらは司令塔が「どのチケットを渡すか」を決める振り分け判断。
````

---

## 8. 成果物7: `README.md`

### 8-1. 「チケット1件の実装フロー(委譲構造)」の mermaid を 1 ノードだけ書き換える

```
        LABEL --> PLAN["steering 計画<br/>(.steering/: requirements / design / tasklist)"]
        PLAN --> DELEGATE["Skill('implement-ticket') を呼ぶ<br/>(司令塔は実装しない)"]
```

の 2 行目を次に置き換える(他のノード・エッジは変更しない)。

```
        PLAN --> DELEGATE["実装を委託する<br/>(既定: delegate-codex.sh impl / フォールバック: implement-ticket)<br/>(司令塔は実装しない)"]
```

### 8-2. 「モデル運用方針」の表の「実装フェーズ」行を差し替える

```markdown
| **実装フェーズ**              | **Codex / Sonnet**    | 既定は Codex(`delegate-codex.sh impl`)。使えなければ `implement-ticket` スキル(`context: fork`)が Sonnet で実行。**ユーザーもモデルも切り替えない** |
```

### 8-3. 新しい節を追加する

「## モデル運用方針」の見出しの**直前**(`---` の後)に、以下の節をまるごと挿入する。

````markdown
## Codex 併用の委託運用

Claude の週枠を守るため、実装・調査・レビューの一部を **Codex CLI(ChatGPT Plus 枠)** に委託できる。委託の入口は `.claude/scripts/delegate-codex.sh` の 1 本だけで、司令塔は**終了コードだけを見て**分岐する(サマリーの文面から成否を推測しない)。

### 3 つの運用モード(切替を宣言するのは人間)

| モード | `.harness/mode` | 使いどころ | Claude の役割 |
| --- | --- | --- | --- |
| A(通常) | 未設定 / `normal` | 週枠に余裕がある | 計画・検収・統合をすべて行う |
| B(節約) | `econ` | 週枠を温存したい | `design.md` を書き切ったら閉じる。検収は CI に預け、PR は **draft** で積む |
| C(縮退) | `degraded` | Claude が使えない | 不在。Codex が `.codex/skills/degraded-mode-ticket/` に従って単独で走り、成果をキューとして積む |

`.harness/mode` は **Claude が自分で書き換えない**。モードごとの司令塔の作法は `.claude/rules/mode/*.md` が SessionStart で注入する。

### 委託の粒度と `delegate:codex` ラベル

判定軸は「仕様が書き切れているか × 途中で設計判断が発生するか」で、モデルの賢さではなく**往復コスト**で決める。ルールの全文は `.claude/rules/lead/delegation-policy.md`(司令塔にのみ注入される)。

| 粒度 | 経路 |
| --- | --- |
| tasklist 1〜3 項目 | `delegate-codex.sh impl` |
| **チケット 1 枚**(1 Issue = 1 PR) | 同上 + Issue に **`delegate:codex`** ラベル。`/next-ticket` が tasklist を分割せず 1 回で委託する |
| 行き詰まり調査 / 重要変更のレビュー | `delegate-codex.sh explore` / `review`(read-only) |
| 委託しない | 委託禁止領域・新規依存の追加・`.git` を書き換えるタスク |

> **委託は「`design.md` を書き切るコスト」<「実装ループのコスト」のときだけ得になる。** 新規パターンの 1 例目は前者が大きいので委託しない(参照実装は司令塔が書く)。

### 委託禁止領域

認証・決済・データ移行・ガードレールなど、事故のコストが高い領域は**パスで**列挙して委託対象から外す。判断ルールは `CLAUDE.md`「プロジェクト固有ルール」、Codex 側への指示は `AGENTS.md` §4。`/kickoff` フェーズ4 が、アーキテクチャ確定後にプロジェクトの実パスへ書き換える。

**`.claude/codex-denylist.txt`(機密の送信禁止)とは別の層。** denylist は該当ファイルが存在するだけで委託を止めるフェイルクローズ検査で、モジュールパスを入れると全委託が止まる。

### Codex を使わない場合

Codex CLI が無い・未認証の環境では `delegate-codex.sh` が `exit 3` を返し、**そのセッションは以降ずっと `implement-ticket`(Sonnet fork)にフォールバックする**。`delegate:codex` ラベルが付いていても同じで、テンプレートの全フローは Codex 無しでも成立する。

---
````

---

## 9. 成果物8: `docs/template-dev/codex-delegation-plan.md`(申し送りの消し込みと注記)

**本文の主張は書き換えない。** 以下 5 か所に追記するだけ。

### 9-1. §6 の粒度表(`| **チケット 1 枚**(1 Issue = 1 PR) | ` で始まる行)

セル `` `impl --background` `` を次に置き換える。

```
`impl`(`--background` は未実装。前景で 1 本ずつ)
```

### 9-2. §6「バッチ運用」の段落末尾に 1 文追加する

```markdown
**(段階6 での読み替え)** 「2 項目以下なら司令塔が直接書く」は `implement-ticket` の fork に渡すと読み替える。司令塔の Edit/Write は `check-implementation-phase.sh` がブロックするため、原文のままでは hook と矛盾する。
```

### 9-3. §8 の「プロダクト側のプロジェクトでこのテンプレートを使う場合も同じ検査が要る。」で始まる段落の末尾に追記する

```markdown
**→ 段階6 で実装済み(2026-08-24)**: `/kickoff` フェーズ0 の Step 0 チェックが `gh api repos/{owner}/{repo}/rulesets` を叩き、403 なら上の 3 択を提示する。
```

### 9-4. §9 の自己編集ハザードの箇条書き(`**委託先が `delegate-codex.sh` 自身を編集すると〜`)の末尾 `**未対処**(段階6 までに判断する)` を次に置き換える

```markdown
**判断済み(2026-08-24 / 段階6)**: 回避策は **(b) 起動時に自身を一時ディレクトリへコピーして `exec` する** を採る。実装は段階6 のスコープ外(委託の唯一の入口を、その委託自身に書き換えさせない)とし、別 Issue に切り出す。それまでの当座の防波堤として、`delegate-codex.sh` を **委託禁止領域**(`CLAUDE.md` / `AGENTS.md` §4)に明記した。
```

### 9-5. §10.3 の節末尾に 1 行追記する

```markdown
**→ 段階6 で導線を実装(2026-08-24)**: 判断ルールは `CLAUDE.md`「プロジェクト固有ルール」、実装者への指示は `AGENTS.md` §4 の `<!-- kickoff:delegation-forbidden-paths -->` ブロック。プロダクト側での記入は `/kickoff` フェーズ4 が行う。**`.claude/codex-denylist.txt` には入れない**(フェイルクローズ検査なので、パスを入れると全委託が止まる)。
```

---

## 10. 完了の定義

- 上記 8 ファイルの変更が入っている
- `npm run lint` / `npx prettier --check` が通る(Markdown のみの変更なので型・テストは無関係だが、フォーマッタは通すこと)
- **`.claude/scripts/` と `.harness/` は 1 行も変更していない**
