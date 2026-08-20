# 要件定義: 段階2 — 最小ハーネス(読み取り委託)

正: `docs/template-dev/codex-delegation-plan.md` §11 の段階2。

## 背景

段階1(ベンダー中立ガードレール)が完了し、Claude 以外のクライアントがコミットしても保護ブランチが守られる状態になった。段階2 は**その上に載る最初の委託経路**を作る。

書き込みを伴わない `explore` / `review` に限定するのは、**委託の品質と経路の健全性を、被害の出ない範囲で先に確かめる**ため。実装委託(`impl`)は段階3。

## 解きたい問題

Claude の週枠が枯れると作業が止まる。委託経路が 1 本もない現状では、枠の消費を分散させる手段が存在しない。まず「読み取り専用の委託が成立するか」を確かめる。

## スコープ

### やること

1. `AGENTS.md` の新設(Codex 側への規約の写像。§7.1)
2. `.codex/config.toml` の新設(§7.2)
3. `.claude/scripts/delegate-codex.sh` の新設 — **`explore` / `review` のみ**(§3.1 / §3.2)
4. `.claude/template-manifest.json` への登録(§8.2)
5. `.gitignore` / `.prettierignore` への追記(§8.2)
6. ドキュメント反映(計画文書 §11・§13・CHANGELOG・README)

### やらないこと(段階3 以降)

| 項目 | 段階 | 理由 |
| --- | --- | --- |
| `delegate-codex.sh impl` / `fix-ci` | 3 | 書き込みを伴う。読み取り委託の品質を確かめてから |
| `design.md` の完成マーカー検査(exit 5) | 3 | `impl` にしか意味がない(`explore` / `review` は steering を取らない) |
| run record の SessionStart 注入 | 4 | 未検収委託が生じるのは `impl` から |
| `.harness/mode` による司令塔の作法 | 4 | — |
| `.codex/prompts/` | 5 | モード C 用。ただしマニフェスト登録は今回行う(§8.2) |
| `delegate:codex` ラベル | 6 | — |

**`.harness/mode` の読み取り自体は今回から実装する。** モードは `AGENTS.md` の起動時手順にも書く必要があり(§7.1)、段階4 まで空白にすると「モードを読む経路が無い AGENTS.md」を一度配って後から差し替えることになる。ファイルが無ければ `normal` とみなす既定があるので、段階2 時点で入れても害が無い。

## 受け入れ条件

### 機能要件

| # | 条件 | 検証方法 |
| --- | --- | --- |
| F1 | `delegate-codex.sh` が `explore` / `review` を受け付け、未知の mode を拒否する | 直接実行 |
| F2 | Codex CLI 不在・未認証で **exit 3**(恒久フォールバック)を返す | 現環境がそのまま該当ケース |
| F3 | レート上限を検出したら **exit 4**(一時フォールバック)を返す | JSONL イベントのスタブで検証 |
| F4 | 標準出力は固定フォーマットの要約のみ。生ログは `.harness/codex-runs/[id].log` | 直接実行 |
| F5 | run record(`.harness/codex-runs/[id].json`)を起動時と終了時に書く | 直接実行 |
| F6 | 委託前に機密ファイル(`.env` / `*.pem` / `id_rsa*` / `credentials*`)を検出したら確認を求める | ダミーファイルで検証 |
| F7 | 検証コマンドの空実行に失敗したら委託せず exit 3 | AGENTS.md の検証コマンドを壊して検証 |
| F8 | sandbox は **CLI フラグで明示的に** `read-only` を渡す(設定ファイルに依存しない) | 生成されるコマンド列の確認 |
| F9 | 入力は参照渡し(ファイル内容をプロンプトに貼らない) | スクリプトの読み取り |

### 非機能要件

| # | 条件 |
| --- | --- |
| N1 | Codex CLI が無い環境でも、スクリプトの実行自体は正常終了する(exit 3 で明示的に落ちる。異常終了しない) |
| N2 | スタック非依存(`node_modules` の有無を決め打ちで見ない)。テンプレート所有ファイルとして全プロジェクトに配られる |
| N3 | `bash -n` を通る。既存スクリプトと同じ `set -uo pipefail` の作法に揃える |
| N4 | 司令塔のコンテキストに長いログを積まない |

## 前提の検証結果(§13 の一括検証)

段階0 が未達(Codex CLI 未インストール)のため実機検証はできないが、**公開ドキュメントで 5 件が確定**した。実機でしか確かめられない 2 件は段階3 に持ち越す。

| # | 確かめること | 結果 | 出典 |
| --- | --- | --- | --- |
| 1 | `codex exec` のオプション体系と sandbox の指定方法 | **確定**。`codex exec --sandbox read-only\|workspace-write\|danger-full-access`、`--json`、`--output-last-message,-o`、`-c key=value`、`--cd,-C`、`--model,-m` | Codex CLI リファレンス |
| 2 | レート上限に固有の終了コードを返すか | **返さない**。ただし `--json` のイベントに `rate_limit_reached` / `usage_limit_reached` / `credits_depleted` という**構造化された識別子**が流れる。文言マッチより頑健な材料がある | openai/codex の issue 群 |
| 3 | sandbox のネットワーク無効が CLI 自身の通信を妨げないか | **妨げない**。sandbox はエージェントが実行する**コマンド**に掛かる層で、CLI 自身のモデル API 通信は外側 | 設定リファレンス |
| 4 | `.codex/prompts/` の project スコープ対応 | **未確定**(段階5 で確認)。project スコープの `.codex/` レイヤに config・hooks・rules があることは確認できたが、prompts の記載が見つからない | — |
| 5 | Codex CLI がこの devcontainer で動くか | **未検証**(段階0)。段階3 で確認 | — |
| 6 | レート上限のリセット単位と `resetAt` の取得可否 | **5 時間枠 + 週次**。`resetAt` の機械的取得は未確定 | 公開情報 |
| 7 | `.codex/config.toml` にパス単位の読み取り除外があるか | **無い**。sandbox は**書き込み**の制限であり、読み取りの deny-list は存在しない | 設定リファレンス(advanced) |

### 検証で判明した、計画の修正が要る点

1. **`.codex/config.toml` は防衛線として当てにできない**(§9 の「唯一の防衛線」は不正確)
   - CLI フラグと `-c` が project config に**優先する**
   - project を untrusted にすると `.codex/` レイヤが**丸ごと読まれない**
   - → `delegate-codex.sh` は sandbox を**フラグで明示的に**渡す。設定ファイルは「人間が直接 `codex` を叩くとき(モード C)の既定」という位置づけに降格する
2. **§13 #7 が「無い」で確定したため、機密チェックは段階2 で必須**(段階3 に送れない)。読み取り委託でも `.env` は読める
3. **exit 4 の判定は `--json` のイベント識別子で行う**。§3.2 の「stderr のパターンマッチに降格」より一段良い材料が使える

## 制約

- Codex CLI は未インストール。実機での往復検証はできない
- したがって**「Codex が正しく動く」ことは今回検証できない**。検証できるのは「委託経路が正しく壊れる(exit 3 / 4 / 機密検出で止まる)」ことまで
- ChatGPT Plus 契約の有無は未確認(段階0)

## 完了の定義

- 上記 F1〜F9 / N1〜N4 を満たす
- `bash -n` と `npm run format:check` を通る
- CI の `harness-integrity` を通る
- 計画文書 §11 の段階2 が「完了」に、§13 の検証結果が反映されている
