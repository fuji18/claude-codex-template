# 要求: 委託禁止領域の適用漏れを塞ぐ(Issue #56)

/ 根拠: `docs/template-dev/harness-review-20260831.html` S1 / S2 / S6(優先度表 P0)

## 背景

「委託禁止領域が守るのは**実行される実体**」という現行の原則に、適用漏れが 3 系統ある。
いずれも `delegate-codex.sh` の `FORBIDDEN_PATHS` に無く、impl 委託が書き換えても
**出口の内容ハッシュ検査に掛からない**。

| 系統 | 対象 | 漏れの性質 |
| --- | --- | --- |
| S1 | `.claude/branch-policy.json` | 保護ブランチ検査の全 3 層が読む**判定データ**。ロジックは `check-protected-branch.sh` に一本化して守られているが、データが守られていない。`check-guard-integrity.sh` の検査1 は「`protectedBranches` が空か」しか見ないため、`["develop"]` への差し替えは**全層が正常動作したうえで素通し**する形で通り、guard-integrity も緑のまま |
| S2 | `.claude/rules/` / `CLAUDE.md` / `.mcp.json` | `.claude/settings.json` を禁止した理由(司令塔コンテキストへの注入元)と同じ性質を持つのに保護されていない。`rules/` は SessionStart hook と CLAUDE.md 経由で本文がそのまま注入されるため、1 段落の追記が**恒久的な指示注入の足場**になる |
| S6 | `.codex/` | 「Codex 自身は `.codex/` に書けない」は codex-cli v0.149.0 の**実測に依存した前提**。CLI 更新で崩れると、モード C の手順書と `network_access` 設定が書き換えられうる。検査に加えるコストはほぼゼロ |

モード B / C は検収レビューそのものを飛ばす設計なので、この 3 系統の担保は
CHANGELOG 検査(逃げ道ラベルあり)しか残っていない。

## 要求

1. `FORBIDDEN_PATHS` に S1 / S2 / S6 の対象を追加し、出口検査の対象にする
2. 単一ソース 2 系統(配列 / `AGENTS.md` §4 マーカー)と説明(`CLAUDE.md`)の 3 箇所を**同時に**一致させる
3. 追加によって正常な委託が誤爆しないこと(不在パス・sandbox で書けない想定のパスを含む)

## 受け入れ条件(Issue #56 より)

- [ ] 追加した各パスを書き換えた状態で impl 委託を流すと、出口検査が `status=failed` / `exit 2` で止まる(使い捨てステアリングで最低 2 パス実測)
- [ ] `.codex/` のように「そもそも sandbox で書けない」想定のパスを含めても、正常な委託が通る(誤爆しない)
- [ ] `AGENTS.md` §4 / `CLAUDE.md` の列挙が配列と一致している
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## スコープ外

- `check-guard-integrity.sh` のポリシー整合検査の強化(Issue #59 / A1・A5)
- `CLAUDE.md` と `--print-forbidden` の記述ずれの CI 機械検査(Issue #64 / A4)
- `forbidden_snapshot()` の `git hash-object` バッチ化(Issue #65 / C3)
- `skills/` / `commands/` / `agents/` / `docs/` を禁止領域に入れること(**意図的に除外**)

## 委託方針

**Codex に委託しない。** 変更対象が委託禁止領域そのもの(`.claude/scripts/` / `AGENTS.md` /
`CLAUDE.md`)であり、委託した時点でその委託自身が出口検査で `failed` になる。
Issue にも `delegate:codex` は付けない方針が明記されている。実装は `implement-ticket` の fork が行う。
