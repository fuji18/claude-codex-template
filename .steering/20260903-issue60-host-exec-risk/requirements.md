# 要件: 検収時のホスト実行を明文化し、package.json ライフサイクル差分の先行確認を入れる

- Issue: [#60](https://github.com/fuji18/claude-codex-template/issues/60)(P1 / `delegate:codex` は付けない)
- 根拠: Codex 併用ハーネス実装レビュー(2026-08-31)S4 / C4

## 背景

### S4: sandbox が守るのは「委託の実行中」だけ

ネットワーク無効 + `workspace-write` の sandbox は**委託が動いている間**しか効かない。委託が終わった瞬間から、次はすべて「**委託成果をホスト上・ネットワーク有効で実行する**」行為になる:

- `/check` / `test-runner` が回す `npm test` / `npm run lint` — **`package.json` の `scripts` は委託が自由に書き換えられる**(禁止領域外)
- `.husky/pre-commit` が呼ぶ `lint-staged` — 設定も同じく `package.json` 内
- テストコード自体 — 委託成果そのもの

`AGENTS.md` の verify-probe 形式検査(入口検査3)は「AGENTS.md 改ざん → ホスト実行」という細い経路を塞いだが、**より太い経路(`package.json` の scripts / テストコード)は原理的に塞げない**。実質の境界は devcontainer であり、その devcontainer は bubblewrap のために `seccomp=unconfined` で動いていて既定より弱い。

これは「委託成果のコードはいずれ実行する」以上**受け入れるしかない構造**だが、計画書 §9 / §10.2 のリスク一覧に**この形では書かれていない**。受容するなら明文化する。

### C4: 重要変更で発動条件が二択になっている

`delegation-policy.md`(`delegate-codex.sh review`)と `review-policy.md`(`/code-review ultra`)が、**同じ発動条件(200 行以上 × 重要変更)に別の手段を割り当てている**。両方回してしまう運用崩れの余地がある。

## スコープ(やること)

1. `docs/template-dev/codex-delegation-plan.md` §9 に「検収時のホスト実行」をリスクとして追記する(sandbox の保護範囲 / 塞げない太い経路 / 実質の境界が devcontainer で `seccomp=unconfined` / **受容する判断であること**)
2. 検収フローに規約を追加する: **`package.json` のライフサイクル系差分(`scripts` / `lint-staged` / `prepare`)は `/check` を回す前に目視する**。反映先は `code-reviewer` の重点範囲と `review-policy.md` の三層表の近く。**モード B/C での担保も決める**
3. 機械化: 出口検査に「ライフサイクル系に差分があれば**警告**」を足す。**ブロックはしない**
4. C4 の二択を解消し、`delegation-policy.md` と `review-policy.md` の両方に同じ結論を書く

## スコープ外(やらないこと)

- `package.json` を委託禁止領域に入れること(委託が依存やスクリプトを触る正当なケースが多く、委託の余地を過度に狭める)
- devcontainer の `seccomp` 設定変更(bubblewrap = sandbox の実体が動かなくなる)
- 検収を sandbox 内で実行する仕組みの構築(規模が別チケット)

## 受け入れ条件

- [ ] §9 に「検収時のホスト実行」が、**受容する判断であることを含めて**書かれている
- [ ] 検収手順に `package.json` ライフサイクル差分の先行確認が入っている(モード B/C での扱いを含む)
- [ ] `scripts` を書き換えた委託で警告が出て、**かつブロックされない**(実測をもって示す)
- [ ] 200 行以上の重要変更での既定手段が 1 つに決まり、2 ファイルに同じ結論が書かれている
- [ ] `docs/template-dev/CHANGELOG.md` に追記済み
