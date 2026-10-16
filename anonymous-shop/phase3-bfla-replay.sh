#!/usr/bin/env bash
# phase3-bfla-replay.sh — rejeu de contrôle d'accès inter-rôles (BFLA / élévation)
#   pour le TP interne anonymous_eshop (cf. livrable-phase1-cartographie.md).
#
# Principe : les 3 fronts proxifient tous /api/* vers le même backend :8080.
# Toute la sécurité d'accès repose donc sur la validation du rôle dans le JWT
# côté backend. Ce script rejoue chaque endpoint réservé vendor/admin avec un
# JWT buyer (puis vendor), et classe la réponse :
#   401/403 → OK (le backend bloque bien)
#   200     → BFLA / élévation de privilège (le rôle n'est pas vérifié)
#   autre   → à inspecter manuellement
#
# ⚠️  À exécuter uniquement contre VOTRE instance locale de dev (localhost /
#     10.0.2.2:8080). Jamais contre anonymous.shop ni avec des clés Stripe live.
#
# Usage :
#   ./phase3-bfla-replay.sh --base http://10.0.2.2:8080 \
#       --buyer-jwt "eyJ..." [--vendor-jwt "eyJ..."]
#   # ou laisser le script se connecter lui-même :
#   ./phase3-bfla-replay.sh --base http://10.0.2.2:8080 \
#       --buyer-login acheteur@test.local:Passw0rd! \
#       --vendor-login vendeur@test.local:Passw0rd!

set -euo pipefail

BASE="http://10.0.2.2:8080"
BUYER_JWT=""
VENDOR_JWT=""
BUYER_LOGIN=""
VENDOR_LOGIN=""
OUT_DIR=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

usage() {
  cat <<EOF
Usage: $0 --base <url> (--buyer-jwt <jwt> | --buyer-login <email:pass>) [options]

  --base <url>              Backend (défaut: ${BASE})
  --buyer-jwt <jwt>         JWT buyer déjà capturé
  --vendor-jwt <jwt>        JWT vendor déjà capturé (pour tester vendor→admin)
  --buyer-login <e:p>       Identifiants buyer -> login automatique via /api/auth/login
  --vendor-login <e:p>      Identifiants vendor -> login automatique
  -o, --output <dir>        Dossier de sortie (défaut: ./phase3_<horodatage>)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2;;
    --buyer-jwt) BUYER_JWT="$2"; shift 2;;
    --vendor-jwt) VENDOR_JWT="$2"; shift 2;;
    --buyer-login) BUYER_LOGIN="$2"; shift 2;;
    --vendor-login) VENDOR_LOGIN="$2"; shift 2;;
    -o|--output) OUT_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Option inconnue: $1"; usage; exit 1;;
  esac
done

BASE="${BASE%/}"
OUT_DIR="${OUT_DIR:-./phase3_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR/responses"
RESULTS="$OUT_DIR/resultats.csv"
echo "role_jwt,methode,endpoint,role_attendu,code_http,verdict" > "$RESULTS"

# ── Login helper ────────────────────────────────────────────────────────────
login() {   # login <email:pass> -> echo JWT
  local creds="$1" email pass body token
  email="${creds%%:*}"; pass="${creds#*:}"
  body=$(curl -s -X POST "$BASE/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}") || true
  # extrait un champ token/accessToken/jwt du JSON renvoyé
  token=$(echo "$body" | grep -oE '"(token|accessToken|jwt)"[[:space:]]*:[[:space:]]*"[^"]+"' \
          | head -1 | sed -E 's/.*:"([^"]+)"/\1/')
  if [[ -z "$token" ]]; then
    echo -e "${YELLOW}[!] Login $email : pas de token extrait. Réponse brute :${RESET}" >&2
    echo "$body" >&2
    echo -e "${YELLOW}    (compte 2FA ? étape TOTP intermédiaire ? cf. Phase 2)${RESET}" >&2
  fi
  echo "$token"
}

[[ -n "$BUYER_LOGIN"  && -z "$BUYER_JWT"  ]] && BUYER_JWT="$(login "$BUYER_LOGIN")"
[[ -n "$VENDOR_LOGIN" && -z "$VENDOR_JWT" ]] && VENDOR_JWT="$(login "$VENDOR_LOGIN")"

if [[ -z "$BUYER_JWT" ]]; then
  echo -e "${RED}[x] Aucun JWT buyer fourni/obtenu. Stop.${RESET}"; exit 1
fi

# ── Décodage du payload JWT (pour vérifier le claim de rôle réellement porté) ─
decode_claims() {  # decode_claims <jwt>
  local p; p=$(echo "$1" | cut -d. -f2)
  # base64url -> base64 + padding
  p="${p//-/+}"; p="${p//_//}"
  case $(( ${#p} % 4 )) in 2) p="$p==";; 3) p="$p=";; esac
  echo "$p" | base64 -d 2>/dev/null || true
}
echo -e "${CYAN}[*] Claims JWT buyer :${RESET}"
decode_claims "$BUYER_JWT" | tee "$OUT_DIR/buyer-claims.json"; echo
if [[ -n "$VENDOR_JWT" ]]; then
  echo -e "${CYAN}[*] Claims JWT vendor :${RESET}"
  decode_claims "$VENDOR_JWT" | tee "$OUT_DIR/vendor-claims.json"; echo
fi

# ── Cœur du rejeu ────────────────────────────────────────────────────────────
# test <label-role> <jwt> <methode> <endpoint> <role-attendu>
test_ep() {
  local label="$1" jwt="$2" method="$3" ep="$4" expected="$5"
  local url="$BASE$ep"
  local safe; safe=$(echo "${label}_${method}_${ep}" | tr -c 'A-Za-z0-9' '_')
  local code
  # -o fichier réponse, -w code ; GET par défaut, corps vide pour POST (on teste
  # juste l'autorisation, pas la logique métier)
  code=$(curl -s -o "$OUT_DIR/responses/$safe.txt" -w '%{http_code}' \
    -X "$method" "$url" \
    -H "Authorization: Bearer $jwt" \
    ${method:+$([[ "$method" == "POST" ]] && echo '-H Content-Type:application/json -d {}')} ) || code="ERR"

  local verdict color
  case "$code" in
    401|403) verdict="OK-bloque"; color="$GREEN";;
    200|201) verdict="BFLA/ELEVATION"; color="$RED";;
    404)     verdict="404-a-verifier"; color="$YELLOW";;
    500)     verdict="500-erreur-serveur"; color="$YELLOW";;
    *)       verdict="code-$code"; color="$YELLOW";;
  esac
  printf "  ${color}%-16s${RESET} %-4s %-45s [%s]\n" "$verdict" "$method" "$ep" "$code"
  echo "$label,$method,$ep,$expected,$code,$verdict" >> "$RESULTS"
}

# ── Table d'endpoints (issue du livrable Phase 1) ─────────────────────────────
# Format : "METHODE|/endpoint|role-attendu"
VENDOR_ENDPOINTS=(
  "GET|/api/vendor/alerts|vendor"
  "GET|/api/vendor/announcements|vendor"
  "GET|/api/vendor/campaigns|vendor"
  "GET|/api/vendor/campaigns/recipients|vendor"
  "GET|/api/vendor/campaigns/recipients/count|vendor"
  "GET|/api/vendor/email-settings|vendor"
  "GET|/api/vendor/orders|vendor"
  "GET|/api/vendor/products|vendor"
  "GET|/api/vendor/promo-codes|vendor"
  "GET|/api/vendor/reports/sales|vendor"
  "GET|/api/vendor/seo|vendor"
  "GET|/api/vendor/settings/bank|vendor"
  "GET|/api/vendor/settings/vat|vendor"
  "GET|/api/vendor/shipping-fee-tiers|vendor"
  "GET|/api/vendor/shop/theme|vendor"
)
ADMIN_ENDPOINTS=(
  "GET|/api/admin/accounts|admin"
  "GET|/api/admin/accounts/revoked|admin"
  "GET|/api/admin/audit-logs|admin"
  "GET|/api/admin/carriers|admin"
  "GET|/api/admin/mail/config|admin"
  "GET|/api/admin/settings/maintenance|admin"
)

run_suite() {   # run_suite <label> <jwt> <array-name>
  local label="$1" jwt="$2"; shift 2
  local -n eps="$1"
  for entry in "${eps[@]}"; do
    IFS='|' read -r m e r <<< "$entry"
    test_ep "$label" "$jwt" "$m" "$e" "$r"
  done
}

echo -e "\n${BOLD}═══ BUYER JWT → endpoints VENDOR ═══${RESET}"
run_suite "buyer" "$BUYER_JWT" VENDOR_ENDPOINTS
echo -e "\n${BOLD}═══ BUYER JWT → endpoints ADMIN ═══${RESET}"
run_suite "buyer" "$BUYER_JWT" ADMIN_ENDPOINTS

if [[ -n "$VENDOR_JWT" ]]; then
  echo -e "\n${BOLD}═══ VENDOR JWT → endpoints ADMIN (escalade) ═══${RESET}"
  run_suite "vendor" "$VENDOR_JWT" ADMIN_ENDPOINTS
fi

# ── Synthèse ─────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}═══ Synthèse ═══${RESET}"
hits=$(grep -c 'BFLA/ELEVATION' "$RESULTS" || true)
if [[ "$hits" -gt 0 ]]; then
  echo -e "${RED}[!] $hits accès NON autorisés (200/201) — BFLA/élévation :${RESET}"
  grep 'BFLA/ELEVATION' "$RESULTS" | awk -F, '{printf "    %-6s %-5s %s\n",$1,$2,$3}'
else
  echo -e "${GREEN}[✓] Aucun 200/201 inattendu : le backend semble valider le rôle.${RESET}"
fi
echo -e "\nCSV complet : ${CYAN}$RESULTS${RESET}"
echo -e "Corps des réponses : ${CYAN}$OUT_DIR/responses/${RESET}"
echo -e "${YELLOW}Rappel : un 404 sur un endpoint {id} peut masquer un accès autorisé —"
echo -e "       ajoute les UUID capturés (Phase 1) pour lever le doute.${RESET}"
