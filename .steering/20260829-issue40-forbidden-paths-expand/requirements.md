# 要件: 委託禁止領域に CI/hook の判定実体を含める(Issue #40)

## 背景

`FORBIDDEN_PATHS`(`.claude/scripts/delegate-codex.sh`)は `.github/workflows/` を守っているが、
**そのワークフローが `bash` で呼ぶ判定スクリプトの実体は守っていない**。定義を守っても、
定義が実行する実体が書き換え可能なら防御は成立しない。

守られていない実体と、書き換えられたときに静かに成立する状態:

| パス | 骨抜きにされたときの状態 |
| --- | --- |
| `.claude/scripts/check-record-hygiene.sh` | 冒頭に `exit 0` を 1 行足すだけで #37 の記録漏れ検査が全 PR で無効化される |
| `.claude/scripts/check-guard-integrity.sh` | husky 層が消えたことに気づけなくなる(このハーネスが最も恐れる状態) |
| `.claude/scripts/codex-run.sh` | 委託先が自分の run record を `accepted` にできる |
| `.claude/settings.json` | PreToolUse hook の定義そのもの |
| `.claude/hooks/session-start.sh` | 司令塔コンテキストへの注入元(プロンプトインジェクション経路) |

## 要求

1. **R1**: `FORBIDDEN_PATHS` に `.claude/scripts/` / `.claude/hooks/` / `.claude/settings.json` を追加する。
   個別列挙はスクリプトが増えるたびに同じ漏れを繰り返すため、**ディレクトリ単位**で足す。
   既存の `.claude/scripts/delegate-codex.sh` / `.claude/scripts/check-protected-branch.sh` は
   `.claude/scripts/` に包含されるので削除する。
2. **R2**: 記述を 3 箇所同時に更新する(単一ソースは配列側だが、乖離すると委託判断が狂う)。
   `delegate-codex.sh` の配列 / `AGENTS.md` §4 マーカー内 / `CLAUDE.md`「Codex への委託禁止領域(パス)」節。
3. **R3**: 既存の impl 委託が壊れないことを実測で確認する(禁止領域に触れない委託は従来どおり成功する)。
4. **R4**: `docs/template-dev/CHANGELOG.md` に追記する(`AGENTS.md` は `merge` 区分 = `[manual]`)。

## スコープ外

- `.claude/` 全体をディレクトリごと禁止にすること。`.claude/skills/` / `.claude/commands/` /
  `.claude/agents/` / `.claude/rules/` の定型追記まで止めると委託の余地が過剰に狭まる。
  今回は**実行される実体**(scripts / hooks / settings)に限る
- `.claude/settings.local.json` の扱い変更(gitignore 対象。`.claude/settings.json` を
  完全一致で列挙するため今回も対象外のまま)
- `.husky/` のディレクトリ化(現行の 2 ファイル個別列挙を維持する)
- 判定順序(禁止領域 > レート上限)の変更

## 受け入れ条件

- [ ] `.claude/scripts/check-record-hygiene.sh` を変更する impl 委託が `status=failed` / `exit 2` で止まる(実測)
- [ ] `.claude/hooks/session-start.sh` / `.claude/settings.json` でも同様に止まる(実測)
- [ ] 禁止領域に触れない通常の impl 委託が従来どおり成功する(回帰確認)
- [ ] `AGENTS.md` §4 と `CLAUDE.md` の記述が配列と一致している
- [ ] `.claude/scripts/` 追加後のスナップショットコストを 1 回計測して記録する
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
