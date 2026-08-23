# 要求定義: 段階3 — 実装委託(delegate-codex.sh impl)と終了コード契約

対象 Issue: [#5](https://github.com/fuji18/claude-codex-template/issues/5)
根拠: `docs/template-dev/codex-delegation-plan.md` §3.2 / §4.1 / §4.2 / §4.4 / §12.6

## 背景

段階2 で作った委託経路は読み取り(`explore` / `review`)だけで書き込みが無い。**Claude の週枠を実際に温存する効果は実装委託でしか出ない**ため、ここが要件(上限対策)の本丸になる。

段階0 の実機検証で 2 つの前提が確定している。両方ともこのチケットの設計を直接縛る:

1. `codex exec` の終了コードは**エージェントのターンが完了したか**を表しており、**タスクの成否を見ていない**。sandbox が起動せず何一つ達成できなかった委託が `exit 0` を返した実測がある
2. `resetAt` は `codex exec --json` からは取得できない(イベント型は 5 種のみで `resets_at` は流れない)

## 満たすこと

| # | 要求 | 受け入れの見方 |
| --- | --- | --- |
| R1 | `delegate-codex.sh impl <.steering/dir>` が Codex を `workspace-write` で駆動し、tasklist を消化させる | 実機の Codex で 1 ステアリングを完走する |
| R2 | 終了コード 0〜5 が契約どおりに返る。特に **`5`(計画未完成)と `2`(タスク起因の失敗)を分ける** | 各コードを再現手順つきで確認する |
| R3 | **`exit 0` を成果の実在で裏取りする**。差分も HEAD も tasklist の進捗も動いていなければ `exit 2` に落とす | 何もしない Codex スタブで `exit 2` になる |
| R4 | run record が状態の正になる(`steering` / `codexSessionId` / `pid` / `accepted` / 時刻を含む) | 会話を捨てても record だけで現在地が分かる |
| R5 | 同じ steering への二重起動を防ぐ | 実行中の record があるとき再実行が拒否される |
| R6 | 入口検査に `design.md` の完成マーカーと `git config core.hooksPath` を足す | draft で `exit 5`、hooksPath 未設定で `exit 3` |
| R7 | `/next-ticket` / `/add-feature` / `/fix-issue` の実装ステップが「Codex 委託 → 終了コードで分岐 → exit 3 なら Sonnet fork に恒久フォールバック」になる | 3 コマンドの散文が同じ分岐表を指す |
| R8 | 中断からの回復(§12.6)が run record 上で成立する | `status` の更新と `accepted` の付与が手段として存在する |
| R9 | 検収の往復回数を §10.7 の形式で記録する | `.harness/decisions.jsonl` に 1 行残る |

## 満たさないこと(スコープ外)

| 項目 | 送り先 |
| --- | --- |
| `.harness/mode` の SessionStart 注入・未検収委託の現在地表示・モード B の司令塔作法 | 段階4([#6](https://github.com/fuji18/claude-codex-template/issues/6)) |
| `--background`(非同期委託) | 段階4。**未検収委託が SessionStart に出るまで、非同期にすると「委託したことを忘れる」経路ができる**(§3.4)。同期実行なら司令塔が必ず結果を見る |
| `fix-ci` モード | 段階外。§3.1 の表には載るが本チケットのスコープに無い |
| `/check` / `/commit` からの `accepted` 自動付与(§3.4) | 段階4。未検収の警告を出す層(SessionStart 注入)と対になる話であり、警告が無い段階で自動化しても効果を測れない |
| `delegate:codex` ラベル運用 | 段階6([#8](https://github.com/fuji18/claude-codex-template/issues/8)) |
| 計画 §8「強制層は 4 段」→「強制 3 層 + 情報提供 1 層」の書き直し | §8 を触るときにまとめて(段階4 以降) |

## 受け入れ条件に対する既知の逸脱(着手前に宣言する)

Issue の受け入れ条件は「終了コードのうち **0 / 4 は実機で確認**」としているが、**`4`(レート上限)は実機で再現できない**。上限に到達するまで枠を消費する行為そのものが本チケットの目的(枠の温存)に反する。

代替として次の 2 つで担保し、その旨を記録に残す:

- `0` は実機で確認する(R1 と同じ委託で兼ねる)
- `4` は `codex` スタブで契約(exit 4・`status: rate-limited`・生エラー 3 行の保存)を確認し、加えて**段階2 の実機ログに `rate_limit_reached` 等の識別子が実在するか**を突き合わせる

## 制約

- **このチケット自身を Codex に実装委託しない。** `delegate-codex.sh` を書き換えながら同じスクリプト経由で走らせるのは自己参照で、失敗時の切り分けが立たない。実装は `implement-ticket` の Sonnet fork が担う
- `delegate-codex.sh` はテンプレート所有(`owned`)で全プロジェクトに配られる。**スタック固有の決め打ち(`node_modules` の有無など)を入れない**
- ネットワーク無効が既定。新規依存を足さない
