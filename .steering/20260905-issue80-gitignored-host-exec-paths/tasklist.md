# タスクリスト: #80 gitignore 済みのホスト実行経路を禁止領域に入れる

設計は `design.md`。**設計判断が必要になったら停止して報告する**(自力で判断しない)。

## 実装

- [x] T1: `delegate-codex.sh` の `FORBIDDEN_PATHS` を修正する(design §2-1 (a))
- [x] T2: `delegate-codex.sh` の配列直前コメントを実態に合わせる(design §2-1 (b)(c))
- [x] T3: `CLAUDE.md` の 3 箇所を配列と一致させる(design §2-2 (a)(b)(c))
- [x] T4: `AGENTS.md` §4 マーカー内の 2 行を更新する(design §2-3 (a)(b))
- [x] T5: `check-guard-integrity.sh` に検査 5(ラッパの source 検査)を追加する(design §2-4)
- [x] T6: `docs/template-dev/CHANGELOG.md` に追記する(design §2-5)

## 検証(design §5 をそのまま回す)

- [x] T7: V1 配列と `--print-forbidden` の出力
- [x] T8: V2 `find .husky -type f` にラッパが出ること
- [x] T9: V3 `check-guard-integrity.sh` が無音化を検出し、復元後に緑へ戻ること(**復元必須**)
- [x] T10: V4 `bash -n` / `check-forbidden-paths-doc.sh` / prettier
- [x] T11: V5 出口検査の再現テスト(到達できなければ理由と終了コードを記録して報告)
- [x] T12: 結果を `verification.md` に記録する(コマンドと実際の出力)

## 検収の指摘反映(code-reviewer 1 巡目: Critical 0 / Major 1 / Minor 2)

司令塔の判断は下に書き切ってある。**新しい設計判断はしない。**

- [x] T13 (Major): `AGENTS.md` §4 マーカー内から、**意図しないバックティック断片を外す**。
      マーカー内のバックティック文字列は `delegate-codex.sh` が無検証で抽出して
      `PROJECT_FORBIDDEN_PATHS` にマージするため、説明のために囲んだ語まで禁止領域に化ける。
      現状の実害はゼロ(`.husky/_/` は `.husky/` の部分集合、裸の `settings.local.json` は
      実在せず `[ -e ]` で落ちる)だが、**同じ diff 内で一度踏んだ罠を 2 箇所残している**ため直す。
      - 150 行目: 説明文中の `` `settings.local.json` `` のバックティックを外して地の文にする
        (行頭の項目名 `` `.claude/settings.local.json` `` は**残す**。あれが本体)
      - 153 行目: 説明文中の `` `.husky/_/` `` のバックティックを外して地の文にする
        (行頭の項目名 `` `.husky/` `` は**残す**)
      - **判断の根拠**: マーカー内でバックティックを使ってよいのは「禁止領域そのもののパス」だけ。
        説明のための例示は地の文で書く。この規約を 153 行目の文末に 1 文で明記すること
        (次に同じ罠を踏まないため。マーカー**内**に書く = 委託先も読む)
- [x] T14 (Minor): `check-guard-integrity.sh` の `WRAPPER_RE` が行末インラインコメントで
      偽陽性を出す件。`(#.*)?` を足して許容する:
      ```sh
      WRAPPER_RE='^[^#]*(source|\.)[[:space:]]+[^#]*/h"?[[:space:]]*(#.*)?$'
      ```
      **行末アンカー `$` は外さない。** 検査 4 の `INVOKE_RE` にアンカーが無いのは
      「どこかで呼んでいれば良い」検査だから。こちらは「source の対象が `h` **である**」ことを
      見る検査で、アンカーを外すと `. "$(dirname "$0")/helper"` の `/h` にも一致して
      **偽陰性(壊れているのに緑)**に倒れる。危険な向きが逆。この差をコメントに 1〜2 文で書く
      (現行コメントの「検査 4 の INVOKE_RE と同じ考え方」は、この差の説明が無いと不正確)
- [x] T15 (Minor): `docs/template-dev/CHANGELOG.md` の 2026-09-05 エントリの
      「取り込む側の作業」に、`.claude/settings.local.json` の追記漏れへの注意を 1 文足す。
      `AGENTS.md` は `template-manifest.json` で `merge`(手動統合)対象のため、
      `.husky/` の行だけ直して hooks 行への追記を見落とす経路が実在する

## 追加検証(V1 の穴を塞ぐ)

- [x] T16: V1 は「意図した 2 エントリが**有る**こと」しか見ておらず、**余計なエントリが
      無いこと**を見ていない(Major の見落としが通った直接の原因)。期待リストとの完全一致で
      検証する:
      ```bash
      cat > /tmp/expected-forbidden.txt <<'LIST'
      .claude/branch-policy.json
      .claude/codex-denylist.txt
      .claude/hooks/
      .claude/rules/
      .claude/scripts/
      .claude/settings.json
      .claude/settings.local.json
      .codex/
      .github/workflows/
      .harness/codex-runs/
      .harness/mode
      .husky/
      .mcp.json
      <!-- verify-probe: ... -->
      AGENTS.md
      CLAUDE.md
      delegate-codex.sh
      LIST
      bash .claude/scripts/delegate-codex.sh --print-forbidden | LC_ALL=C sort -u \
        | diff - /tmp/expected-forbidden.txt && echo "V1b PASS"
      ```
      `delegate-codex.sh` と `<!-- verify-probe: ... -->` は**この変更より前から**
      マーカー内の説明文に含まれている既存の断片で、今回のスコープでは触らない
      (実在検査で落ちるため無害。マーカー内の表記規約は T13 で明文化する)
- [x] T17: T13〜T16 の結果を `verification.md` に追記する。あわせて V1 の記述
      「委託禁止領域の実体・挙動は変えていない」を実測に合わせて訂正する
      (`PROJECT_FORBIDDEN_PATHS` の生の抽出結果は変化していた。指摘 Major の 2 点目)
- [x] T18: 再検証として V3(`check-guard-integrity.sh` の無音化検出 → 復元)と
      `bash -n` / `check-forbidden-paths-doc.sh` / `npx prettier --check` を回し直す。
      **`.husky/_/` を触ったら必ず正規状態に復元し、`check-guard-integrity.sh` が
      無出力・exit 0 に戻ることを確認してから終えること**
