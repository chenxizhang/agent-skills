# Agent Skills

Cross-platform agent skills following the [skills.sh](https://skills.sh/) open ecosystem.

## Install

```bash
# Install individual skills
npx skills add chenxizhang/agent-skills/cleanup-nul
npx skills add chenxizhang/agent-skills/git-sync-all
npx skills add chenxizhang/agent-skills/system-health-check
```

## Available Skills

| Skill | Description |
|-------|-------------|
| [cleanup-nul](skills/cleanup-nul) | Find and delete `nul` files accidentally created by tools on Windows |
| [git-sync-all](skills/git-sync-all) | Recursively find all git repos and pull latest changes **in parallel** |
| [system-health-check](skills/system-health-check) | Parallel security, performance, and optimization scanning |

All skills are instruction-driven (no scripts), dynamically adapt to your OS/shell, and leverage agent parallelism.

## Learn More

- [skills.sh](https://skills.sh/) — The open agent skills ecosystem
- [AGENTS.md](AGENTS.md) — Contributor guidelines
