# 要件: モード C 復帰検査に「名乗らないコミット」の逆向き検査を足す(Issue #84)

## 背景

`check-guard-integrity.sh degraded` の D3(禁止領域への差分)と D4(`package.json` 変更)は、
対象コミットを `git log --grep='Codex-authored'` で選ぶ。このトレーラーは **Codex 自身が付ける**
ものなので、付けなければ両検査の対象から外れる。

トレーラーは「上限で殺されて `codex-log.md` を書けなくても各コミットが自分で名乗る」という
**可用性**の要件から来たもので、その目的には適合している。**敵対的な相手に対する識別子としては
機能しない。** モード C は `.git` が書き込み可能な唯一の経路で、D1〜D4 が唯一の検収層である以上、
その入口が自己申告で開閉できる状態は明示的に塞ぐか、明文化する必要がある。

モード C では**定義上 Claude はコミットしない**ため、範囲内の全コミットがトレーラーを持つのが正常。
逆向きの検査(トレーラーを**持たない**コミットの列挙)は既存の `git log` の引数変更だけで成立する。

## 受け入れ条件(Issue #84 より)

- [ ] `Codex-authored` を持たないコミットが `$DEGRADED_RANGE` にある状態で
      `check-guard-integrity.sh degraded` を回すと、そのコミットが報告される
- [ ] 全コミットがトレーラーを持つ状態では 1 行も出ない(誤検知しない)
- [ ] 報告のみで `exit` の挙動は変わらない(D1〜D4 と同じく `FOUND=1` になるだけ)
- [ ] CI の `harness-integrity` が引き続き緑(既定サブコマンドには載せていないこと)
- [ ] `degraded.md` と `codex-delegation-plan.md` §2.3 の記述が実装と一致している
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み

## スコープ外

- トレーラーの機械的強制(`.husky/prepare-commit-msg` での付与)
- コミット署名(GPG / SSH)の導入
- `git reflog` との突き合わせ
- D3 / D4 のループ本体の共通化(#58 で判断済み)

## 委託方針

**Codex に委託しない。** 変更対象が `.claude/scripts/` / `.claude/rules/` /
`docs/template-dev/`(前 2 者は委託禁止領域)。Issue にも `delegate:codex` は付けない旨が明記されている。
実装は `implement-ticket` の fork が行う。
