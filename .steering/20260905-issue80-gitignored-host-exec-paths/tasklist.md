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
