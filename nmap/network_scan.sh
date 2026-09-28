#!/usr/bin/env bash
# network_scan.sh — discover live hosts on local subnets, then nmap-scan their ports
# Usage: ./network_scan.sh [--top-ports N] [--ports "22,80,443"] [--subnet 192.168.1.0/24] [-oA output]

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
TOP_PORTS=100
CUSTOM_PORTS=""
CUSTOM_SUBNET=""
OUTPUT_BASE=""
PING_TIMEOUT=1          # seconds per host for host discovery
NMAP_TIMING="-T4"       # T1=sneaky … T5=insane

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

banner() {
  echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  Network Scanner — nmap-powered host + port discovery${RESET}"
  echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
}

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "  --top-ports N          Scan top N common nmap ports (default: ${TOP_PORTS})"
  echo "  --ports 22,80,443      Scan specific ports instead of top-N"
  echo "  --subnet 192.168.0/24  Override: scan specific subnet (skip interface detection)"
  echo "  -oA <base>             Write nmap output in all formats to <base>.*"
  echo "  -T <0-5>               nmap timing template (default: 4)"
  echo "  -h, --help             Show this help"
  exit 0
}

die() { echo -e "${RED}[!] $*${RESET}" >&2; exit 1; }
info() { echo -e "${CYAN}[*]${RESET} $*"; }
ok()   { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[~]${RESET} $*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --top-ports)  TOP_PORTS="$2";    shift 2 ;;
    --ports)      CUSTOM_PORTS="$2"; shift 2 ;;
    --subnet)     CUSTOM_SUBNET="$2";shift 2 ;;
    -oA)          OUTPUT_BASE="$2";  shift 2 ;;
    -T)           NMAP_TIMING="-T$2";shift 2 ;;
    -h|--help)    usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ── Dependency checks ─────────────────────────────────────────────────────────
command -v nmap  &>/dev/null || die "nmap not found. Install it: apt/brew/choco install nmap"

# ── Port argument for nmap ────────────────────────────────────────────────────
if [[ -n "$CUSTOM_PORTS" ]]; then
  PORT_ARG="-p ${CUSTOM_PORTS}"
  PORT_DESC="ports: ${CUSTOM_PORTS}"
else
  PORT_ARG="--top-ports ${TOP_PORTS}"
  PORT_DESC="top ${TOP_PORTS} ports"
fi

# ── Get local subnets ─────────────────────────────────────────────────────────
get_subnets() {
  local subnets=()

  # Linux: ip addr
  if command -v ip &>/dev/null; then
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*inet[[:space:]]([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+) ]] || continue
      cidr="${BASH_REMATCH[1]}"
      # Skip loopback and APIPA
      [[ "$cidr" =~ ^127\. || "$cidr" =~ ^169\.254 ]] && continue
      # Network address (zero host bits)
      net=$(python3 -c "import ipaddress; print(ipaddress.IPv4Network('${cidr}', strict=False))" 2>/dev/null) || continue
      [[ -z "$net" ]] && continue
      # Skip subnets larger than /16
      prefix="${net##*/}"
      (( prefix < 16 )) && { warn "Skipping ${net} — too large (/${prefix})"; continue; }
      subnets+=("$net")
    done < <(ip -4 addr show scope global)

  # macOS: ifconfig
  elif command -v ifconfig &>/dev/null; then
    while IFS= read -r line; do
      [[ "$line" =~ inet[[:space:]]([0-9.]+)[[:space:]]+netmask[[:space:]]0x([0-9a-f]+) ]] || continue
      ip="${BASH_REMATCH[1]}"
      hex_mask="${BASH_REMATCH[2]}"
      [[ "$ip" =~ ^127\. || "$ip" =~ ^169\.254 ]] && continue
      net=$(python3 -c "
import ipaddress, struct
mask = struct.unpack('>I', bytes.fromhex('${hex_mask}'))[0]
prefix = bin(mask).count('1')
print(ipaddress.IPv4Network(f'${ip}/{prefix}', strict=False))
" 2>/dev/null) || continue
      [[ -z "$net" ]] && continue
      prefix="${net##*/}"
      (( prefix < 16 )) && { warn "Skipping ${net} — too large (/${prefix})"; continue; }
      subnets+=("$net")
    done < <(ifconfig)

  # Windows / Git Bash / WSL fallback via PowerShell
  elif command -v powershell.exe &>/dev/null || command -v pwsh &>/dev/null; then
    PS=$(command -v pwsh 2>/dev/null || echo "powershell.exe")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ip="${line%%/*}"; prefix="${line##*/}"
      [[ "$ip" =~ ^127\. || "$ip" =~ ^169\.254 ]] && continue
      (( prefix < 16 )) && { warn "Skipping ${ip}/${prefix} — too large"; continue; }
      net=$(python3 -c "import ipaddress; print(ipaddress.IPv4Network('${ip}/${prefix}', strict=False))" 2>/dev/null) || continue
      subnets+=("$net")
    done < <("$PS" -NoProfile -Command \
      "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.PrefixLength -ge 16 -and \$_.IPAddress -notlike '127.*' -and \$_.IPAddress -notlike '169.254.*' } | ForEach-Object { \$ipB = [System.Net.IPAddress]::Parse(\$_.IPAddress).GetAddressBytes(); \$pre = [int]\$_.PrefixLength; \$mB = New-Object byte[] 4; for (\$i=0;\$i -lt 4;\$i++) { \$b=[Math]::Min(8,[Math]::Max(0,\$pre-\$i*8)); if(\$b-eq 8){\$mB[\$i]=255}elseif(\$b-eq 0){\$mB[\$i]=0}else{\$mB[\$i]=[byte](256-[Math]::Pow(2,8-\$b))} }; \$nB=New-Object byte[] 4; for(\$i=0;\$i -lt 4;\$i++){\$nB[\$i]=\$ipB[\$i] -band \$mB[\$i]}; ([System.Net.IPAddress]::new(\$nB)).ToString() + '/' + \$pre }")
  fi

  printf '%s\n' "${subnets[@]}"
}

# ── Output flag ───────────────────────────────────────────────────────────────
output_flag() {
  local subnet="$1"
  if [[ -n "$OUTPUT_BASE" ]]; then
    safe="${subnet//\//_}"
    echo "-oA ${OUTPUT_BASE}_${safe}"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
banner
info "Port selection : ${PORT_DESC}"
info "nmap timing    : ${NMAP_TIMING}"
echo ""

if [[ -n "$CUSTOM_SUBNET" ]]; then
  subnets=("$CUSTOM_SUBNET")
else
  mapfile -t subnets < <(get_subnets)
fi

[[ ${#subnets[@]} -eq 0 ]] && die "No usable subnets found. Use --subnet to specify one."

for subnet in "${subnets[@]}"; do
  echo ""
  info "Subnet: ${BOLD}${subnet}${RESET}"
  echo "──────────────────────────────────────────────────────"

  # Step 1: host discovery (ping scan)
  info "Phase 1 — host discovery on ${subnet}..."
  LIVE_HOSTS_FILE=$(mktemp /tmp/live_hosts_XXXX.txt)
  trap 'rm -f "$LIVE_HOSTS_FILE"' EXIT

  nmap -sn $NMAP_TIMING --host-timeout "${PING_TIMEOUT}s" \
    -oG "$LIVE_HOSTS_FILE" "$subnet" &>/dev/null

  mapfile -t live_ips < <(grep "^Host:" "$LIVE_HOSTS_FILE" | awk '{print $2}')

  if [[ ${#live_ips[@]} -eq 0 ]]; then
    warn "No live hosts found in ${subnet}"
    rm -f "$LIVE_HOSTS_FILE"
    continue
  fi

  ok "${#live_ips[@]} host(s) alive: ${live_ips[*]}"
  echo ""

  # Step 2: port scan live hosts
  info "Phase 2 — port scan (${PORT_DESC})..."
  echo ""

  # Build optional -oA flag
  oA_flag=""
  if [[ -n "$OUTPUT_BASE" ]]; then
    safe="${subnet//\//_}"
    oA_flag="-oA ${OUTPUT_BASE}_${safe}"
  fi

  # shellcheck disable=SC2086
  nmap -sV --open $NMAP_TIMING $PORT_ARG \
    ${oA_flag} \
    "${live_ips[@]}"

  rm -f "$LIVE_HOSTS_FILE"
done

echo ""
info "Scan complete."
