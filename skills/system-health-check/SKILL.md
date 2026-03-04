---
name: system-health-check
description: Comprehensive system health scanner that checks security risks, performance metrics, and optimization opportunities. Leverages agent parallelism for fast multi-category scanning. Works on Windows, macOS, and Linux.
license: MIT
metadata:
  author: chenxizhang
  version: "2.0"
---

# System Health Check

A comprehensive scanner that analyzes your system for security risks, performance issues, and optimization opportunities — **using parallel execution for maximum speed**.

## When to Use

- Setting up a new machine
- Periodic security audits
- Troubleshooting performance issues
- Before deploying to production

## Options

Users may request a subset:
- **Full check** (default): All three categories
- **Security only**: Security checks only
- **Performance only**: Performance checks only
- **Optimization only**: Optimization suggestions only

## Execution Strategy

**Do NOT use any scripts. Execute all commands directly through the agent's shell/tool capabilities.**

### Phase 1: Environment Detection

Detect the runtime environment to plan the correct commands:

- **Operating System**: Windows, macOS, or Linux (include version/distro)
- **Shell**: PowerShell, bash, zsh, etc.
- **Privilege level**: Admin/root or standard user
- **Hostname**: For the report header

Display the detected environment before proceeding.

### Phase 2: Parallel Execution ⚡

**CRITICAL: The three check categories are COMPLETELY INDEPENDENT. Run them ALL in PARALLEL!**

Launch three independent workstreams simultaneously:

- **GitHub Copilot CLI**: Use three sub-agents (task tool with agent_type "task" or "general-purpose") — one for Security, one for Performance, one for Optimization. All three run concurrently.
- **Claude Code**: Use Agent Teams — dispatch three sub-agents in parallel, one per category.
- **Other agents**: Use whatever parallel execution mechanism is available.

Each sub-agent independently executes the checks for its category using the platform-appropriate commands from the reference tables below.

### Phase 3: Compile Report

After all parallel workstreams complete, compile a unified report:

```
================================================================================
                         SYSTEM HEALTH CHECK REPORT
================================================================================
Generated: <timestamp>
System: <OS and version>
Hostname: <hostname>

[Security Analysis results...]
[Performance Analysis results...]
[Optimization Suggestions...]
```

Use these severity indicators:
- `[✓]` — Check passed / healthy
- `[!]` — Warning / needs attention
- `[✗]` — Critical issue / security risk

Focus on **actionable findings** — don't just dump raw command output. Interpret results and provide recommendations.

---

## 🔒 Security Analysis

### Checks to Perform

| Check | What to Look For |
|-------|------------------|
| Firewall status | Is the firewall enabled? Any rules allowing unrestricted inbound traffic? |
| Open ports | What ports are listening? Any unexpected services exposed? |
| SSH configuration | Password auth disabled? Key-based auth configured? |
| User privileges | Unnecessary admin/root accounts? |
| System updates | Pending security updates? |
| Antivirus status | (Windows/macOS) Is AV active and up to date? |
| Sensitive file permissions | Are SSH keys, config files properly secured? |
| AI Agent security | Scan AI agent configs for risky patterns (see below) |

### Platform Command Reference

The agent should select the appropriate commands based on the detected OS:

| Check | Windows (PowerShell) | macOS | Linux |
|-------|---------------------|-------|-------|
| Firewall | `Get-NetFirewallProfile` | `defaults read /Library/Preferences/com.apple.alf globalstate` | `ufw status` or `iptables -L` |
| Open ports | `Get-NetTCPConnection -State Listen` | `lsof -i -P -n \| grep LISTEN` | `ss -tlnp` |
| SSH config | Check `$env:ProgramData\ssh\sshd_config` | Check `/etc/ssh/sshd_config` | Check `/etc/ssh/sshd_config` |
| Updates | `Get-HotFix \| Sort InstalledOn -Desc \| Select -First 5` | `softwareupdate -l` | `apt list --upgradable` or `yum check-update` |
| AV status | `Get-MpComputerStatus` | N/A | N/A (check if ClamAV installed) |
| Users | `Get-LocalUser \| Where-Object Enabled` | `dscl . -list /Users \| grep -v '^_'` | `awk -F: '$3>=1000{print $1}' /etc/passwd` |
| File perms | `Get-Acl ~/.ssh/*` | `ls -la ~/.ssh/` | `ls -la ~/.ssh/` |

### AI Agent Security Scanning

Scan these config directories for risky patterns:

**User-level directories:**
- `~/.claude/`, `~/.copilot/`, `~/.continue/`, `~/.cursor/`, `~/.aider/`, `~/.agents/`, `~/.codeium/`, `~/.codeflow/`

**Project-level directories:**
- `.claude/`, `.continue/`, `.cursor/`, `.copilot/`, `.github/copilot/`

**Risk patterns to flag:**

| Category | Risk Level | Patterns to Search For |
|----------|-----------|----------------------|
| Network outbound | HIGH | `curl.*POST`, `wget --post`, `Invoke-WebRequest.*POST`, `fetch(` with POST |
| Credential access | HIGH | References to `.ssh/`, `.aws/`, `API_KEY`, `SECRET`, `TOKEN`, `PASSWORD` |
| Obfuscation | HIGH | `base64 -d`, `base64 --decode`, hex decoding, `rev \|`, `String.fromCharCode` |
| Dynamic execution | MEDIUM | `eval(`, `exec(`, `source <(`, `Function(` |
| Package installation | MEDIUM | `npx -y`, `pip install` from URLs, `npm install` unscoped packages |
| Permission bypass | MEDIUM | `bypassPermissions`, `skipVerify`, `allowAll`, `dangerouslyAllow` |
| Network requests | LOW | General `curl`/`wget`/`fetch` usage |
| MCP servers | LOW | MCP server definitions with `command` fields |

For each directory found, scan config files (JSON, YAML, TOML, MD) for these patterns using grep or the agent's search capabilities. Report findings grouped by risk level.

---

## 📊 Performance Analysis

### Checks to Perform

| Check | What to Look For |
|-------|------------------|
| CPU usage | Current utilization, top 5 processes by CPU |
| Memory usage | Total, used, available; top 5 processes by memory |
| Disk usage | Per-partition usage; flag partitions >85% full |
| Network connections | Active connection count, any unusual outbound connections |
| Process count | Total processes, any zombie/defunct processes |
| Startup items | Services/programs set to auto-start, total count |

### Platform Command Reference

| Check | Windows (PowerShell) | macOS | Linux |
|-------|---------------------|-------|-------|
| CPU | `Get-CimInstance Win32_Processor \| Select LoadPercentage` and `Get-Process \| Sort CPU -Desc \| Select -First 5` | `top -l 1 -n 0 \| grep "CPU usage"` and `ps aux --sort=-%cpu \| head -6` | `top -bn1 \| head -5` and `ps aux --sort=-%cpu \| head -6` |
| Memory | `Get-CimInstance Win32_OperatingSystem \| Select TotalVisibleMemorySize,FreePhysicalMemory` | `vm_stat` and `sysctl hw.memsize` | `free -h` |
| Disk | `Get-PSDrive -PSProvider FileSystem \| Select Name,Used,Free` | `df -h` | `df -h` |
| Network | `(Get-NetTCPConnection).Count` | `netstat -an \| grep ESTABLISHED \| wc -l` | `ss -s` |
| Processes | `(Get-Process).Count` | `ps aux \| wc -l` | `ps aux \| wc -l` |
| Startup | `Get-CimInstance Win32_StartupCommand \| Select Name,Command` | `launchctl list \| wc -l` | `systemctl list-unit-files --state=enabled --no-pager` |

---

## 🔧 Optimization Suggestions

### Checks to Perform

| Check | What to Look For |
|-------|------------------|
| Disk cleanup opportunities | Temp files, caches, logs that can be safely cleared; report total reclaimable space |
| Resource-heavy processes | Processes using >10% CPU or >500MB memory |
| Unused/unnecessary services | Running services that may not be needed |
| Temp file accumulation | Orphaned temp directories and their sizes |

### Platform Command Reference

| Check | Windows (PowerShell) | macOS | Linux |
|-------|---------------------|-------|-------|
| Temp files | `Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue \| Measure-Object -Property Length -Sum` | `du -sh /tmp/ ~/Library/Caches/ 2>/dev/null` | `du -sh /tmp/ /var/tmp/ 2>/dev/null` |
| Services | `Get-Service \| Where-Object {$_.Status -eq 'Running'} \| Measure-Object` | `launchctl list \| wc -l` | `systemctl list-units --type=service --state=running --no-pager \| wc -l` |
| Top CPU | `Get-Process \| Sort CPU -Desc \| Select -First 10 Name,CPU,WorkingSet64` | `ps aux --sort=-%cpu \| head -11` | `ps aux --sort=-%cpu \| head -11` |
| Top Memory | `Get-Process \| Sort WorkingSet64 -Desc \| Select -First 10 Name,@{N='MemMB';E={[math]::Round($_.WorkingSet64/1MB)}}` | `ps aux --sort=-%mem \| head -11` | `ps aux --sort=-%mem \| head -11` |

---

## Parallelism Guidelines

| Scope | Strategy |
|-------|----------|
| Full check (3 categories) | Run Security, Performance, Optimization as 3 parallel sub-agents |
| Single category | Run individual checks within the category in parallel where possible |
| AI Agent scanning | Scan multiple config directories in parallel |

## Notes

- Some checks may require elevated privileges — if a command fails due to permissions, note it in the report and continue
- Adapt commands based on what's actually installed (e.g., if `ufw` is not available, try `iptables`; if neither, skip and note)
- The command reference tables are hints, not rigid prescriptions — the agent should use its knowledge to pick the best available command
- Individual checks within a category can also be parallelized for even more speed
