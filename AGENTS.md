# Agent Skills Repository

This repository contains agent skills following the [agentskills.io](https://agentskills.io/) specification.

## Design Principles

1. **Instruction-driven, not script-driven**: SKILL.md defines strategy and platform-specific command references. The agent dynamically plans and executes — no wrapper scripts.
2. **Dynamic environment detection**: Every skill starts by detecting OS, shell, and available tools, then adapts its execution plan accordingly.
3. **Parallelism first**: Independent tasks MUST be executed in parallel using the agent's capabilities (sub-agents, agent teams, fleet model, parallel tool calls).
4. **Truly cross-platform**: No bash/shell assumptions. Provide command reference tables for Windows (PowerShell), macOS, and Linux — the agent picks the right ones.

## Project Structure

```
skills/
└── skill-name/
    ├── SKILL.md          # Required: skill definition with YAML frontmatter
    ├── references/       # Optional: additional documentation
    └── assets/           # Optional: static resources
```

## Creating Skills

### SKILL.md Format

```yaml
---
name: skill-name           # Required: lowercase, hyphens allowed, 1-64 chars
description: Description   # Required: what it does and when to use it, 1-1024 chars
license: MIT               # Optional
compatibility: ...         # Optional: environment requirements
metadata:                  # Optional
  author: name
  version: "1.0"
---

# Skill Instructions

Markdown content here...
```

### Naming Rules

- Lowercase letters, numbers, and hyphens only
- Must not start or end with hyphen
- No consecutive hyphens
- Directory name must match `name` field

## Language

All skill content must be written in English:
- SKILL.md (frontmatter and instructions)
- Reference documentation

## Cross-Platform Compatibility

All skills must work on Windows, macOS, and Linux:

- **Agent-driven, not script-driven**: Skills define WHAT to do, the agent dynamically selects HOW based on the detected OS and shell
- **Environment detection first**: Every skill must begin by detecting the runtime environment (OS, shell, available tools)
- **Platform command references**: Provide command hints per platform as reference tables, not hardcoded scripts
- **No shell assumptions**: Do not assume bash is available — the agent picks the right commands at runtime

## Target Agents

Skills should be compatible with:
- Claude Code
- GitHub Copilot CLI
- Other agentskills.io compliant agents

## Validation

```bash
skills-ref validate ./skills/your-skill-name
```
