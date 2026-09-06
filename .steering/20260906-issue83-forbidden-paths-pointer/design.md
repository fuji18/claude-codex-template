<!-- status: ready -->

# 設計: #83 委託禁止領域節のポインタ化 + 乖離検査の双方向化

## 0. 全体像(どこに何を置くか)

| 置き場所 | 置くもの | 読まれる場所 |
| --- | --- | --- |
| `delegate-codex.sh` の `FORBIDDEN_PATHS` | **汎用項目の単一ソース**(変更なし) | 機械のみ |
| `AGENTS.md` §4 マーカー内 | **プロジェクト固有パスの単一ソース** + 委託先向け散文(変更なし) | 委託先 |
| `.claude/rules/lead/delegation-policy.md` | **パス一覧 + 1 行の理由**(新設。汎用項目のみ) | 司令塔のみ |
| `docs/template-dev/codex-delegation-plan.md` §9.1 | **詳細な根拠**(#番号・実測・設計の経緯) | 読み込み対象外 |
| `CLAUDE.md` | **ポインタ 5 行のみ** | 司令塔 + 全サブエージェント |

## 1. `CLAUDE.md`「### Codex への委託禁止領域(パス)」節の置換

**節見出しは変えない**(`README.md` / `/kickoff` / `check-forbidden-paths-doc.sh` の旧 HEADING が参照している。
見出しを残したままポインタ化するのが最も影響が小さい)。

見出し行の**次の行から、次の `## ディレクトリ構造(要点)` の直前まで**を、以下で丸ごと置き換える:

```markdown

事故のコストが高い領域は Codex に委託せず、**司令塔または `implement-ticket` の fork が直接書く**。対象は 3 系統 —— (1) 実行される実体、(2) コンテキストへ注入される実体、(3) 全層が読む判定データ。

- **一覧を出す**: `bash .claude/scripts/delegate-codex.sh --print-forbidden`(プロジェクト固有パスを含む全量)
- **単一ソースは 2 系統**: 汎用項目 = `delegate-codex.sh` の `FORBIDDEN_PATHS` / プロジェクト固有パス = `AGENTS.md` §4 の `<!-- kickoff:delegation-forbidden-paths -->` マーカー内。**追加・変更はこの 2 箇所だけを直す**(出口検査が委託の開始時に両方を抽出してマージし、前後の内容ハッシュ差分を `status=failed` / `exit 2` で止める)
- **振り分けの判断材料**(パス一覧と 1 行の理由)は `.claude/rules/lead/delegation-policy.md`、**なぜそのパスなのか**の詳細は `docs/template-dev/codex-delegation-plan.md` §9.1
- **機密の送信禁止(`.claude/codex-denylist.txt`)とは別の層。** denylist は該当ファイルが存在するだけで委託を止めるフェイルクローズ検査、こちらは司令塔が「どのチケットを渡すか」を決める振り分け判断

```

**注意**: 上の本文に登場するバックティック囲みのパス(`.claude/scripts/delegate-codex.sh` など)は
実在するため、旧 `check-forbidden-paths-doc.sh` の照合対象になり得る。だが §4 の変更で照合先が
`delegation-policy.md` に移るので問題にならない。

## 2. `.claude/rules/lead/delegation-policy.md` への一覧の移設

### 2-1. 既存記述の修正

L14 の「委託しない」行:

```
| **委託しない** | — | **委託禁止領域**(`CLAUDE.md` にパスで列挙)/ **新規依存の追加**...
```

を次に変える(参照先だけの差し替え。他は一字も変えない):

```
| **委託しない** | — | **委託禁止領域**(下の一覧)/ **新規依存の追加**...
```

### 2-2. 新しい節の挿入位置

`### 重要変更のレビューは ...` 節の**直前**(= L18 の箇条書きと L20 の見出しの間)に、
以下の節を丸ごと挿入する。

```markdown
### 委託禁止領域(パス一覧)

事故のコストが高い領域は委託しない。**単一ソースはここではない** —— 汎用項目は
`delegate-codex.sh` の `FORBIDDEN_PATHS`、プロジェクト固有パス(認証・決済・データ移行などの実パス)は
`AGENTS.md` §4 のマーカー内が正で、`/kickoff` フェーズ4 が書く。下の表は**汎用項目だけ**の写しで、
司令塔が振り分けを判断するために置いてある(CI の `harness-integrity` ジョブが双方向で照合する)。
プロジェクト固有パスを含む全量は `bash .claude/scripts/delegate-codex.sh --print-forbidden` で出る。
**なぜそのパスなのか**の詳細は `docs/template-dev/codex-delegation-plan.md` §9.1。

<!-- forbidden-paths -->
| パス | 渡さない理由(1 行) |
| --- | --- |
| `.claude/scripts/` | 委託の唯一の入口・保護ブランチ判定・CI が `bash` で呼ぶ判定の実体。1 行の書き換えで検査が静かに無効化される |
| `.claude/hooks/` | PreToolUse / SessionStart hook の実体。司令塔コンテキストへの注入元でもある |
| `.claude/settings.json` | hook の定義そのもの(どのコマンドを止めるかの宣言) |
| `.claude/settings.local.json` | 同上。gitignore 済みで `git diff` に出ないが、次に人間がセッションを開いた瞬間にホストで走る |
| `.claude/branch-policy.json` | 保護ブランチ検査の全 3 層が読む判定データ。書き換われば全層が「正常に動作したうえで素通し」する |
| `.claude/rules/` | 司令塔と全サブエージェントのコンテキストへ本文がそのまま注入される |
| `.husky/` | ベンダー中立ガードレールの本体と、git が実際に起動する入口(`.husky/_/`。git 追跡外) |
| `.claude/codex-denylist.txt` | 委託先が自分の送信禁止リストを編集できてはならない |
| `AGENTS.md` | 委託先の憲法。冒頭の verify-probe は次回委託時にホスト上で読まれる |
| `CLAUDE.md` | 全エージェントに毎回ロードされる = `rules/` と同じ注入経路 |
| `.mcp.json` | MCP サーバ定義 = セッション開始時のローカルプロセス起動指示 |
| `.github/workflows/` | 非 fork PR で `CLAUDE_CODE_OAUTH_TOKEN` にアクセスできる定義そのもの |
| `.codex/` | Codex 側の設定(`network_access` 等)とモード C の手順書 |
| `.harness/mode` | 委託先がハーネスモードを詐称できてはならない |
| `.harness/codex-runs/` | 委託先が自分の結果を `accepted` に書き換えられてはならない |
<!-- /forbidden-paths -->

**機密の送信禁止(`.claude/codex-denylist.txt`)とは別の層。** denylist は該当ファイルが存在するだけで
委託を止めるフェイルクローズ検査、こちらは司令塔が「どのチケットを渡すか」を決める振り分け判断。

```

**表の行の形は機械が読む**(§4 の検査が第 1 セルのバックティック囲みを抽出する)。
`| ` + バックティック囲みのパス + ` | 理由 |` の形を崩さないこと。

## 3. `docs/template-dev/codex-delegation-plan.md` §9 への根拠の移設

§9 の箇条書きの**末尾**(`- **モード C には自動ゲートが無い**` のブロックの後、`---` と `## 10.` の前)に、
`### 9.1 委託禁止領域の設計(なぜこのパスなのか)` を新設する。

**中身は、置換前の `CLAUDE.md` L27〜L52 の記述を「そのまま」移す**(言い換えない・要約しない)。
具体的には次の 3 つを原文のまま含める:

1. 各パス項目の箇条書き(`.claude/scripts/` 〜 `.harness/mode` / `.harness/codex-runs/` の全 13 項目)。
   `#15` / `#40` / `#56` / `#80` / `S1` / `S3` / `S6` への言及、`core.hooksPath` の連鎖の説明、
   `.husky/_/.gitignore = *` の説明を落とさない
2. 「`.claude/` 配下でも `skills/` / `commands/` / `agents/` / `docs/` は禁止領域に含めない。対象は次の 3 系統に限る(#56)」
   から始まる 3 系統の分類
3. 「**単一ソースは 2 系統に分かれる。**」から始まる段落(汎用項目 = 配列 / プロジェクト固有 = `AGENTS.md` §4、
   出口検査のマージと内容ハッシュ比較、「汎用項目を変えるときはスクリプト側の配列と `AGENTS.md` §4 を同時に直す」)

節の冒頭に導入を 2 行だけ足す:

```markdown
### 9.1 委託禁止領域の設計(なぜこのパスなのか)

判断に必要なパス一覧と 1 行の理由は `.claude/rules/lead/delegation-policy.md`(司令塔にのみ注入)、
委託先への指示は `AGENTS.md` §4。ここに置くのは**その根拠**で、どのコンテキストにも読み込まれない(#83)。
```

「**単一ソースは 2 系統に分かれる。**」段落の中の
「ここの記述はその説明であり、汎用項目を変えるときは…」は文脈が変わるので、
「ここの記述はその根拠であり、汎用項目を変えるときは…」に 1 語だけ直す。

## 4. 【設計判断】`check-forbidden-paths-doc.sh` は**残して双方向化する**

### 決定

廃止しない。照合先を `CLAUDE.md` から `.claude/rules/lead/delegation-policy.md` の
`<!-- forbidden-paths -->` マーカー内に変え、**双方向**・**完全一致**に改める。警告のままにする(CI は赤にしない)。

### 理由

- **3 箇所目は消えない、移るだけ。** C1 でパス一覧は `delegation-policy.md` に残る。
  検査を廃止すると、配列と一覧を結ぶ機械的な紐が 1 本も無くなる。#80 の再発を防げない
- **廃止の前提だった「警告に留める理由」が消えた。** 旧コメントは「`CLAUDE.md` はプロジェクト所有ファイルで
  説明文の書き方に自由度がある」から表現を縛れないとしていた。移設先の `delegation-policy.md` は
  **テンプレート所有**(`/sync-template` の同期対象)なので、マーカー + 表という機械可読な形を強制できる。
  これで完全一致比較が成立し、`grep -qF` の部分一致バグ(`.husky/` が `.husky/pre-commit` に一致する)が消える
- **警告のままにする**(エラーに昇格させない): マーカーを持たない旧版の `delegation-policy.md` を抱えた
  下流プロジェクトで CI が赤くなるのを避ける。乖離は `harness-integrity` ジョブの警告として十分見える

### 生じる問題と対処: `--print-forbidden` は**マージ済み**の一覧を返す

`delegation-policy.md` の表は**汎用項目だけ**の写しなので、プロジェクト固有パスを含む
`--print-forbidden` の出力とそのまま突き合わせると、`/kickoff` フェーズ4 を通したプロジェクトで
**必ず誤検知する**(固有パスが「節に書かれていない」と報告される)。

対処: `delegate-codex.sh` に**汎用項目だけを出す経路**を足す。既存の `--print-forbidden` の出力は変えない
(`check-guard-integrity.sh` の D3 はマージ済みの全量を必要とする)。

## 5. `delegate-codex.sh`: `--print-forbidden generic` の追加

新しいモードは足さない。既存の `--print-forbidden` に**任意の第 2 引数 `generic`** を受け付ける。
配列の内容は変えない(スコープ外)。変更は次の 4 箇所だけ。

1. **usage**(L161 付近)の該当行を 2 行にする:

   ```
     --print-forbidden [generic]        委託禁止領域の一覧を 1 行 1 パスで出力(read-only)。
                                        generic を付けると汎用項目(スクリプト内の配列)だけを出す
   ```

2. **引数検査**(L182 付近の `if [ "$MODE" != "--print-forbidden" ] && [ -z "$TARGET" ]` の直後)に、
   `--print-forbidden` の TARGET を検証する分岐を足す。空か `generic` 以外は usage + `exit "$EX_FAIL"`:

   ```bash
   # --print-forbidden の第 2 引数は generic のみ。黙って無視すると
   # 「指定したのに効いていない」に気づけない(下の余剰オプション検査と同じ方針)。
   if [ "$MODE" = "--print-forbidden" ] && [ -n "$TARGET" ] && [ "$TARGET" != "generic" ]; then
     echo "delegate-codex: --print-forbidden の引数は 'generic' のみです: $TARGET" >&2
     usage
     exit "$EX_FAIL"
   fi
   ```

3. **出力ブロック**(L343 付近)を次に置き換える:

   ```bash
   if [ "$MODE" = "--print-forbidden" ]; then
     printf '%s\n' "${FORBIDDEN_PATHS[@]}"
     # generic は汎用項目(この配列)だけを返す。delegation-policy.md の表が汎用項目のみの
     # 写しであるため、双方向の乖離検査はマージ前の一覧と突き合わせる必要がある(#83)。
     if [ "$TARGET" != "generic" ] && [ "${#PROJECT_FORBIDDEN_PATHS[@]}" -gt 0 ]; then
       printf '%s\n' "${PROJECT_FORBIDDEN_PATHS[@]}"
     fi
     exit 0
   fi
   ```

4. **短絡コメント**(L56 付近)は変更しない。`--print-forbidden` の判定は `"${1:-}"` を見ており、
   第 2 引数があっても成立する。

## 6. `check-forbidden-paths-doc.sh` の書き換え

ファイルを全面的に書き直す。仕様:

- 冒頭コメントを新しい役割に合わせて書き直す(照合先が `delegation-policy.md` になったこと、
  双方向・完全一致になったこと、警告に留める理由が「下流プロジェクトの旧版で赤くしない」に変わったこと、
  出力の装飾は呼び出し側の責任であること)
- 定数:
  - `DELEGATE=".claude/scripts/delegate-codex.sh"`
  - `DOC=".claude/rules/lead/delegation-policy.md"`
  - `BEGIN='<!-- forbidden-paths -->'` / `END='<!-- /forbidden-paths -->'`
- フェイルオープン(`exit 0`、検査対象外の構成):
  - `$DELEGATE` が無い / `$DOC` が無い
- 警告を出して `exit 1`:
  - `bash "$DELEGATE" --print-forbidden generic` の出力が空
  - `$DOC` にマーカーが揃っていない(片方だけ、または両方無い)。メッセージにマーカー名を含める
- 一覧の正規化: 両側とも末尾の `*` / `**` を落とす(`sed 's/\*\{1,2\}$//'`)+ `LC_ALL=C sort -u`
- 節側の抽出: マーカー行の間から `grep -o '`[^`]*`'` ではなく、**表の行の第 1 セルだけ**を取る。
  `awk -F'|' 'NF >= 3 { print $2 }'` でセルを取り出し、前後の空白とバックティックを剥がす。
  空・区切り行(`---`)・バックティックで囲まれていないものは捨てる
- 比較は**完全一致**(`grep -qF` を使わない)。`comm` は使わず、両方向とも
  「片方の各要素が、もう片方の集合に文字列として等しく存在するか」を bash のループで見る
- 出力(1 行 1 件、装飾なし):
  - 一覧にあって節に無い:
    `委託禁止領域 '<path>' が .claude/rules/lead/delegation-policy.md の一覧に書かれていない。FORBIDDEN_PATHS にパスを足したら、この表も同時に更新すること`
  - 節にあって一覧に無い:
    `.claude/rules/lead/delegation-policy.md の一覧にある '<path>' が delegate-codex.sh の FORBIDDEN_PATHS に無い。表に書いただけでは機械的な保護は掛からない(#80 はこの向きの乖離だった)`
- 終了コード: 0 = ずれ無し / 1 = ずれあり(既存と同じ)
- **実在検査(`[ -e "$_p" ]`)は行わない。** 両側とも汎用項目だけになり、
  「実在しない語がバックティックで囲まれている」ケース(AGENTS.md 由来のノイズ)が入らなくなったため。
  旧コメントが「まだ存在しないパスを足したケースは検知できない」と諦めていた穴もこれで閉じる

### 検証(実装者が実行して結果を tasklist に記録する)

```bash
# 1) 乖離なし → 出力なし・rc=0
bash .claude/scripts/check-forbidden-paths-doc.sh; echo "rc=$?"

# 2) 順方向(配列にあって表に無い): 表から 1 行消して警告 1 件・rc=1 を確認し、元に戻す
# 3) 逆方向(表にあって配列に無い): 表に `.claude/nonexistent-guard.json` の行を足して
#    警告 1 件・rc=1 を確認し、元に戻す
# 4) 部分一致バグの回帰: 表の `.husky/` を `.husky/pre-commit` に変えると
#    **両方向**で警告が出る(旧実装は素通しした)。確認後に戻す
# 5) generic の分離: 出力が配列 15 件と一致する
bash .claude/scripts/delegate-codex.sh --print-forbidden generic

# 6) 引数検査
bash .claude/scripts/delegate-codex.sh --print-forbidden bogus; echo "rc=$?"   # rc=1(EX_FAIL)
```

## 7. `.github/workflows/ci.yml` の更新

ステップ名(`Check forbidden-paths documentation drift`)と `run:` の中身は**変えない**。
直前のコメント(L131〜L134)だけを、照合先が `delegation-policy.md` になったことに合わせて書き直す:

```yaml
      # 委託禁止領域の単一ソース(delegate-codex.sh の FORBIDDEN_PATHS)と
      # .claude/rules/lead/delegation-policy.md の一覧のずれを**双方向**で検出する。
      # マーカーを持たない旧版の delegation-policy.md を抱えた下流プロジェクトで
      # ジョブが赤くならないよう、**警告に留める**(#64 / #83)。continue-on-error を
      # 使わないのは、ステップ自体が失敗扱いになって UI に赤が出るため。
```

`exit 0` の理由を書いた既存コメント(L136〜L141)はそのまま残す。

## 8. 参照の張り替え(散文のみ。挙動は変わらない)

| ファイル:行 | 現在 | 変更後 |
| --- | --- | --- |
| `README.md`:223 節 | 「判断ルールは `CLAUDE.md`「プロジェクト固有ルール」、Codex 側への指示は `AGENTS.md` §4」 | 「判断材料(パス一覧と理由)は `.claude/rules/lead/delegation-policy.md`、Codex 側への指示は `AGENTS.md` §4、根拠は `docs/template-dev/codex-delegation-plan.md` §9.1。一覧は `bash .claude/scripts/delegate-codex.sh --print-forbidden` で出る」 |
| `.claude/commands/kickoff.md`:94 | 「`CLAUDE.md`「プロジェクト固有ルール」節に「Codex への委託禁止領域(パス)」として列挙する(判断ルールの正)」 | **この行を削除する。**(プロジェクト固有パスの単一ソースは `AGENTS.md` §4 だけ。`CLAUDE.md` はポインタになったので二重管理を作らない) |
| `.claude/commands/kickoff.md`:138 | 「Codex 併用時は委託禁止領域が `CLAUDE.md` と `AGENTS.md` にパスで書かれている」 | 「Codex 併用時は委託禁止領域のプロジェクト固有パスが `AGENTS.md` §4 のマーカー内に書かれている」 |
| `.claude/commands/next-ticket.md`:61 | 「委託禁止領域(`CLAUDE.md`「プロジェクト固有ルール」)に触れる」 | 「委託禁止領域(`.claude/rules/lead/delegation-policy.md` の一覧 / 全量は `--print-forbidden`)に触れる」 |
| `.claude/commands/setup-tickets.md`:48 | 「委託禁止領域(`CLAUDE.md`「プロジェクト固有ルール」)に触れない」 | 「委託禁止領域(`.claude/rules/lead/delegation-policy.md` の一覧)に触れない」 |

## 9. 削減幅の計測(受け入れ条件)

作業の**前後**で次を実行し、結果を `tasklist.md` の該当項目に数値で記録する:

```bash
wc -c CLAUDE.md
awk 'index($0,"### Codex への委託禁止領域")==1{f=1} f&&/^## /{exit} f' CLAUDE.md | wc -c
```

着手時点の実測値: `CLAUDE.md` = 11,368 B / 当該節 = 7,845 B。

## 10. `docs/template-dev/CHANGELOG.md`

最上部の未リリース節に 1 行足す(既存の書式に合わせる。`[manual]` 印は不要 —— 同期すれば整合する)。
内容: 委託禁止領域の一覧を `delegation-policy.md` へ移し `CLAUDE.md` をポインタ化したこと、
乖離検査を双方向・完全一致に改めたこと、`--print-forbidden generic` を追加したこと(#83)。

## 11. やらないこと

- `FORBIDDEN_PATHS` の内容変更
- `AGENTS.md` §4 の削減
- `check-forbidden-paths-doc.sh` のエラー昇格(§4 の判断のとおり警告のまま)
- CLAUDE.md の他の節(技術スタック・ディレクトリ構造・開発プロセス)の削減(C2 の別チケット)
