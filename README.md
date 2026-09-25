# skills-and-plugins

Claude Code skills and plugins, kept under version control.

| Skill | For |
|---|---|
| [`vocacards-app-tester`](skills/vocacards-app-tester/SKILL.md) | QA for the VocaCards app: change review, bug hunts, on-device verification, release audits |

Install everything globally for Claude Code (`~/.claude/skills`) and Codex
(`~/.codex/skills`) by junctioning each skill to this clone:

```powershell
.\install.ps1
```

`git pull` then updates the installed skills in place. Re-run the script after adding a
skill; restart Claude Code / Codex to pick up a new one.
