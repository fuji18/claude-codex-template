# タスクリスト: 実装ルールの欠陥修正とドキュメント整合

<!-- main-edit-ok -->
<!-- ↑ この作業はテンプレート自体の改修であり、司令塔が直接編集する。
     check-implementation-phase.sh のブロックを解除するマーカー。
     プロダクト開発のチケットでは付けないこと。 -->

## 1. 重大

- [x] `implement-ticket` の `allowed-tools` 行を削除する
- [x] `.claude/scripts/latest-steering.sh` を新設する(実行権限を git に記録)
- [x] `check-implementation-phase.sh` / `session-start.sh` を新スクリプト呼び出しに置き換える
- [x] `implement-ticket/SKILL.md` / `implementer.md` の検出コマンド例を差し替える
- [x] `check-branch-policy.sh` の検出をコマンド位置に限定する
- [x] `block-dangerous-cmds.sh` の検出をコマンド位置に限定し、SQL を DB クライアント経由に絞る
- [x] `/kickoff` にテンプレート由来 `.steering/` の掃除手順を追加する

## 2. 中

- [x] `/fix-issue` の検証を code-reviewer + test-runner の並列起動にし、コミットを `Skill('commit')` に統一する
- [x] `.claude/settings.json` の allow に git fetch / git merge / gh pr create を追加する
- [x] `implement-ticket` の品質チェック手順を「変更ファイル中心の自己修復」に限定し、`review-policy.md` に役割分担を明記する

## 3. ドキュメント整合

- [x] `docs/template-dev/README.md` の索引を実ファイルに合わせる
- [x] `harness-setup/SKILL.md` のモデル ID を `claude-opus-5` に更新する
- [x] `review-policy.md` の CI トリガー記述を実態に合わせる
- [x] `CLAUDE.md` のディレクトリ構造に `.claude/docs/` を追加する
- [x] `README.md` の hook 強制範囲の表現を修正し、`.steering/` 掃除に言及する
- [x] 前作業の `requirements.md` の受け入れ条件を実態に更新する
- [x] `docs/template-dev/CHANGELOG.md` に今回の変更を追記する

## 4. 検証

- [x] hook スクリプトの構文チェック・実行権限・誤爆解消の実地確認(16 ケースの真陽性/偽陽性テストを実施)
- [x] `code-reviewer` によるレビューと指摘対応(Major 1 / Minor 5)
- [x] 同日 2 ディレクトリでの最新判定の実地確認(同日新規・古い作業への編集・翌日作業の 4 ケース)
- [x] `/check`(lint・型・フォーマット・テスト)

## 申し送り

- **設計からの変更**: `latest-steering.sh` の第二キーを当初案の「ディレクトリの mtime」から **`tasklist.md` の mtime** に変更した。実地検証で、古いステアリングの `requirements.md` を 1 つ編集しただけでそのディレクトリが「最新」に化ける挙動を再現したため。進捗を表すのは `tasklist.md` の更新であり、そこだけを見る
- **設計外の修正を 1 件追加**: `block-dangerous-cmds.sh` の force push 検出が `git push -f origin main`(フラグが第一引数に来る形)を取りこぼしていた。コマンド位置の限定を入れる過程でテストして判明。`permissions.deny` の前方一致が同じ形をカバーしていたため実害は出ていなかったが、パイプ内では素通りしていた
- **未検証のまま残るもの**: fork(`implement-ticket`)が実際に Sonnet で走り、停止条件が機能するかは依然として実地検証されていない(前作業からの持ち越し)。`allowed-tools` を外したことで「編集ツールを失う」経路は消えたが、**最初のプロダクトチケットで fork の戻り値と往復回数を観察すること**
- **レビューでの追加修正(code-reviewer / Major 1 件)**: コマンド位置に限定する接頭辞にバッククォートが入っておらず、`` `rm -rf /` `` のようなコマンド置換形式が素通りしていた。あわせて「終端」クラス(`E`)を新設し、`` `git push -f` `` のように閉じバッククォートが直後に来る形の取りこぼしも塞いだ。テストケースを 10 → 16 に拡充
- レビュー指摘のうち **`bash -c "..."` / eval 経由の迂回は非対応のまま**とした。文字列パターンによるベストエフォートの防衛線であってサンドボックスではない、というスクリプト冒頭の位置づけどおり。コメントに限定事項として明記した
- レビュー指摘の `Skill('commit')` 表記は**修正不要**と判断した。`.claude/commands/*.md` は Skill ツールから呼べる形で提供されており、既存の `/add-feature` も同じ表記を使っている
- `<!-- main-edit-ok -->` 付きのこのディレクトリも、プロダクト開発を始める際は `/kickoff` フェーズ5 で削除される対象
