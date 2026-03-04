# Agent Skills

Cross-platform agent skills following the [skills.sh](https://skills.sh/) open ecosystem.

## Install

```bash
# Install all skills (interactive)
npx skills add chenxizhang/agent-skills --all

# Install all skills (skip prompts with -y)
npx skills add chenxizhang/agent-skills --all -y

# Install a specific skill
npx skills add chenxizhang/agent-skills --skill cleanup-nul -y

# Install to specific agents
npx skills add chenxizhang/agent-skills --agent claude-code copilot -y

# Install globally (user-level)
npx skills add chenxizhang/agent-skills -g --all -y

# List available skills without installing
npx skills add chenxizhang/agent-skills --list
```

## Available Skills

| Skill | Description |
|-------|-------------|
| [cleanup-nul](skills/cleanup-nul) | Find and delete `nul` files accidentally created by tools on Windows |
| [git-sync-all](skills/git-sync-all) | Recursively find all git repos and pull latest changes **in parallel** |
| [system-health-check](skills/system-health-check) | Parallel security, performance, and optimization scanning |
| [update-all](skills/update-all) | Update winget, npm globals, agent skills, and apt **all in parallel** |

All skills are instruction-driven (no scripts), dynamically adapt to your OS/shell, and leverage agent parallelism.

## Learn More

- [skills.sh](https://skills.sh/) — The open agent skills ecosystem
- [AGENTS.md](AGENTS.md) — Contributor guidelines
