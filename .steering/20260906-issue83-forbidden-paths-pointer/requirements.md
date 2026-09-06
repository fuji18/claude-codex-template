# 要求: #83 CLAUDE.md の委託禁止領域節をポインタ化する

- Issue: https://github.com/fuji18/claude-codex-template/issues/83
- 根拠: Codex 併用ハーネス実装レビュー(2026-09-04)C1 / D1、対応順序 4
- depends: #80(closed)

## 背景

### C1: `CLAUDE.md` の大半が司令塔専用の説明で、全サブエージェント spawn に課金されている

着手時点の実測(#80 の反映後。Issue 記載の 5,085 B から増えている):

| 範囲 | サイズ | 読まれる場所 |
| --- | --- | --- |
| `CLAUDE.md` 全体 | 11,368 B | 司令塔 + **全サブエージェント spawn ごと** |
| うち「Codex への委託禁止領域(パス)」節 | **7,845 B(69%)** | 同上 |

この節は「どのチケットを Codex に渡すか」という**司令塔の振り分け判断**の説明で、
`code-reviewer` / `test-runner` / `implementer` / `doc-reviewer` のいずれもこの判断を行わない
(実装者向けの規約は `AGENTS.md` §4、機械検査は `delegate-codex.sh`)。

`context-management.md`「ルールを追記するときの置き場所」に照らすと、
パス一覧と 1 行の理由は `.claude/rules/lead/`、詳細な根拠(#番号への言及・実測値・設計の経緯)は
`docs/template-dev/`(読み込み対象外)に属する。

### D1: 乖離検査が片方向で、実際に穴を見逃している

`check-forbidden-paths-doc.sh` が見るのは「一覧にあって `CLAUDE.md` に無い」方向だけ。
逆向き(「節にあって一覧に無い」)は検出されない。#80 がまさにこの穴だった。
さらに `grep -qF -- ".husky/"` は `.husky/pre-commit` という記述に部分一致するため、
配列を `.husky/` に変えても検査は素通しする。

## スコープ

1. `CLAUDE.md` の当該節をポインタ(数行)に縮める
2. 禁止領域のパス一覧と 1 行の理由を `.claude/rules/lead/delegation-policy.md` へ移す
3. 詳細な根拠を `docs/template-dev/codex-delegation-plan.md` §9 へ移す
4. `check-forbidden-paths-doc.sh` を廃止するか双方向にするかを決める(→ design.md §4 で決定)
5. 上記に伴う参照の張り替え(`README.md` / `.claude/commands/*.md` / `ci.yml` のコメント)

## スコープ外

- `AGENTS.md` §4 の内容を減らすこと(委託先が読む唯一の規約)
- `FORBIDDEN_PATHS` の**内容**変更(#80 で確定済み)
- 司令塔ルール全体の削減(C2 の別チケット)

## 受け入れ条件

- [ ] `CLAUDE.md` の当該節がポインタになっている(削減幅が計測されている)
- [ ] 移した先から元の情報が失われていない
- [ ] 4 の判断が `design.md` に記録されている
- [ ] 双方向(`CLAUDE.md` ではなく移設先の節を対象に)で警告が出る
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
