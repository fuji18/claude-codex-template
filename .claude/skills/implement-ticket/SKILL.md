---
name: implement-ticket
description: .steering/ の design.md / tasklist.md に従って実装フェーズを実行する。/next-ticket・/add-feature・/fix-issue の実装ステップ専用で、計画(design.md)が未作成の状態では使わない。
context: fork
agent: implementer
model: sonnet
background: false
---

<!-- allowed-tools はあえて書かない。ここで絞ると implementer から Read / Edit / Write が
     失われて実装そのものが成立しなくなるうえ、権限の定義が settings.json・エージェント定義と
     3 重になり、片方の更新漏れがそのまま「実装できない」に直結する。
     権限の担保は .claude/settings.json の permissions.allow と
     .claude/agents/implementer.md の tools: に一本化する。 -->

# 実装フェーズの実行

`$ARGUMENTS` にステアリングディレクトリのパスが渡されている場合はそれを対象にする。渡されていない場合は、**最新のステアリングディレクトリ**を次のコマンドで特定する(日付プレフィックス降順 → 同日は mtime 降順。hook と同じ規則になる):

```bash
bash .claude/scripts/latest-steering.sh
```

## やること

1. 対象ディレクトリの `design.md` と `tasklist.md` を読む
2. `tasklist.md` の未完了タスクを先頭から 1 つずつ実装し、完了ごとに `- [x]` へ更新する
3. 全タスク完了後、**変更したファイルを対象に**品質チェック(lint・型チェック・フォーマット・関連するテスト)を実行し、機械的なエラーを修正する。フルスイートは司令塔側の検収(`test-runner`)と CI が回すため、ここで全体を通す必要はない
4. 報告フォーマットに従って結果を返す

## やらないこと

- **設計判断**(`design.md` に無い判断が要るなら停止して報告する)
- **コミット・push・PR 作成**(司令塔の担当)
- **`tasklist.md` に無い機能の追加**(スコープガード)

## 停止したときの扱い

「判断待ち」「失敗」で戻した場合、司令塔が `design.md` を更新してからこのスキルを再度呼ぶ。`tasklist.md` の進捗は保存されているため、続きから再開される。**進捗をこまめに `tasklist.md` へ書き戻すこと**が、この再開を成立させている。
