# Publish Test

## Published Evidence

TOD can use the local fallback executor for bounded tasks in docs/local-fallback-publish-67e3f72889b94976ada712abbffe88db.md when Codex only returns wrapper output or no meaningful execution evidence.

- Eligibility stays inside bounded docs, code, config, or test changes under allowed paths.
- Published evidence includes changed files, diff summary, command output, validation results, blockers, and rollback hints.
- The executor fails closed when it cannot infer a safe target or bounded patch.
