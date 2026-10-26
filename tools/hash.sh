#!/usr/bin/env bash
# hash.sh — génère les hash d'un texte (ou de chaque ligne d'une wordlist)
#
# Usage :
#   tools/hash.sh "texte"                 # tous les algos du texte
#   tools/hash.sh -a sha256 "texte"       # un seul algo
#   echo "texte" | tools/hash.sh          # depuis stdin
#   tools/hash.sh -a md5 -l words.txt     # hache chaque ligne -> "hash:mot"
#
# Algos : md5 sha1 sha256 sha512 ntlm  (ntlm nécessite openssl avec md4)
set -euo pipefail

ALGO="all"; LIST=""
while getopts ":a:l:h" opt; do
  case "$opt" in
    a) ALGO="$OPTARG" ;;
    l) LIST="$OPTARG" ;;
    h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "option invalide (-h pour l'aide)"; exit 1 ;;
  esac
done
shift $((OPTIND-1))

# --- hache UNE chaîne (sans newline final) dans un algo donné ---
hash_one() {
  local algo="$1" s="$2"
  case "$algo" in
    md5)    printf '%s' "$s" | md5sum    | cut -d' ' -f1 ;;
    sha1)   printf '%s' "$s" | sha1sum   | cut -d' ' -f1 ;;
    sha256) printf '%s' "$s" | sha256sum | cut -d' ' -f1 ;;
    sha512) printf '%s' "$s" | sha512sum | cut -d' ' -f1 ;;
    ntlm)   printf '%s' "$s" | iconv -f UTF-8 -t UTF-16LE \
              | openssl dgst -md4 2>/dev/null | awk '{print $NF}' ;;
    *) echo "algo inconnu: $algo (md5|sha1|sha256|sha512|ntlm|all)" >&2; return 2 ;;
  esac
}

ALGOS_ALL="md5 sha1 sha256 sha512 ntlm"

emit() {   # $1 = texte
  local s="$1" a h
  if [[ "$ALGO" == "all" ]]; then
    for a in $ALGOS_ALL; do
      h="$(hash_one "$a" "$s" 2>/dev/null || true)"
      if [[ -n "$h" ]]; then printf '%-7s %s\n' "$a" "$h"; fi
    done
  else
    hash_one "$ALGO" "$s" || { echo "(échec $ALGO — algo indisponible ?)" >&2; return 0; }
  fi
  return 0
}

# --- mode wordlist : une ligne -> hash:mot ---
if [[ -n "$LIST" ]]; then
  [[ -f "$LIST" ]] || { echo "fichier introuvable: $LIST" >&2; exit 1; }
  [[ "$ALGO" == "all" ]] && ALGO="sha256"   # en mode liste, un seul algo (défaut sha256)
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s:%s\n' "$(hash_one "$ALGO" "$line")" "$line"
  done < "$LIST"
  exit 0
fi

# --- texte depuis argument, sinon stdin ---
if [[ $# -ge 1 ]]; then
  emit "$*"
else
  # stdin : chaque ligne traitée séparément
  while IFS= read -r line; do emit "$line"; done
fi
