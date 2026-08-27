# 要件: チケット完了時の記録漏れ(CHANGELOG / decisions.jsonl)を機械的に検出する

- Issue: #37(P2 / `ticket`)
- 起点: `/sync-docs`(2026-08-26)の乖離レポート、`.steering/20260825-docs-impl-drift/tasklist.md` の振り返り

## 背景

チケット完了時に書くべき記録が 2 つあり、どちらも**散文の運用ルールだけに依存している**。

1. `docs/template-dev/CHANGELOG.md` — #20〜#29 の **8 件連続で追記されなかった**。`/sync-template` は `syncedAt` 以降の日付見出ししか読まないため、取り込む側が `[manual]` 4 件に気づけない状態だった
2. `.harness/decisions.jsonl` — #23 の 1 件が欠けていた。司令塔が検収指摘の反映まで自分で手を動かし、**通常の検収フローから外れた分岐**で落ちた

1 は初回ではない。2026-08-25 の振り返りで「4 回連続で守られなかった」ことが記録され、**同じ CI チェックが既に提案されていた**。散文の宿題として書いただけで消化されず、直後に 8 件連続で再発している。**散文をもう一段強く書き直しても効かない**ことが 2 回の実測で分かっている、というのがこのチケットの前提。

## 機能要件

### FR-1: CHANGELOG 記載漏れの検出

- PR の変更差分が `.claude/` / `.husky/` / `.codex/` / `AGENTS.md` のいずれかを含み、かつ `docs/template-dev/CHANGELOG.md` を含まない場合に検出する
- 検出時は **ジョブを失敗させる**(判定を落とす)。加えて `::error::` annotation と Job Summary に必ず出す
- ラベル `no-changelog` が PR に付いている場合は検出しない(逃げ道)

### FR-2: decisions.jsonl 記載漏れの検出

- PR ボディの close キーワード(`Closes #N` 等)で参照される Issue のうち、**`ticket` ラベルが付いているもの**を対象とする
- 対象 Issue 番号 N について、`.harness/decisions.jsonl` に `"issue": N` の行が無ければ検出する
- 検出時の扱いは FR-1 と同じ(ジョブ失敗 + annotation + Summary)
- ラベル `no-decision-record` が付いている場合は検出しない(逃げ道)

### FR-3: 起動点

- 両チェックとも **PR 時**に走らせる。トリガの `types` にラベル増減とボディ編集を含め、**逃げ道ラベルの付与と `Closes #N` の追記が即座に再判定される**ようにする
- 既存 `ci.yml` には同居させない(`types` の拡張が `quality` ジョブまで巻き込んで再実行されるため)

### FR-4: 運用への反映

- `.claude/rules/lead/delegation-policy.md`「実測の記録」に、記録のタイミングと逃げ道ラベルを明記する
- `docs/template-dev/CHANGELOG.md`「記法」に、CI で機械的に検査される旨と逃げ道ラベルを明記する
- 本チケット自身の変更を CHANGELOG に追記する(取り込む側はラベル 2 つの作成が要る = `[manual]`)

## 非機能要件

- CI は Claude の枠を消費しない(`.claude/rules/lead/review-policy.md`)。ネットワーク越しの判定は `gh` + `GITHUB_TOKEN` のみで完結させ、シークレット追加を要求しない
- 判定ロジックは `.claude/scripts/` のシェルスクリプトに置き、**環境変数だけで手元から同じ判定を再現できる**ようにする(CI の yaml 内にロジックを埋めない)

## スコープ外

- CHANGELOG 本文の自動生成(何を書くかが価値であり、コミットメッセージの転記では `[manual]` の判断が落ちる)
- `decisions.jsonl` の書式変更・スキーマ検証(今回は「行が存在するか」だけ)
- 過去分の遡及チェック(#20〜#29 は `90691f6` / `04b8ef8` で解消済み)

## 受け入れ条件(Issue より)

- [ ] `.claude/` を変更し `CHANGELOG.md` を変更しない PR で、チェックが検出する(実際に PR を立てて確認する)
- [ ] `CHANGELOG.md` を変更した PR では鳴らない
- [ ] 逃げ道(ラベル)が効くことを確認した
- [ ] `decisions.jsonl` チェックの起動点が決まっており、その根拠が記録されている
- [ ] 運用が `.claude/rules/lead/delegation-policy.md` に反映されている

## 委託判断

**Codex に委託しない。** 対象に `.github/workflows/`(委託禁止領域)を含むため。Issue にも `delegate:codex` は付けない旨が明記されている。実装は `implement-ticket`(Sonnet fork)に渡す。
