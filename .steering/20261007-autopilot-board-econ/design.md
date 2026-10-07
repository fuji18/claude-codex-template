<!-- status: ready -->
# 設計: 全体管理 Issue・ローカルの手間削減・econ 対応

## 1. 全体管理 Issue(`autopilot-board.sh`)

- `autopilot` ラベルの open Issue(最小番号)。`ticket` は付けない(判定に数えないため)
- `sync`: 判定 JSON から本文を再生成。「最終更新」行を除いて変化がなければ書かない。一時停止チェックは旧本文から引き継ぐ
- `paused`: 本文の `- [x] **一時停止**` を見る。`notify`: コメント + `AUTOPILOT_NOTIFY_CMD`
- `render`: GitHub に触らず本文を出す(確認・テスト用)
- 表示層の失敗では本体を止めない(ループ側で握る)

## 2. ループ(`autopilot-loop.sh`)

- `--background`(nohup・pid・ログ)/ `--log` / `--stop`
- 優先順: 自分の中断作業(この作業ツリーに `issue[N]-` のブランチがある stalled)> fix > start > wait
- 未コミット変更は「再開するチケット自身のブランチ上」なら続きとして扱い、それ以外で止まる
- 別セッションの stalled は wait を続け、全体管理 Issue に表示(blocked で残るときだけ止まる)
- 停止は全体管理 Issue にコメント + 通知コマンド + ベル
- 進捗の同一判定キーは resume では HEAD と作業ツリーのハッシュを含める(econ の段階進行を「進まない」と誤判定しない)。Codex の exit 4 で待っただけの周は数えない

## 3. econ

- 判定: モードが econ なら `econ.maxInFlight`(既定 4)
- 1 段ずつ実態から判定: steering 無し / design が ready でない → `/next-ticket N --plan-only`、tasklist に未完了 → `delegate-codex.sh impl`(1|5 → plan-only、3 → 停止、4 → 待機、他 → 停止)、全完了 → ライフサイクル差分(base との分岐点比較)があれば停止、無ければ `/ship-ticket N`
- `--plan-only` で委託に向かないと判断したら `autopilot:manual` を付け、判定は候補から外す(残りが manual だけなら action `manual`)
