# .agents/

**このディレクトリは生成物です。直接編集しないでください**(次の生成で消えます)。

`.claude/skills/` を単一ソースとして、Codex CLI が読む `.agents/skills/` を機械的に複製したものです。
Claude Code は `.claude/skills/` だけを、Codex CLI は `.agents/skills/` だけを読むため、同じスキルを
両方から使うには一方を正にしてもう一方を追従させる必要があります。

- 生成: `bash .claude/scripts/sync-agents-skills.sh`
- 検査: `bash .claude/scripts/sync-agents-skills.sh --check`(CI の `harness-integrity` が実行する)

スキルを足す・直すときは `.claude/skills/` 側を編集し、生成し直してコミットしてください。
