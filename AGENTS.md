# Agent Skills Repository

This repository contains agent skills following the [agentskills.io](https://agentskills.io/) specification.

## Project Structure

```
skills/
└── skill-name/
    ├── SKILL.md          # Required: skill definition with YAML frontmatter
    ├── scripts/          # Optional: executable scripts
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
- Scripts and code comments
- Reference documentation

## Cross-Platform Compatibility

All skills must work on Windows, macOS, and Linux:

- Use `#!/usr/bin/env bash` or `#!/usr/bin/env python3` shebangs
- Avoid platform-specific commands
- Test on multiple platforms when possible
- Use forward slashes in paths within scripts

## Target Agents

Skills should be compatible with:
- Claude Code
- GitHub Copilot CLI
- Other agentskills.io compliant agents

## Validation

```bash
skills-ref validate ./skills/your-skill-name
```
