# 要求定義: 段階4 — モード B(節約)

- 対象 Issue: [#6](https://github.com/fuji18/claude-codex-template/issues/6)(P0 相当の主力機能だがラベルは P1)
- 根拠: `docs/template-dev/codex-delegation-plan.md` §2.1 / §2.2 / §2.6 / §3.4 / §12.2
- 前提: 段階3([#5](https://github.com/fuji18/claude-codex-template/issues/5))完了済み。`delegate-codex.sh impl` / run record / `codex-run.sh` は実機で動く

## 背景

週枠の実効寿命を延ばす主力はモード B(§2.1)。Claude を「`design.md` を書いて黙る」だけに絞り、検収を CI とベンダー中立ガードレールに委ねる。

この運用は**委託を挟んで `/clear`(あるいはセッションを閉じる)ことが前提条件**で、それを支えるのが run record と SessionStart 注入(§3.4)。現状、run record は書かれているが**誰も読んでいない**ため、セッションを閉じると未検収の委託が行方不明になる。

## スコープ(やること)

1. **`.harness/mode` の読み取りを Claude 側にも通す**(§2.2)
   - 値は `normal` / `econ` / `degraded`。ファイルが無ければ `normal`
   - 切替は**人間が宣言する**。Claude は自動降格も自動復帰もしない
   - 現状 Codex 側(`delegate-codex.sh` + AGENTS.md)だけが読んでいる。Claude 側(SessionStart)が読んでいない
2. **未検収 run record の SessionStart 注入**(§3.4)
   - `accepted != true` の record を現在地に 1 ブロック追加する
   - `status=running` なのにプロセスが居ない場合は異常終了(レート上限で殺された等)を疑う表示にする
   - 別ブランチの委託は明示する / 7 日以上経過した記録は調子を落として出す(§3.4 の但し書き)
3. **モード B の司令塔作法をルールとして注入する**(§2.1 / §12.2)
   - `design.md` を書き切ったら検収を待たずセッションを閉じる。`/check` も `code-reviewer` も回さない
4. **モード B の累積制御**(§2.6)
   - モード B 中の PR は **draft で積みマージしない**
   - 枠が戻ったら `ready_for_review` に切り替え、`claude-code-review.yml` の `types: [opened, ready_for_review]` で自動レビューを起動させる

## スコープ外(やらないこと)

- モード C の縮退運用一式(段階5 = #7)。ただし**モード宣言の読み取りは 3 値すべてを対象にする**(`degraded` のときに Claude が起動したらどうするか、という最小の指示だけは置く。読み取り経路を後から作り直さないため)
- `delegate-codex.sh` の新モード追加(段階6 = #8)
- 非 draft PR の**機械的ブロック**(PreToolUse hook 層の追加)。Issue のスコープに無く、§2.6 も「急ぐ場合の例外はユーザーが明示的に判断する」としているため、今回は規約 + コマンド手順に留める(申し送りに残す)
- `docs/template-dev/codex-harness.html`(レンダリング済みの読み物)の追随更新

## 受け入れ条件

- [ ] `.harness/mode` を `econ` にすると Claude 側(SessionStart)と Codex 側(AGENTS.md 手順 / `delegate-codex.sh`)の**両方**に伝わり、両者が同じ値を返す
- [ ] 委託を挟んで `/clear` しても、新セッションの現在地に未検収委託が出る。**`/clear` だけでなく通常の `startup` でも出る**(モード B の実運用では「司令塔がセッションを閉じる → 人間が委託 → 新セッションを開く」が既定経路であり、再開が `clear` とは限らない)
- [ ] draft PR で `ci.yml` は走り `claude-code-review.yml` は走らないことを**実際の PR で**確認する
- [ ] 週枠の実効寿命の**測定方法とベースライン**を記録する(§11 の「検証したいこと」)

## 既知の逸脱(先に宣言する)

**「週枠の実効寿命がどれだけ延びたか」は本チケット内では実測できない。** 測定には「モード B で数チケットを回した後の週次消費」が要り、1 チケットの作業時間には収まらない縦断的な指標である。

本チケットでは代替として次を成立させる:

- 測定方法(何を・どこから取るか)を定義し `.harness/decisions.jsonl` に記録する
- 現時点のベースライン(モード A での 1 チケットあたりの司令塔消費の内訳)を記録する
- 段階5・段階6 の消化時に同じ形式で追記し、段階6 完了時点で比較する

この逸脱は Issue の受け入れ条件を満たさない項目として PR ボディに明記する。
