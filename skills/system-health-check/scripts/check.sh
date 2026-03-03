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
        pwsh -NoProfile -Command "$1" 2>/dev/null
    elif command -v powershell.exe &> /dev/null; then
        powershell.exe -NoProfile -Command "$1" 2>/dev/null
    else
        echo "N/A"
    fi
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
            local win_ver
            win_ver=$(run_powershell '[System.Environment]::OSVersion.VersionString')
            echo "System: Windows - $win_ver"
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
            local fw_status
            fw_status=$(run_powershell '(Get-NetFirewallProfile -Profile Domain,Public,Private | Where-Object {$_.Enabled -eq $true}).Count')
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
            ports=$(run_powershell 'Get-NetTCPConnection -State Listen | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique | ForEach-Object { $_ }' | tr '\n' ' ')
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
            local defender_status
            defender_status=$(run_powershell '(Get-MpComputerStatus).RealTimeProtectionEnabled')
            if [[ "$defender_status" == "True" ]]; then
                print_ok "Windows Defender: Real-time protection enabled"
            else
                print_fail "Windows Defender: Real-time protection disabled" "Enable real-time protection in Windows Security"
            fi

            local last_scan
            last_scan=$(run_powershell '(Get-MpComputerStatus).FullScanEndTime')
            print_info "Last full scan: $last_scan"
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
            local pending
            pending=$(run_powershell '(New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0").Updates.Count' 2>/dev/null || echo "N/A")
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

run_security_checks() {
    print_header "SECURITY ANALYSIS"

    check_firewall
    check_open_ports
    check_ssh_config
    check_antivirus
    check_updates
    check_sensitive_files
}

# ============================================================================
# Performance Checks
# ============================================================================

check_cpu() {
    print_info "Checking CPU usage..."

    case $OS in
        windows)
            local cpu_usage
            cpu_usage=$(run_powershell '(Get-Counter "\Processor(_Total)\% Processor Time").CounterSamples.CookedValue' | cut -d. -f1)
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
            local mem_info
            mem_info=$(run_powershell '
                $os = Get-CimInstance Win32_OperatingSystem
                $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
                $free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
                $used = [math]::Round($total - $free, 1)
                $pct = [math]::Round(($used / $total) * 100, 0)
                Write-Output "$used|$total|$pct"
            ')
            IFS='|' read -r used total pct <<< "$mem_info"
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
            run_powershell '
                Get-PSDrive -PSProvider FileSystem | ForEach-Object {
                    $total = [math]::Round($_.Used/1GB + $_.Free/1GB, 0)
                    $used = [math]::Round($_.Used/1GB, 0)
                    $pct = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 0) } else { 0 }
                    Write-Output "$($_.Name):|$used|$total|$pct"
                }
            ' | tr -d '\r' | while IFS='|' read -r drive used total pct; do
                # Clean up variables
                pct=$(echo "$pct" | tr -cd '0-9')
                total=$(echo "$total" | tr -cd '0-9')
                if [[ -n "$drive" ]] && [[ -n "$total" ]] && [[ "$total" -gt 0 ]]; then
                    if [[ -z "$pct" ]]; then pct=0; fi
                    if [[ "$pct" -lt 80 ]]; then
                        print_ok "Disk $drive ${used}GB / ${total}GB (${pct}%)"
                    elif [[ "$pct" -lt 90 ]]; then
                        print_warn "Disk $drive ${used}GB / ${total}GB (${pct}%)" "Consider cleanup"
                    else
                        print_fail "Disk $drive ${used}GB / ${total}GB (${pct}%)" "Critical - free up space"
                    fi
                fi
            done
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
            run_powershell '
                Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 |
                ForEach-Object {
                    $cpu = [math]::Round($_.CPU, 1)
                    $mem = [math]::Round($_.WorkingSet64/1MB, 0)
                    Write-Output ("  {0,-30} CPU: {1,8}s  Mem: {2,6}MB" -f $_.ProcessName, $cpu, $mem)
                }
            '
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
            established=$(run_powershell '(Get-NetTCPConnection -State Established).Count')
            listening=$(run_powershell '(Get-NetTCPConnection -State Listen).Count')
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
            temp_size=$(run_powershell '
                $size = (Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum / 1MB
                [math]::Round($size, 0)
            ')
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
            local count
            count=$(run_powershell '(Get-CimInstance Win32_StartupCommand).Count')
            print_info "Startup items: $count registered"
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
