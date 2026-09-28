#!/usr/bin/env bash
# webapp_recon.sh — automated recon pipeline for a web app bug bounty target
# Usage: ./webapp_recon.sh -d example.com [-o output_dir] [--full] [--screenshots] [--nuclei] [--brute wordlist.txt]
#
# ⚠️  Only run this against domains explicitly in scope of a bug bounty program
#     or another engagement you are authorized to test.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DOMAIN=""
OUT_DIR=""
DO_SCREENSHOTS=0
DO_NUCLEI=0
DO_BRUTE=0
WORDLIST=""
FULL=0
RATE_LIMIT=150   # requests/sec cap for active tools (httpx, ffuf, nuclei)

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

banner() {
  echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  Web App Recon — bug bounty reconnaissance pipeline${RESET}"
  echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
}

usage() {
  echo "Usage: $0 -d <domain> [OPTIONS]"
  echo ""
  echo "  -d, --domain <domain>   Root domain in scope (required), e.g. example.com"
  echo "  -o, --output <dir>      Output directory (default: ./recon_<domain>)"
  echo "  --full                  Also run: URL collection (gau/waybackurls) + nuclei"
  echo "  --screenshots           Take screenshots of live hosts (gowitness)"
  echo "  --nuclei                Run nuclei templates against live hosts"
  echo "  --brute <wordlist>      Run content discovery (ffuf) with this wordlist"
  echo "  --rate <N>              Requests/sec cap for active tools (default: ${RATE_LIMIT})"
  echo "  -h, --help              Show this help"
  exit 0
}

die() { echo -e "${RED}[!] $*${RESET}" >&2; exit 1; }
info() { echo -e "${CYAN}[*]${RESET} $*"; }
ok()   { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[~]${RESET} $*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--domain)     DOMAIN="$2";        shift 2 ;;
    -o|--output)     OUT_DIR="$2";       shift 2 ;;
    --full)          FULL=1;             shift ;;
    --screenshots)   DO_SCREENSHOTS=1;   shift ;;
    --nuclei)        DO_NUCLEI=1;        shift ;;
    --brute)         DO_BRUTE=1; WORDLIST="$2"; shift 2 ;;
    --rate)          RATE_LIMIT="$2";    shift 2 ;;
    -h|--help)       usage ;;
    *) die "Unknown option: $1 (use -h for help)" ;;
  esac
done

[[ -z "$DOMAIN" ]] && die "Missing required -d/--domain. Use -h for help."
[[ -n "$OUT_DIR" ]] || OUT_DIR="./recon_${DOMAIN}"
[[ $DO_BRUTE -eq 1 && ! -f "$WORDLIST" ]] && die "Wordlist not found: ${WORDLIST}"

mkdir -p "$OUT_DIR"
SUBS_FILE="${OUT_DIR}/subdomains.txt"
LIVE_FILE="${OUT_DIR}/live_hosts.txt"
URLS_FILE="${OUT_DIR}/urls.txt"
FFUF_FILE="${OUT_DIR}/content_discovery.txt"
NUCLEI_FILE="${OUT_DIR}/nuclei_findings.txt"
SCREENSHOTS_DIR="${OUT_DIR}/screenshots"

need() { command -v "$1" &>/dev/null; }
require_warn() {
  need "$1" || { warn "$1 not found — skipping this step (install: $2)"; return 1; }
}

# ── Step 1: subdomain enumeration (passive) ───────────────────────────────────
enumerate_subdomains() {
  info "Phase 1 — passive subdomain enumeration for ${DOMAIN}..."
  : > "$SUBS_FILE"

  if require_warn subfinder "go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"; then
    subfinder -silent -d "$DOMAIN" >> "$SUBS_FILE" 2>/dev/null || true
  fi

  if require_warn assetfinder "go install github.com/tomnomnom/assetfinder@latest"; then
    assetfinder --subs-only "$DOMAIN" >> "$SUBS_FILE" 2>/dev/null || true
  fi

  if require_warn amass "go install -v github.com/owasp-amass/amass/v4/...@master"; then
    amass enum -passive -d "$DOMAIN" >> "$SUBS_FILE" 2>/dev/null || true
  fi

  # Always include the apex domain itself
  echo "$DOMAIN" >> "$SUBS_FILE"

  sort -u -o "$SUBS_FILE" "$SUBS_FILE"
  ok "$(wc -l < "$SUBS_FILE") unique host(s) written to ${SUBS_FILE}"
}

# ── Step 2: probe for live HTTP(S) hosts ──────────────────────────────────────
probe_live_hosts() {
  info "Phase 2 — probing live HTTP(S) hosts..."

  if ! require_warn httpx "go install github.com/projectdiscovery/httpx/cmd/httpx@latest"; then
    warn "Falling back to raw subdomain list (no status/title/tech info)"
    cp "$SUBS_FILE" "$LIVE_FILE"
    return
  fi

  httpx -silent -rate-limit "$RATE_LIMIT" -status-code -title -tech-detect \
    -l "$SUBS_FILE" -o "$LIVE_FILE" 2>/dev/null || true

  ok "$(wc -l < "$LIVE_FILE" 2>/dev/null || echo 0) live host(s) written to ${LIVE_FILE}"
}

# ── Step 3 (optional): historic URL collection ────────────────────────────────
collect_urls() {
  info "Phase 3 — collecting historic URLs (params, endpoints)..."
  : > "$URLS_FILE"

  if require_warn gau "go install github.com/lc/gau/v2/cmd/gau@latest"; then
    gau --subs "$DOMAIN" >> "$URLS_FILE" 2>/dev/null || true
  fi

  if require_warn waybackurls "go install github.com/tomnomnom/waybackurls@latest"; then
    echo "$DOMAIN" | waybackurls >> "$URLS_FILE" 2>/dev/null || true
  fi

  if [[ -s "$URLS_FILE" ]]; then
    sort -u -o "$URLS_FILE" "$URLS_FILE"
    ok "$(wc -l < "$URLS_FILE") unique URL(s) written to ${URLS_FILE}"
  else
    warn "No URLs collected (missing tools or no results)"
  fi
}

# ── Step 4 (optional): content discovery ──────────────────────────────────────
brute_force_content() {
  info "Phase 4 — content discovery (ffuf) on live hosts..."

  if ! require_warn ffuf "go install github.com/ffuf/ffuf/v2@latest"; then
    return
  fi
  [[ -s "$LIVE_FILE" ]] || { warn "No live hosts to brute-force"; return; }

  : > "$FFUF_FILE"
  while IFS= read -r host; do
    url="${host%% *}"                # first whitespace-separated field (httpx prefixes url first)
    [[ "$url" =~ ^https?:// ]] || url="https://${url}"
    info "  → ${url}"
    ffuf -s -u "${url}/FUZZ" -w "$WORDLIST" -mc 200,204,301,302,307,401,403 \
      -rate "$RATE_LIMIT" 2>/dev/null >> "$FFUF_FILE" || true
  done < "$LIVE_FILE"

  ok "Content discovery results written to ${FFUF_FILE}"
}

# ── Step 5 (optional): screenshots ────────────────────────────────────────────
take_screenshots() {
  info "Phase 5 — screenshotting live hosts (gowitness)..."

  if ! require_warn gowitness "go install github.com/sensepost/gowitness@latest"; then
    return
  fi
  [[ -s "$LIVE_FILE" ]] || { warn "No live hosts to screenshot"; return; }

  mkdir -p "$SCREENSHOTS_DIR"
  awk '{print $1}' "$LIVE_FILE" > "${OUT_DIR}/.gowitness_targets.txt"
  gowitness file -f "${OUT_DIR}/.gowitness_targets.txt" -P "$SCREENSHOTS_DIR" --no-http 2>/dev/null || \
    gowitness scan file -f "${OUT_DIR}/.gowitness_targets.txt" -s "$SCREENSHOTS_DIR" 2>/dev/null || \
    warn "gowitness invocation failed — check the installed version's CLI syntax"
  rm -f "${OUT_DIR}/.gowitness_targets.txt"

  ok "Screenshots (if any) saved under ${SCREENSHOTS_DIR}"
}

# ── Step 6 (optional): nuclei vulnerability templates ─────────────────────────
run_nuclei() {
  info "Phase 6 — running nuclei templates on live hosts..."

  if ! require_warn nuclei "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"; then
    return
  fi
  [[ -s "$LIVE_FILE" ]] || { warn "No live hosts to scan"; return; }

  awk '{print $1}' "$LIVE_FILE" > "${OUT_DIR}/.nuclei_targets.txt"
  nuclei -l "${OUT_DIR}/.nuclei_targets.txt" -rate-limit "$RATE_LIMIT" \
    -o "$NUCLEI_FILE" 2>/dev/null || true
  rm -f "${OUT_DIR}/.nuclei_targets.txt"

  ok "Nuclei findings written to ${NUCLEI_FILE}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
banner
info "Target        : ${DOMAIN}"
info "Output dir    : ${OUT_DIR}"
info "Rate limit    : ${RATE_LIMIT} req/s"
echo ""

enumerate_subdomains
echo ""
probe_live_hosts
echo ""

if [[ $FULL -eq 1 ]]; then
  collect_urls
  echo ""
  DO_NUCLEI=1
fi

if [[ $DO_BRUTE -eq 1 ]]; then
  brute_force_content
  echo ""
fi

if [[ $DO_SCREENSHOTS -eq 1 ]]; then
  take_screenshots
  echo ""
fi

if [[ $DO_NUCLEI -eq 1 ]]; then
  run_nuclei
  echo ""
fi

info "Recon complete. Results in: ${OUT_DIR}"
