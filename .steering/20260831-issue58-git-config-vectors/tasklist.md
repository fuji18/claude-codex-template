# タスクリスト: モード C 復帰検査に `.git/config` の実行ベクタ検査(D2.5)を追加する(Issue #58)

design.md の §番号に対応する。上から順に消化する。

## 実装

- [x] §1 `.claude/scripts/check-guard-integrity.sh` の D2 と D3 の間に D2.5 ブロックを挿入する(D1/D2/D3 は変更しない)
- [x] §2 変更1 `docs/template-dev/codex-delegation-plan.md` §12.3 の手順 7 に push 前検査の 1 文を足す(手順番号は増やさない)
- [x] §2 変更2 同ファイル §9 付近の `(§12.3 手順 6)` を `(§12.3 手順 7)` に直す(この 1 語のみ)
- [x] §3 `.claude/rules/mode/degraded.md` の復帰検収 手順 1 に 1 行足す(他の行は変更しない)

## 検証

- [x] §4-0 `bash -n` を通し、`.git/config` に危険キーが 0 件であることを確認する
- [x] §4-1 平常状態で D2.5 由来の出力が 0 行であることを実測する(受け入れ条件 2)
- [x] §4-2 C1〜C9 が検出されることを実測する(C1 = 受け入れ条件 1)
- [x] §4-2 C10(`!` 無し alias)が**検出されない**ことを実測する
- [x] §4-3 長大な値が 1 行に切り詰められ末尾が `…` になることを実測する
- [x] §4-4 後始末: `.git/config` に検証用キーが 1 つも残っていないことを確認する
- [x] §4 実測結果を `verification.md` に表で記録する(判断4 の alias 実測結果も残す)

## 記録

- [x] §5 `docs/template-dev/CHANGELOG.md` の既存 `## 2026-08-31` 見出しの先頭に追記する
- [x] §6 品質チェック(`bash -n` / lint / typecheck / format:check)を通す

---

## 申し送り(振り返り)

**実装完了日**: 2026-09-01(計画・1 巡目実装は 2026-08-31)

### 計画と実績の差分

| 項目 | 計画 | 実績 | 理由 |
| --- | --- | --- | --- |
| 対象キー | 判断4 の表で確定(`core.fsmonitor` / `core.sshCommand` / `core.pager` / `credential.*.helper` / `filter.*.clean\|smudge` / `include.path` / `includeIf.*.path` / `alias.*`)| **7 パターン追加**(`core.editor` / `sequence.editor` / `core.gitProxy` / `url.*.insteadOf\|pushInsteadOf` / `diff.*.command` / `merge.*.driver`)| 検収 1 巡目の Major 指摘。判断4 の表自体が「D1 は 1 キーしか見ていない = 非対称」という本チケットの動機に対して、**D2.5 の内部に同じ非対称を残していた** |
| 検証シナリオ | C1〜C10 | C1〜C18 | 上記追加分の実測(判断9)|
| 巡回数 | 1 巡想定 | **3 巡**(実装 → 検収1巡目 Major1/Minor3 → 検収2巡目 Minor1)| 下記「学び」1 を参照 |
| `.codex/skills/degraded-mode-ticket/SKILL.md` | スコープ外 | 変更対象に追加 | 検収 1 巡目の Minor 指摘(§7)。Codex 自身が読む説明が検査範囲を過小に伝えていた |

計画どおりだった点: スコープ外(`.git/config` の書き込み自体は止めない / `--global` `--system` は見ない / セキュリティ境界としない / D1・D2・D3 は変更しない / `degraded` サブコマンド限定)は 3 巡を通して 1 つも崩れていない。受け入れ条件 4 件はすべて `verification.md` の実測で充足。

### 学んだこと・次への申し送り

1. **「非対称を直す」チケットは、直した先で同じ非対称を再生産しやすい。** 本チケットの動機は「D1 が `core.hooksPath` 1 キーしか見ていないのは非対称」だった。ところが 1 巡目の判断4 は対象キーを 8 パターンに閉じ、`url.*.insteadOf`(既知の git RCE 手口で `credential.helper` より発火条件が緩い)を落としていた。**動機に使った物差しを、自分の成果物にも当て直す**工程を計画フェーズに入れる。次に「検査範囲が狭い」系のチケットを設計するときは、`design.md` に「この表を D1 と同じ基準で見たとき漏れているものは何か」を 1 節設ける。
2. **閉リストであることは、コードに書いておかないと次のレビューで必ず再指摘される。** 検収 2 巡目の唯一の Minor がこれ(`core.askpass` / `http.proxy` / `gpg.program` がスコープ外のまま)。判断4 で意図的にクローズした判断は正しかったが、その意図が `design.md` にしか無くコードから読めなかった。判断10 でヘッダコメント 2 行を足して解決。**「増やさない」という設計判断は、増やす提案が来る場所(=コード)に痕跡を残す。**
3. **司令塔のコンテキストに毎回注入されるファイルへの追記は、追記前に既存文を読む。** §8 の Minor は「1 巡目の追記が直前の既存文と同じ D1/D2/D3 を再列挙していた」というもの。`.claude/rules/` は SessionStart hook で毎ターン注入されるため、重複は恒久コストになる(`context-management.md` の方針)。`rules/` 配下への追記タスクは、`design.md` に**置換前・置換後の全文**を書く形にしたのが有効だった(2 巡目はこの形式にしたため一発で通った)。
4. **実測の型(スタブ + 使い捨て検証)は今回も効いた。** `.git/config` に危険キーを仕込む → 検出を確認 → `--unset-all` + `--remove-section` で後始末 → 残留 0 件を確認、という手順を `verification.md` に表で残した。`--unset-all` だけでは空セクションが残る点は判断9 で手順に反映済み。**次に同種の検査を足すときはこの後始末手順ごと再利用する。**
5. **環境依存の実測値には注記を付ける(§9)。** 判断2(`--local` 限定)の根拠は「devcontainer が `--global` / `--system` に `credential.helper` の `!` 形式を既定で置いている」という**この 1 インスタンスの実測**。テンプレートとして配布された先では成立しないことがある。`verification.md` 末尾に注記済み。
6. **並行制約は守られている。** #59(`hooksPath` 判定の一本化)は同じ `check-guard-integrity.sh` を触るため、本チケットを先に入れる約束だった。#59 には未着手。**本 PR のマージ後に着手すること。**

## 2 巡目(検収 1 巡目の指摘反映。design.md「追補」に対応)

- [x] 判断9 `check-guard-integrity.sh` の D2.5 の `case "$_key"` に 5 行(7 パターン)を `alias.*)` の直前へ追加する
- [x] 判断9 §4-2 に C11〜C18 を追加して実測し、`verification.md` の表に追記する(C18 は司令塔の実測結果を転記)
- [x] 判断9 §4-4 の後始末を再実行し、空セクション込みで残留 0 件を確認する
- [x] 判断9 CHANGELOG の 1 つ目の `[auto]` 項目のキー列挙を差し替える
- [x] §7 `.codex/skills/degraded-mode-ticket/SKILL.md` の検出範囲の記述に D2.5 を足す
- [x] §8 `.claude/rules/mode/degraded.md` の重複を解消する(正味の行数を増やさない)
- [x] §9 `verification.md` の末尾に環境依存の注記を 1 行足す
- [x] 品質チェック(`bash -n` / lint / typecheck / test / format:check)を通す

## 3 巡目(検収 2 巡目の指摘反映。design.md「追補2」に対応)

- [x] §10 判断10 `check-guard-integrity.sh` の D2.5 ヘッダコメントに閉リストである旨の 2 行を挿入する
- [x] 品質チェック(`bash -n` / lint / typecheck / test / format:check)を通す
