# 要求: 段階5 — モード C(縮退)の Codex 単独運用

- Issue: [#7](https://github.com/fuji18/claude-codex-template/issues/7)
- 根拠: `docs/template-dev/codex-delegation-plan.md` §2.3 / §7.3 / §12.3 / §13 #4

## 背景

Claude の週枠が尽きた期間でも 1 チケットを完走できるようにする。モード C は**恒久解ではなく数日しのぎ**であり、行き止まりではなく**キュー**として設計する — Codex はブランチにコミットを積むだけで PR を作らず、Claude 復帰後に通常フローの検収 → PR に合流する(§2.3)。

## 実機確認の結果(本チケットで確定 / 2026-08-24)

§13 #4 に残っていた唯一の未確認事項「`.codex/skills/` の project スコープが実際に効くか」を実機(codex-cli v0.149.0)で検証した。

| 確認項目 | 手順 | 結果 |
| --- | --- | --- |
| project スコープの発見 | `.codex/skills/probe-marker/SKILL.md` を置き、`codex exec --cd <repo> --sandbox read-only` で利用可能スキルを列挙させる | ✅ **発見された**。`imagegen` 等のシステムスキルと並んで `probe-marker` が列挙された |
| 本文のロード | 同じ構成で「probe-marker スキルを使って magic word を報告せよ」と指示 | ✅ **ロードされた**。Codex が `cat .codex/skills/probe-marker/SKILL.md` を実行して本文を読み、magic word を正しく報告した |

**帰結: `docs/playbook/codex-standalone.md` への降格は不要。** 配置先は `.codex/skills/` に確定する(§7.3 の第一案)。

**併せて判明した機構**: スキルは「description が一覧に載る → 呼ばれたら Codex 自身が SKILL.md を read する」という遅延ロード方式。読み取りは sandbox の `read-only` でも通る。したがって **description に入口条件を書いておかないと発見されない**一方、**本文は長くても常時コンテキストを消費しない**。

## やること

1. **配置先の確定と実装**: `.codex/skills/` にモード C 用のワークフロースキルを置く
2. **`/next-ticket` 相当の手順の複製**: 作業単位の決定 → 計画(steering 3 点)→ 実装 → コミットまでを Codex 単独で完走できる手順にする
3. **入口検査 4 項目を冒頭に固定する(最重要)**: モード C は `delegate-codex.sh` を通らない**唯一の経路**で、§3.2 の機械的な入口検査がここだけ効かない。順序は `.harness/mode` → 保護ブランチ → `core.hooksPath` → 検証プローブ
4. **`codex-log.md` の運用確定**: `.steering/[dir]/codex-log.md` を引き継ぎの単一ソースとし、Claude 復帰時の検収の入口にする
5. **付随する整合**: テンプレートマニフェストへの登録(§8.2)、README のディレクトリ説明、計画ドキュメントの §7.3 / §13 #4 の結果反映

## やらないこと

- Codex に PR を作らせること(§2.3 で明示的に不採用)
- Codex に push させること(ネットワーク無効。人間が区切りごとに push する = §12.3 手順7)
- Codex に Issue 操作をさせること(ネットワーク無効。Claude 復帰時にまとめて行う)
- `delegate:codex` ラベル運用(段階6 / #8)
- `.harness/mode` を Codex や Claude が自動で書き換えること(切替の宣言は人間の担当)

## 受け入れ条件

- [ ] Claude 不在で 1 チケットを完走できる手順が `.codex/skills/` にあり、実機で発見・ロードされる
- [ ] 入口検査 4 項目が手順の冒頭にあり、`core.hooksPath` 未設定時に実際に停止する
- [ ] `codex-log.md` を読むだけで Claude 復帰時の検収が始められる
- [ ] Codex が PR を作らずコミットのみを積むことが手順上明示されている
- [ ] `.codex/skills/` がテンプレート同期の対象として登録されている
