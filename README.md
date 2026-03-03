# Agent Skills Collection

A collection of agent skills following the [agentskills.io](https://agentskills.io/) specification.

## Compatibility

These skills are designed to work with:
- Claude Code
- Copilot CLI
- Other agents supporting the agentskills.io format

All skills are cross-platform compatible (Windows, macOS, Linux).

## Structure

```
skills/
├── skill-name/
│   ├── SKILL.md          # Required: skill definition
│   ├── scripts/          # Optional: executable scripts
│   ├── references/       # Optional: additional documentation
│   └── assets/           # Optional: static resources
```

## Installation

### Claude Code

```bash
claude skill add /path/to/skills/skill-name
```

### Copilot CLI

```bash
# Follow copilot-cli skill installation instructions
```

## Creating a New Skill

1. Create a directory under `skills/` with your skill name (lowercase, hyphens allowed)
2. Add a `SKILL.md` file with required frontmatter:

```yaml
---
name: your-skill-name
description: What this skill does and when to use it.
---

# Your Skill Instructions

Step-by-step instructions for the agent...
```

## Validation

```bash
skills-ref validate ./skills/your-skill-name
```

## License

See individual skill directories for their respective licenses.
