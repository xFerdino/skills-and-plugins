# skills-and-plugins

Ferdino's skills and plugins for coding agents, packaged as an **Agent Plugins**
marketplace (`ferdino-plugins`). It's the same layout as `google/skills`: one repo, one
marketplace manifest per agent family, and one folder per plugin.

| Plugin | Skills | For |
|---|---|---|
| [`vocacards-qa`](plugins/vocacards-qa) | `vocacards-app-tester` | QA for the VocaCards app: change review, device and emulator campaigns (including the Anki bridge and AnkiDroid migration), release audits |

## Install

**Claude Code.** It reads the plugin in place from this clone, so edits are live:

```bash
claude plugin marketplace add "C:/Users/Luk/skills-and-plugins"
claude plugin install vocacards-qa@ferdino-plugins
```

From GitHub instead (this is a private repo, so `gh auth` is needed):
`claude plugin marketplace add xFerdino/skills-and-plugins`.

**Codex CLI and Antigravity** (`.agents/plugins/marketplace.json` and `.codex-plugin/`):

```bash
codex plugin marketplace add "C:/Users/Luk/skills-and-plugins"
codex plugin add vocacards-qa@ferdino-plugins
agy plugin install "C:/Users/Luk/skills-and-plugins/plugins/vocacards-qa"
```

Antigravity installs a **copy** (`~/.gemini/config/plugins/vocacards-qa/`), so after
changing a skill, re-run the `agy plugin install …` line. Claude Code and the Codex junction
read this clone directly.

**The Codex app (no CLI).** `.\install.ps1` junctions each plugin's skills into
`~/.codex/skills`.

## Layout

```
.claude-plugin/marketplace.json        Claude Code marketplace
.agents/plugins/marketplace.json       Codex / Antigravity marketplace
plugins/<plugin>/plugin.json           vendor-neutral manifest (agent-plugins.org schema)
plugins/<plugin>/.claude-plugin/       Claude Code manifest
plugins/<plugin>/.codex-plugin/        Codex manifest ("skills": "./skills/")
plugins/<plugin>/skills/<skill>/       SKILL.md + references/ + scripts/
```

To add a plugin, create its folder with the three manifests, then add one entry to each
marketplace file. Run `claude plugin validate .` before committing.
