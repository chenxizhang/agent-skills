---
name: system-health-check
description: Comprehensive system health scanner that checks security risks, performance metrics, and optimization opportunities. Works on Windows, macOS, and Linux.
license: MIT
compatibility: Requires bash. On Windows, runs via Git Bash and may invoke PowerShell for some checks.
metadata:
  author: chenxizhang
  version: "1.0"
---

# System Health Check

A comprehensive scanner that analyzes your system for security risks, performance issues, and optimization opportunities.

## When to Use

- Setting up a new machine
- Periodic security audits
- Troubleshooting performance issues
- Before deploying to production

## Usage

```bash
bash scripts/check.sh
```

## Options

- `--security`: Run security checks only
- `--performance`: Run performance checks only
- `--optimize`: Run optimization suggestions only
- `--output FILE`: Save report to file (default: stdout)
- `--json`: Output in JSON format

## Examples

```bash
# Full system check
bash scripts/check.sh

# Security audit only
bash scripts/check.sh --security

# Save report to file
bash scripts/check.sh --output report.txt

# JSON output for automation
bash scripts/check.sh --json --output report.json
```

## Checks Performed

### Security

| Check | Windows | macOS | Linux |
|-------|---------|-------|-------|
| Firewall status | ✓ | ✓ | ✓ |
| Open ports | ✓ | ✓ | ✓ |
| SSH configuration | ✓ | ✓ | ✓ |
| Password policies | ✓ | ✓ | ✓ |
| User privileges | ✓ | ✓ | ✓ |
| Sensitive file permissions | ✓ | ✓ | ✓ |
| Antivirus status | ✓ | ✓ | - |
| System updates | ✓ | ✓ | ✓ |

### Performance

| Check | Windows | macOS | Linux |
|-------|---------|-------|-------|
| CPU usage | ✓ | ✓ | ✓ |
| Memory usage | ✓ | ✓ | ✓ |
| Disk usage | ✓ | ✓ | ✓ |
| Network connections | ✓ | ✓ | ✓ |
| Process analysis | ✓ | ✓ | ✓ |
| Startup items | ✓ | ✓ | ✓ |

### Optimization

| Suggestion | Windows | macOS | Linux |
|------------|---------|-------|-------|
| Disk cleanup opportunities | ✓ | ✓ | ✓ |
| Unused services | ✓ | ✓ | ✓ |
| Resource-heavy processes | ✓ | ✓ | ✓ |
| Temp file cleanup | ✓ | ✓ | ✓ |

## Sample Output

```
================================================================================
                         SYSTEM HEALTH CHECK REPORT
================================================================================
Generated: 2024-03-15 10:30:00
System: Windows 11 Pro (10.0.22631)
Hostname: DESKTOP-ABC123

================================================================================
                              SECURITY ANALYSIS
================================================================================

[✓] Firewall: Enabled
[✓] Windows Defender: Active and up to date
[!] Open Ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 3389 (RDP)
    └─ Warning: RDP port 3389 is open. Consider using VPN instead.
[✗] SSH Config: Password authentication enabled
    └─ Recommendation: Disable password auth, use key-based authentication
[✓] User Privileges: No unnecessary admin accounts

... (continued)
```
