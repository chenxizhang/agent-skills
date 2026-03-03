#!/usr/bin/env bash
#
# System Health Check - Security, Performance, and Optimization Scanner
# Cross-platform: Windows (Git Bash + PowerShell), macOS, Linux
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

RUN_SECURITY=true
RUN_PERFORMANCE=true
RUN_OPTIMIZE=true
OUTPUT_FILE=""
JSON_OUTPUT=false

# Colors (disabled if not terminal or if outputting to file)
if [[ -t 1 ]] && [[ -z "${OUTPUT_FILE:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --security)
            RUN_SECURITY=true
            RUN_PERFORMANCE=false
            RUN_OPTIMIZE=false
            shift
            ;;
        --performance)
            RUN_SECURITY=false
            RUN_PERFORMANCE=true
            RUN_OPTIMIZE=false
            shift
            ;;
        --optimize)
            RUN_SECURITY=false
            RUN_PERFORMANCE=false
            RUN_OPTIMIZE=true
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --security     Run security checks only"
            echo "  --performance  Run performance checks only"
            echo "  --optimize     Run optimization suggestions only"
            echo "  --output FILE  Save report to file"
            echo "  --json         Output in JSON format"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# OS Detection
# ============================================================================

detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux" ;;
        Darwin*)    echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

OS=$(detect_os)

# ============================================================================
# Output Helpers
# ============================================================================

declare -a JSON_RESULTS=()

print_header() {
    local title="$1"
    echo ""
    echo "================================================================================"
    echo -e "${BOLD}${title}${NC}"
    echo "================================================================================"
}

print_ok() {
    echo -e "[${GREEN}✓${NC}] $1"
    if $JSON_OUTPUT; then
        JSON_RESULTS+=("{\"status\":\"ok\",\"check\":\"$1\"}")
    fi
}

print_warn() {
    echo -e "[${YELLOW}!${NC}] $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "    └─ Warning: $2"
    fi
    if $JSON_OUTPUT; then
        JSON_RESULTS+=("{\"status\":\"warning\",\"check\":\"$1\",\"message\":\"${2:-}\"}")
    fi
}

print_fail() {
    echo -e "[${RED}✗${NC}] $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "    └─ Recommendation: $2"
    fi
    if $JSON_OUTPUT; then
        JSON_RESULTS+=("{\"status\":\"fail\",\"check\":\"$1\",\"message\":\"${2:-}\"}")
    fi
}

print_info() {
    echo -e "[${BLUE}i${NC}] $1"
}

# ============================================================================
# Windows PowerShell Helper
# ============================================================================

run_powershell() {
    if command -v pwsh &> /dev/null; then
        pwsh -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'
    elif command -v powershell.exe &> /dev/null; then
        powershell.exe -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'
    else
        echo "N/A"
    fi
}

# ============================================================================
# Windows Data Collection (single PowerShell call for all checks)
# ============================================================================

declare -A WIN_DATA=()
WIN_DATA_DISKS=""
WIN_DATA_PROCS=""

collect_windows_data() {
    if [[ "$OS" != "windows" ]]; then
        return 0
    fi

    local ps_file
    ps_file=$(mktemp --suffix=.ps1)

    # Always collect system info
    cat > "$ps_file" << 'ENDPS'
$ErrorActionPreference = "SilentlyContinue"
Write-Output "OS_VERSION=$([System.Environment]::OSVersion.VersionString)"
ENDPS

    if $RUN_SECURITY; then
        cat >> "$ps_file" << 'ENDPS'
$fwCount = (Get-NetFirewallProfile -Profile Domain,Public,Private | Where-Object {$_.Enabled -eq $true}).Count
Write-Output "FW_COUNT=$fwCount"
$ports = (Get-NetTCPConnection -State Listen | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique) -join " "
Write-Output "LISTEN_PORTS=$ports"
$mp = Get-MpComputerStatus
Write-Output "DEFENDER_RTP=$($mp.RealTimeProtectionEnabled)"
Write-Output "DEFENDER_SCAN=$($mp.FullScanEndTime)"
try { $u = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0").Updates.Count; Write-Output "PENDING_UPDATES=$u" } catch { Write-Output "PENDING_UPDATES=N/A" }
ENDPS
    fi

    if $RUN_PERFORMANCE; then
        cat >> "$ps_file" << 'ENDPS'
try { $cpu = [math]::Round((Get-Counter "\Processor(_Total)\% Processor Time").CounterSamples.CookedValue); Write-Output "CPU_USAGE=$cpu" } catch { Write-Output "CPU_USAGE=N/A" }
$osInfo = Get-CimInstance Win32_OperatingSystem
$memTotal = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 1)
$memFree = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 1)
$memUsed = [math]::Round($memTotal - $memFree, 1)
$memPct = [math]::Round(($memUsed / $memTotal) * 100, 0)
Write-Output "MEM_USED=$memUsed"
Write-Output "MEM_TOTAL=$memTotal"
Write-Output "MEM_PCT=$memPct"
Get-PSDrive -PSProvider FileSystem | ForEach-Object { $t = [math]::Round($_.Used/1GB + $_.Free/1GB, 0); $u2 = [math]::Round($_.Used/1GB, 0); $p = if ($t -gt 0) { [math]::Round(($u2 / $t) * 100, 0) } else { 0 }; if ($t -gt 0) { Write-Output "DISK=$($_.Name):$u2`:$t`:$p" } }
Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object { $c = [math]::Round($_.CPU, 1); $m = [math]::Round($_.WorkingSet64/1MB, 0); Write-Output "PROC=$($_.ProcessName):${c}:${m}" }
Write-Output "NET_ESTABLISHED=$((Get-NetTCPConnection -State Established).Count)"
Write-Output "NET_LISTENING=$((Get-NetTCPConnection -State Listen).Count)"
ENDPS
    fi

    if $RUN_OPTIMIZE; then
        cat >> "$ps_file" << 'ENDPS'
$tempSize = [math]::Round((Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 0)
Write-Output "TEMP_SIZE=$tempSize"
Write-Output "STARTUP_COUNT=$((Get-CimInstance Win32_StartupCommand).Count)"
ENDPS
    fi

    local raw
    if command -v pwsh &> /dev/null; then
        raw=$(pwsh -NoProfile -ExecutionPolicy Bypass -File "$ps_file" 2>/dev/null | tr -d '\r')
    elif command -v powershell.exe &> /dev/null; then
        raw=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps_file" 2>/dev/null | tr -d '\r')
    fi
    rm -f "$ps_file"

    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        case "$key" in
            DISK) WIN_DATA_DISKS+="$value"$'\n' ;;
            PROC) WIN_DATA_PROCS+="$value"$'\n' ;;
            *) WIN_DATA["$key"]="$value" ;;
        esac
    done <<< "$raw"
    return 0
}

# ============================================================================
# System Information
# ============================================================================

print_system_info() {
    print_header "SYSTEM INFORMATION"

    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Hostname: $(hostname)"

    case $OS in
        windows)
            echo "System: Windows - ${WIN_DATA[OS_VERSION]}"
            ;;
        macos)
            echo "System: macOS $(sw_vers -productVersion)"
            ;;
        linux)
            if [[ -f /etc/os-release ]]; then
                # shellcheck disable=SC1091
                source /etc/os-release
                echo "System: $NAME $VERSION"
            else
                echo "System: Linux $(uname -r)"
            fi
            ;;
    esac
}

# ============================================================================
# Security Checks
# ============================================================================

check_firewall() {
    print_info "Checking firewall status..."

    case $OS in
        windows)
            local fw_status="${WIN_DATA[FW_COUNT]}"
            if [[ "$fw_status" -ge 1 ]]; then
                print_ok "Firewall: Enabled ($fw_status profile(s) active)"
            else
                print_fail "Firewall: Disabled" "Enable Windows Firewall for all profiles"
            fi
            ;;
        macos)
            local fw_status
            fw_status=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -c "enabled" || echo "0")
            if [[ "$fw_status" -ge 1 ]]; then
                print_ok "Firewall: Enabled"
            else
                print_warn "Firewall: Disabled" "Consider enabling the application firewall"
            fi
            ;;
        linux)
            if command -v ufw &> /dev/null; then
                if ufw status 2>/dev/null | grep -q "Status: active"; then
                    print_ok "Firewall (ufw): Enabled"
                else
                    print_warn "Firewall (ufw): Inactive" "Run 'sudo ufw enable' to activate"
                fi
            elif command -v firewall-cmd &> /dev/null; then
                if firewall-cmd --state 2>/dev/null | grep -q "running"; then
                    print_ok "Firewall (firewalld): Running"
                else
                    print_warn "Firewall (firewalld): Not running"
                fi
            elif command -v iptables &> /dev/null; then
                local rules
                rules=$(iptables -L 2>/dev/null | wc -l || echo "0")
                if [[ "$rules" -gt 8 ]]; then
                    print_ok "Firewall (iptables): Rules configured"
                else
                    print_warn "Firewall (iptables): Minimal rules" "Consider adding firewall rules"
                fi
            else
                print_info "Firewall: No common firewall tool detected"
            fi
            ;;
    esac
}

check_open_ports() {
    print_info "Checking open ports..."

    local ports=""
    local risky_ports=()

    case $OS in
        windows)
            ports="${WIN_DATA[LISTEN_PORTS]}"
            ;;
        macos|linux)
            if command -v ss &> /dev/null; then
                ports=$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ')
            elif command -v netstat &> /dev/null; then
                ports=$(netstat -tlnp 2>/dev/null | awk 'NR>2 {print $4}' | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ')
            fi
            ;;
    esac

    # Check for risky ports
    for port in $ports; do
        case $port in
            21) risky_ports+=("21 (FTP)") ;;
            23) risky_ports+=("23 (Telnet)") ;;
            3389) risky_ports+=("3389 (RDP)") ;;
            5900) risky_ports+=("5900 (VNC)") ;;
        esac
    done

    if [[ ${#risky_ports[@]} -gt 0 ]]; then
        print_warn "Open Ports: $ports" "Potentially risky ports open: ${risky_ports[*]}"
    elif [[ -n "$ports" ]]; then
        print_ok "Open Ports: $ports"
    else
        print_ok "Open Ports: None detected (or requires elevated privileges)"
    fi
}

check_ssh_config() {
    print_info "Checking SSH configuration..."

    local ssh_config="/etc/ssh/sshd_config"

    case $OS in
        windows)
            ssh_config="${PROGRAMDATA:-/c/ProgramData}/ssh/sshd_config"
            if [[ ! -f "$ssh_config" ]]; then
                print_info "SSH Server: Not installed or not configured"
                return
            fi
            ;;
        macos|linux)
            if [[ ! -f "$ssh_config" ]]; then
                print_info "SSH Server: Config not found at $ssh_config"
                return
            fi
            ;;
    esac

    # Check password authentication
    if grep -qE "^PasswordAuthentication\s+yes" "$ssh_config" 2>/dev/null; then
        print_warn "SSH: Password authentication enabled" "Consider using key-based authentication only"
    elif grep -qE "^PasswordAuthentication\s+no" "$ssh_config" 2>/dev/null; then
        print_ok "SSH: Password authentication disabled"
    else
        print_info "SSH: PasswordAuthentication not explicitly set"
    fi

    # Check root login
    if grep -qE "^PermitRootLogin\s+(yes|without-password)" "$ssh_config" 2>/dev/null; then
        print_warn "SSH: Root login permitted" "Consider setting PermitRootLogin to 'no'"
    elif grep -qE "^PermitRootLogin\s+no" "$ssh_config" 2>/dev/null; then
        print_ok "SSH: Root login disabled"
    fi
}

check_antivirus() {
    print_info "Checking antivirus status..."

    case $OS in
        windows)
            local defender_status="${WIN_DATA[DEFENDER_RTP]}"
            if [[ "$defender_status" == "True" ]]; then
                print_ok "Windows Defender: Real-time protection enabled"
            else
                print_fail "Windows Defender: Real-time protection disabled" "Enable real-time protection in Windows Security"
            fi

            print_info "Last full scan: ${WIN_DATA[DEFENDER_SCAN]}"
            ;;
        macos)
            if [[ -d "/Library/Apple/System/Library/CoreServices/XProtect.app" ]]; then
                print_ok "XProtect: Installed (built-in malware protection)"
            fi
            ;;
        linux)
            if command -v clamav &> /dev/null || command -v clamscan &> /dev/null; then
                print_ok "ClamAV: Installed"
            else
                print_info "Antivirus: No common AV detected (ClamAV not installed)"
            fi
            ;;
    esac
}

check_updates() {
    print_info "Checking system updates..."

    case $OS in
        windows)
            local pending="${WIN_DATA[PENDING_UPDATES]}"
            if [[ "$pending" == "0" ]]; then
                print_ok "Windows Update: System is up to date"
            elif [[ "$pending" == "N/A" ]]; then
                print_info "Windows Update: Unable to check (requires elevation)"
            else
                print_warn "Windows Update: $pending update(s) pending" "Install pending updates"
            fi
            ;;
        macos)
            local updates
            updates=$(softwareupdate -l 2>&1 | grep -c "Software Update" || echo "0")
            if [[ "$updates" == "0" ]]; then
                print_ok "macOS Updates: System appears up to date"
            else
                print_warn "macOS Updates: Updates may be available" "Run 'softwareupdate -l' to check"
            fi
            ;;
        linux)
            if command -v apt &> /dev/null; then
                local upgradable
                upgradable=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
                if [[ "$upgradable" == "0" ]]; then
                    print_ok "APT: System is up to date"
                else
                    print_warn "APT: $upgradable package(s) can be upgraded" "Run 'sudo apt upgrade'"
                fi
            elif command -v dnf &> /dev/null; then
                print_info "DNF: Run 'dnf check-update' to check for updates"
            elif command -v yum &> /dev/null; then
                print_info "YUM: Run 'yum check-update' to check for updates"
            fi
            ;;
    esac
}

check_sensitive_files() {
    print_info "Checking sensitive file permissions..."

    case $OS in
        macos|linux)
            # Check SSH keys
            if [[ -d "$HOME/.ssh" ]]; then
                local ssh_perms
                ssh_perms=$(stat -c "%a" "$HOME/.ssh" 2>/dev/null || stat -f "%Lp" "$HOME/.ssh" 2>/dev/null)
                if [[ "$ssh_perms" == "700" ]]; then
                    print_ok "SSH directory permissions: $ssh_perms (correct)"
                else
                    print_warn "SSH directory permissions: $ssh_perms" "Should be 700"
                fi
            fi

            # Check for world-readable sensitive files
            local exposed_files=()
            for file in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" "$HOME/.netrc" "$HOME/.aws/credentials"; do
                if [[ -f "$file" ]]; then
                    local perms
                    perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null)
                    if [[ "${perms: -1}" != "0" ]]; then
                        exposed_files+=("$file ($perms)")
                    fi
                fi
            done

            if [[ ${#exposed_files[@]} -gt 0 ]]; then
                print_warn "World-readable sensitive files found" "${exposed_files[*]}"
            else
                print_ok "Sensitive file permissions: No issues found"
            fi
            ;;
        windows)
            print_info "File permission checks limited on Windows via Git Bash"
            ;;
    esac
}

# ============================================================================
# AI Agent Security Analysis
# ============================================================================

# Counters for summary
AGENT_SCAN_AGENTS=0
AGENT_SCAN_SCRIPTS=0
AGENT_SCAN_CONFIGS=0
AGENT_SCAN_HIGH=0
AGENT_SCAN_MEDIUM=0
AGENT_SCAN_LOW=0

# Global arrays for discovered agents (using | as delimiter for name|path)
declare -a GLOBAL_AGENTS=()
declare -a PROJECT_AGENTS=()

# Discover installed AI agents by checking for their directories
discover_ai_agents() {
    GLOBAL_AGENTS=()

    # Global configurations
    [[ -d "$HOME/.claude" ]] && GLOBAL_AGENTS+=("Claude_Code|$HOME/.claude")
    [[ -d "$HOME/.copilot" ]] && GLOBAL_AGENTS+=("GitHub_Copilot|$HOME/.copilot")
    [[ -d "$HOME/.continue" ]] && GLOBAL_AGENTS+=("Continue.dev|$HOME/.continue")
    [[ -d "$HOME/.cursor" ]] && GLOBAL_AGENTS+=("Cursor|$HOME/.cursor")
    [[ -d "$HOME/.aider" ]] && GLOBAL_AGENTS+=("Aider|$HOME/.aider")
    [[ -d "$HOME/.agents" ]] && GLOBAL_AGENTS+=("Skills_CLI|$HOME/.agents")
    [[ -d "$HOME/.codeium" ]] && GLOBAL_AGENTS+=("Codeium|$HOME/.codeium")
    [[ -d "$HOME/.codeflow" ]] && GLOBAL_AGENTS+=("Windsurf|$HOME/.codeflow")
    return 0
}

# Discover project-level agent configurations
discover_project_agents() {
    PROJECT_AGENTS=()
    local cwd="${PWD}"

    [[ -d "$cwd/.claude" ]] && PROJECT_AGENTS+=("Claude_Code|$cwd/.claude")
    [[ -d "$cwd/.continue" ]] && PROJECT_AGENTS+=("Continue.dev|$cwd/.continue")
    [[ -d "$cwd/.cursor" ]] && PROJECT_AGENTS+=("Cursor|$cwd/.cursor")
    [[ -d "$cwd/.copilot" ]] && PROJECT_AGENTS+=("Copilot|$cwd/.copilot")
    [[ -d "$cwd/.github/copilot" ]] && PROJECT_AGENTS+=("GitHub_Copilot|$cwd/.github/copilot")
    return 0
}

# Analyze a script file for security risks
# Returns: risk findings as newline-separated strings
analyze_script_file() {
    local file="$1"
    local findings=()

    # Read file content (limit to first 5000 chars for performance)
    local content
    content=$(head -c 5000 "$file" 2>/dev/null) || return

    # HIGH: Network outbound with data
    if echo "$content" | grep -qiE 'curl.*(-X\s*POST|--data|--upload|-d\s)'; then
        findings+=("HIGH:Network POST request detected (curl with data)")
    fi
    if echo "$content" | grep -qiE 'wget.*--post'; then
        findings+=("HIGH:Network POST request detected (wget)")
    fi
    if echo "$content" | grep -qiE 'Invoke-WebRequest.*-Method\s*(Post|Put)'; then
        findings+=("HIGH:Network POST request detected (PowerShell)")
    fi
    if echo "$content" | grep -qiE 'fetch\s*\([^)]*method[^)]*POST'; then
        findings+=("HIGH:Network POST request detected (fetch)")
    fi

    # HIGH: Credential/secret access
    if echo "$content" | grep -qiE '(cat|type|less|more|head|tail).*\.(ssh|aws|gnupg|netrc)'; then
        findings+=("HIGH:Reading credential files detected")
    fi
    if echo "$content" | grep -qiE '\$\{?(AWS_SECRET|API_KEY|GITHUB_TOKEN|NPM_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY)'; then
        findings+=("HIGH:Accessing sensitive environment variables")
    fi

    # HIGH: Obfuscation patterns
    if echo "$content" | grep -qiE 'base64\s+(-d|--decode)|base64\s+-D'; then
        findings+=("HIGH:Base64 decoding detected (possible obfuscation)")
    fi
    if echo "$content" | grep -qiE 'xxd\s+-r|printf.*\\x[0-9a-f]{2}'; then
        findings+=("HIGH:Hex decoding detected (possible obfuscation)")
    fi
    if echo "$content" | grep -qiE '\$\(echo.*\|.*rev\)|\$\(rev\s*<<<'; then
        findings+=("HIGH:String reversal detected (possible obfuscation)")
    fi

    # MEDIUM: Dynamic execution
    if echo "$content" | grep -qiE '\beval\s+["$]|\beval\s*\('; then
        findings+=("MEDIUM:Dynamic eval execution")
    fi
    if echo "$content" | grep -qiE 'source\s+<\(|source\s+/dev/stdin'; then
        findings+=("MEDIUM:Dynamic source execution")
    fi
    if echo "$content" | grep -qiE '\bexec\s+["`$]'; then
        findings+=("MEDIUM:Dynamic exec execution")
    fi

    # MEDIUM: External package installation
    if echo "$content" | grep -qiE 'npx\s+-y\s|npm\s+install\s|pip\s+install\s|gem\s+install'; then
        findings+=("MEDIUM:External package installation detected")
    fi

    # LOW: Network requests (without POST)
    if echo "$content" | grep -qiE '\bcurl\b|\bwget\b' && ! echo "$content" | grep -qiE 'curl.*(-X\s*POST|--data|-d\s)'; then
        findings+=("LOW:Network requests detected (review URLs)")
    fi

    # Output findings
    for finding in "${findings[@]}"; do
        echo "$finding"
    done
}

# Analyze a config file for security risks
analyze_config_file() {
    local file="$1"
    local findings=()

    # Read file content
    local content
    content=$(head -c 10000 "$file" 2>/dev/null) || return

    # Check for dangerous permission settings
    if echo "$content" | grep -qiE '"bypassPermissions"\s*:\s*true|"skipVerify"\s*:\s*true'; then
        findings+=("MEDIUM:Dangerous permission bypass enabled")
    fi

    # Check for MCP server definitions with external commands
    if echo "$content" | grep -qiE '"mcpServers"\s*:' && echo "$content" | grep -qiE '"command"\s*:'; then
        findings+=("LOW:MCP servers configured (review commands)")
    fi

    # Check for external URLs
    if echo "$content" | grep -qiE '"(url|endpoint|server|host)"\s*:\s*"https?://'; then
        findings+=("LOW:External URLs configured (review endpoints)")
    fi

    # Check for embedded commands in hooks
    if echo "$content" | grep -qiE '"hooks"\s*:' && echo "$content" | grep -qiE '"command"\s*:'; then
        findings+=("LOW:Hooks with commands configured (review)")
    fi

    # Check for API keys in config (should be in env vars)
    if echo "$content" | grep -qiE '"(api_key|apiKey|api-key|token|secret)"\s*:\s*"[^"]{10,}"'; then
        findings+=("MEDIUM:API key or secret in config file")
    fi

    # Output findings
    for finding in "${findings[@]}"; do
        echo "$finding"
    done
}

# Scan an agent directory for security issues
scan_agent_directory() {
    local agent_name="$1"
    local agent_dir="$2"
    local scope="$3"  # "Global" or "Project"

    echo ""
    echo "[$agent_name - $scope]"
    echo "────────────────────────────────────────"

    AGENT_SCAN_AGENTS=$((AGENT_SCAN_AGENTS + 1))

    local has_issues=false
    local script_count=0
    local config_count=0
    declare -a script_issues=()
    declare -a config_issues=()

    # Find script files (limit depth to 3 for performance)
    local tmpfile
    tmpfile=$(mktemp)
    find "$agent_dir" -maxdepth 3 -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.ps1" \) 2>/dev/null > "$tmpfile" || true

    while IFS= read -r script; do
        [[ -z "$script" ]] && continue
        [[ ! -f "$script" ]] && continue
        script_count=$((script_count + 1))
        AGENT_SCAN_SCRIPTS=$((AGENT_SCAN_SCRIPTS + 1))

        local findings
        findings=$(analyze_script_file "$script" 2>/dev/null) || true
        if [[ -n "$findings" ]]; then
            local rel_path="${script#"$agent_dir/"}"
            while IFS= read -r finding; do
                [[ -z "$finding" ]] && continue
                local level="${finding%%:*}"
                local msg="${finding#*:}"
                script_issues+=("$rel_path: $msg")

                case "$level" in
                    HIGH) AGENT_SCAN_HIGH=$((AGENT_SCAN_HIGH + 1)) ;;
                    MEDIUM) AGENT_SCAN_MEDIUM=$((AGENT_SCAN_MEDIUM + 1)) ;;
                    LOW) AGENT_SCAN_LOW=$((AGENT_SCAN_LOW + 1)) ;;
                esac
            done <<< "$findings"
        fi
    done < "$tmpfile"
    rm -f "$tmpfile"

    if [[ ${#script_issues[@]} -gt 0 ]]; then
        has_issues=true
        print_warn "scripts ($script_count files analyzed)"
        for issue in "${script_issues[@]}"; do
            echo "    └─ $issue"
        done
    elif [[ $script_count -gt 0 ]]; then
        print_ok "scripts ($script_count files): No issues found"
    fi

    # Find config files (limit depth to 2)
    tmpfile=$(mktemp)
    find "$agent_dir" -maxdepth 2 -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" \) 2>/dev/null > "$tmpfile" || true

    while IFS= read -r config; do
        [[ -z "$config" ]] && continue
        [[ ! -f "$config" ]] && continue
        config_count=$((config_count + 1))
        AGENT_SCAN_CONFIGS=$((AGENT_SCAN_CONFIGS + 1))

        local findings
        findings=$(analyze_config_file "$config" 2>/dev/null) || true
        if [[ -n "$findings" ]]; then
            local rel_path="${config#"$agent_dir/"}"
            while IFS= read -r finding; do
                [[ -z "$finding" ]] && continue
                local level="${finding%%:*}"
                local msg="${finding#*:}"
                config_issues+=("$rel_path: $msg")

                case "$level" in
                    HIGH) AGENT_SCAN_HIGH=$((AGENT_SCAN_HIGH + 1)) ;;
                    MEDIUM) AGENT_SCAN_MEDIUM=$((AGENT_SCAN_MEDIUM + 1)) ;;
                    LOW) AGENT_SCAN_LOW=$((AGENT_SCAN_LOW + 1)) ;;
                esac
            done <<< "$findings"
        fi
    done < "$tmpfile"
    rm -f "$tmpfile"

    if [[ ${#config_issues[@]} -gt 0 ]]; then
        has_issues=true
        print_warn "configs ($config_count files analyzed)"
        for issue in "${config_issues[@]}"; do
            echo "    └─ $issue"
        done
    elif [[ $config_count -gt 0 ]]; then
        print_ok "configs ($config_count files): No issues found"
    fi

    # Summary for this agent
    if ! $has_issues && [[ $script_count -eq 0 ]] && [[ $config_count -eq 0 ]]; then
        print_ok "No executable scripts or configs found"
    fi
}

# Main orchestrator for AI agent security checks
run_agent_security_checks() {
    print_header "AI AGENT SECURITY ANALYSIS"

    # Reset counters
    AGENT_SCAN_AGENTS=0
    AGENT_SCAN_SCRIPTS=0
    AGENT_SCAN_CONFIGS=0
    AGENT_SCAN_HIGH=0
    AGENT_SCAN_MEDIUM=0
    AGENT_SCAN_LOW=0

    # Discover installed agents
    discover_ai_agents

    # Check if any global agents found
    local agent_count=${#GLOBAL_AGENTS[@]}
    if [[ $agent_count -eq 0 ]]; then
        print_info "No AI agents detected in home directory"
    else
        echo ""
        echo "Discovered AI Agents:"
        for agent_info in "${GLOBAL_AGENTS[@]}"; do
            local name="${agent_info%%|*}"
            local path="${agent_info#*|}"
            # Replace underscores with spaces for display
            local display_name="${name//_/ }"
            # Shorten home path for display
            local display_path="${path/$HOME/~}"
            echo "  • $display_name ($display_path)"
        done

        # Scan each global agent
        for agent_info in "${GLOBAL_AGENTS[@]}"; do
            local name="${agent_info%%|*}"
            local path="${agent_info#*|}"
            local display_name="${name//_/ }"
            scan_agent_directory "$display_name" "$path" "Global"
        done
    fi

    # Scan project-level configs
    discover_project_agents

    echo ""
    echo "[Project Level: ${PWD}]"
    echo "────────────────────────────────────────"

    # Check if any project agents found
    if [[ ${#PROJECT_AGENTS[@]} -eq 0 ]]; then
        print_info "No project-level agent configs found"
    else
        for agent_info in "${PROJECT_AGENTS[@]}"; do
            local name="${agent_info%%|*}"
            local path="${agent_info#*|}"
            local display_name="${name//_/ }"
            scan_agent_directory "$display_name" "$path" "Project"
        done
    fi

    # Print summary
    echo ""
    echo "Summary"
    echo "────────────────────────────────────────"
    echo "Agents scanned: $AGENT_SCAN_AGENTS"
    echo "Scripts analyzed: $AGENT_SCAN_SCRIPTS"
    echo "Configs analyzed: $AGENT_SCAN_CONFIGS"

    local total_issues=$((AGENT_SCAN_HIGH + AGENT_SCAN_MEDIUM + AGENT_SCAN_LOW))
    if [[ $total_issues -eq 0 ]]; then
        print_ok "No security issues found"
    else
        print_warn "Issues found: $total_issues ($AGENT_SCAN_HIGH HIGH, $AGENT_SCAN_MEDIUM MEDIUM, $AGENT_SCAN_LOW LOW)"
    fi
}

run_security_checks() {
    print_header "SECURITY ANALYSIS"

    check_firewall
    check_open_ports
    check_ssh_config
    check_antivirus
    check_updates
    check_sensitive_files

    # AI Agent security analysis
    run_agent_security_checks
}

# ============================================================================
# Performance Checks
# ============================================================================

check_cpu() {
    print_info "Checking CPU usage..."

    case $OS in
        windows)
            local cpu_usage="${WIN_DATA[CPU_USAGE]}"
            if [[ -n "$cpu_usage" ]] && [[ "$cpu_usage" =~ ^[0-9]+$ ]]; then
                if [[ "$cpu_usage" -lt 70 ]]; then
                    print_ok "CPU Usage: ${cpu_usage}%"
                elif [[ "$cpu_usage" -lt 90 ]]; then
                    print_warn "CPU Usage: ${cpu_usage}%" "High CPU usage detected"
                else
                    print_fail "CPU Usage: ${cpu_usage}%" "Critical CPU usage - check running processes"
                fi
            else
                print_info "CPU Usage: Unable to measure"
            fi
            ;;
        macos)
            local cpu_idle
            cpu_idle=$(top -l 1 | grep "CPU usage" | awk '{print $7}' | tr -d '%')
            local cpu_usage=$((100 - ${cpu_idle%.*}))
            print_ok "CPU Usage: ~${cpu_usage}%"
            ;;
        linux)
            if command -v mpstat &> /dev/null; then
                local cpu_idle
                cpu_idle=$(mpstat 1 1 | awk '/Average/ {print $NF}')
                local cpu_usage
                cpu_usage=$(echo "100 - $cpu_idle" | bc 2>/dev/null || echo "N/A")
                print_ok "CPU Usage: ${cpu_usage}%"
            elif [[ -f /proc/stat ]]; then
                print_info "CPU: Install sysstat for detailed metrics"
            fi
            ;;
    esac
}

check_memory() {
    print_info "Checking memory usage..."

    case $OS in
        windows)
            local used="${WIN_DATA[MEM_USED]}"
            local total="${WIN_DATA[MEM_TOTAL]}"
            local pct="${WIN_DATA[MEM_PCT]}"
            if [[ "$pct" -lt 80 ]]; then
                print_ok "Memory: ${used}GB / ${total}GB (${pct}%)"
            else
                print_warn "Memory: ${used}GB / ${total}GB (${pct}%)" "High memory usage"
            fi
            ;;
        macos)
            local mem_info
            mem_info=$(vm_stat | awk '
                /Pages free/ {free=$3}
                /Pages active/ {active=$3}
                /Pages inactive/ {inactive=$3}
                /Pages wired/ {wired=$3}
                END {
                    total=(free+active+inactive+wired)*4096/1024/1024/1024
                    used=(active+wired)*4096/1024/1024/1024
                    printf "%.1f|%.1f|%.0f", used, total, (used/total)*100
                }
            ')
            IFS='|' read -r used total pct <<< "$mem_info"
            print_ok "Memory: ${used}GB / ${total}GB (~${pct}%)"
            ;;
        linux)
            local mem_info
            mem_info=$(free -g | awk '/^Mem:/ {printf "%.1f|%.1f|%.0f", $3, $2, ($3/$2)*100}')
            IFS='|' read -r used total pct <<< "$mem_info"
            if [[ "$pct" -lt 80 ]]; then
                print_ok "Memory: ${used}GB / ${total}GB (${pct}%)"
            else
                print_warn "Memory: ${used}GB / ${total}GB (${pct}%)" "High memory usage"
            fi
            ;;
    esac
}

check_disk() {
    print_info "Checking disk usage..."

    case $OS in
        windows)
            while IFS=':' read -r drive used total pct; do
                [[ -z "$drive" ]] && continue
                if [[ -n "$total" ]] && [[ "$total" -gt 0 ]]; then
                    if [[ -z "$pct" ]]; then pct=0; fi
                    if [[ "$pct" -lt 80 ]]; then
                        print_ok "Disk $drive: ${used}GB / ${total}GB (${pct}%)"
                    elif [[ "$pct" -lt 90 ]]; then
                        print_warn "Disk $drive: ${used}GB / ${total}GB (${pct}%)" "Consider cleanup"
                    else
                        print_fail "Disk $drive: ${used}GB / ${total}GB (${pct}%)" "Critical - free up space"
                    fi
                fi
            done <<< "$WIN_DATA_DISKS"
            ;;
        macos|linux)
            df -h 2>/dev/null | awk 'NR>1 && /^\/dev/ {
                pct = int($5)
                if (pct < 80) status = "ok"
                else if (pct < 90) status = "warn"
                else status = "fail"
                print status "|" $1 ": " $3 " / " $2 " (" $5 ")"
            }' | while IFS='|' read -r status info; do
                case $status in
                    ok) print_ok "Disk $info" ;;
                    warn) print_warn "Disk $info" "Consider cleanup" ;;
                    fail) print_fail "Disk $info" "Critical - free up space" ;;
                esac
            done
            ;;
    esac
}

check_top_processes() {
    print_info "Top resource-consuming processes..."

    echo ""
    case $OS in
        windows)
            while IFS=':' read -r name cpu mem; do
                [[ -z "$name" ]] && continue
                printf "  %-30s CPU: %8ss  Mem: %6sMB\n" "$name" "$cpu" "$mem"
            done <<< "$WIN_DATA_PROCS"
            ;;
        macos)
            ps aux | sort -nrk 3 | head -5 | awk '{printf "  %-30s CPU: %5s%%  Mem: %5s%%\n", $11, $3, $4}'
            ;;
        linux)
            ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "  %-30s CPU: %5s%%  Mem: %5s%%\n", $11, $3, $4}'
            ;;
    esac
}

check_network_connections() {
    print_info "Checking network connections..."

    local established=0
    local listening=0

    case $OS in
        windows)
            established="${WIN_DATA[NET_ESTABLISHED]}"
            listening="${WIN_DATA[NET_LISTENING]}"
            ;;
        macos|linux)
            if command -v ss &> /dev/null; then
                established=$(ss -t state established 2>/dev/null | wc -l)
                listening=$(ss -tln 2>/dev/null | tail -n +2 | wc -l)
            elif command -v netstat &> /dev/null; then
                established=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo "0")
                listening=$(netstat -an 2>/dev/null | grep -c LISTEN || echo "0")
            fi
            ;;
    esac

    print_ok "Network: $established established, $listening listening"
}

run_performance_checks() {
    print_header "PERFORMANCE METRICS"

    check_cpu
    check_memory
    check_disk
    check_top_processes
    check_network_connections
}

# ============================================================================
# Optimization Suggestions
# ============================================================================

check_temp_files() {
    print_info "Checking temporary files..."

    local temp_size=""

    case $OS in
        windows)
            temp_size="${WIN_DATA[TEMP_SIZE]}"
            if [[ -n "$temp_size" ]] && [[ "$temp_size" -gt 500 ]]; then
                print_warn "Temp files: ${temp_size}MB in %TEMP%" "Consider running disk cleanup"
            else
                print_ok "Temp files: ${temp_size:-0}MB in %TEMP%"
            fi
            ;;
        macos|linux)
            temp_size=$(du -sm /tmp 2>/dev/null | cut -f1)
            if [[ "$temp_size" -gt 500 ]]; then
                print_warn "Temp files: ${temp_size}MB in /tmp" "Consider cleanup"
            else
                print_ok "Temp files: ${temp_size}MB in /tmp"
            fi
            ;;
    esac
}

check_cache_dirs() {
    print_info "Checking common cache directories..."

    declare -A caches=()

    case $OS in
        windows)
            # npm cache
            if [[ -d "$APPDATA/npm-cache" ]]; then
                local npm_size
                npm_size=$(du -sm "$APPDATA/npm-cache" 2>/dev/null | cut -f1)
                caches["npm"]=$npm_size
            fi
            ;;
        macos)
            if [[ -d "$HOME/Library/Caches" ]]; then
                local cache_size
                cache_size=$(du -sm "$HOME/Library/Caches" 2>/dev/null | cut -f1)
                caches["Library/Caches"]=$cache_size
            fi
            ;;
        linux)
            if [[ -d "$HOME/.cache" ]]; then
                local cache_size
                cache_size=$(du -sm "$HOME/.cache" 2>/dev/null | cut -f1)
                caches[".cache"]=$cache_size
            fi
            ;;
    esac

    # Common caches across platforms
    if [[ -d "$HOME/.npm" ]]; then
        caches["npm"]=$(du -sm "$HOME/.npm" 2>/dev/null | cut -f1)
    fi

    for cache in "${!caches[@]}"; do
        local size=${caches[$cache]}
        if [[ "$size" -gt 1000 ]]; then
            print_warn "Cache ($cache): ${size}MB" "Consider cleaning"
        else
            print_ok "Cache ($cache): ${size}MB"
        fi
    done
}

check_docker() {
    print_info "Checking Docker resources..."

    if ! command -v docker &> /dev/null; then
        print_info "Docker: Not installed"
        return
    fi

    if ! docker info &> /dev/null; then
        print_info "Docker: Not running or no permission"
        return
    fi

    local images volumes
    images=$(docker images -q 2>/dev/null | wc -l)
    volumes=$(docker volume ls -q 2>/dev/null | wc -l)

    local dangling
    dangling=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)

    if [[ "$dangling" -gt 0 ]]; then
        print_warn "Docker: $images images, $volumes volumes, $dangling dangling images" "Run 'docker image prune' to clean"
    else
        print_ok "Docker: $images images, $volumes volumes"
    fi
}

check_startup_items() {
    print_info "Checking startup items..."

    case $OS in
        windows)
            print_info "Startup items: ${WIN_DATA[STARTUP_COUNT]} registered"
            ;;
        macos)
            local launch_agents
            launch_agents=$(ls -1 "$HOME/Library/LaunchAgents" 2>/dev/null | wc -l | tr -d ' ')
            print_info "Launch Agents: $launch_agents in ~/Library/LaunchAgents"
            ;;
        linux)
            if [[ -d "$HOME/.config/autostart" ]]; then
                local autostart
                autostart=$(ls -1 "$HOME/.config/autostart" 2>/dev/null | wc -l)
                print_info "Autostart: $autostart items in ~/.config/autostart"
            fi
            ;;
    esac
}

run_optimization_checks() {
    print_header "OPTIMIZATION OPPORTUNITIES"

    check_temp_files
    check_cache_dirs
    check_docker
    check_startup_items
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Redirect output to file if specified
    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > "$OUTPUT_FILE"
    fi

    # Collect all Windows data in a single PowerShell call
    collect_windows_data

    print_header "SYSTEM HEALTH CHECK REPORT"
    print_system_info

    if $RUN_SECURITY; then
        run_security_checks
    fi

    if $RUN_PERFORMANCE; then
        run_performance_checks
    fi

    if $RUN_OPTIMIZE; then
        run_optimization_checks
    fi

    echo ""
    print_header "END OF REPORT"

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "Report saved to: $OUTPUT_FILE" >&2
    fi
}

main
