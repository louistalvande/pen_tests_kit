#!/usr/bin/env bash
# build-wordlist.sh — pipeline complet de génération de wordlist ciblée
# keywords.txt (+ cewl) -> abréviations -> mutations -> filtrage -> final.txt
# Voir burp/08-wordlists-brute-force-api.md (Partie 1)
#
# Usage :
#   ./build-wordlist.sh https://cible.example.com      # avec moisson cewl
#   ./build-wordlist.sh                                # keywords.txt seul
#
# Pré-requis : keywords.txt dans le dossier courant ; cewl, hashcat installés.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULE="${RULE:-/usr/share/hashcat/rules/best64.rule}"   # surchargeable : RULE=tools/mutations.rule
URL="${1:-}"

[[ -f keywords.txt ]] || { echo "keywords.txt manquant dans $(pwd)"; exit 1; }

# 1) moisson du site (optionnelle)
if [[ -n "$URL" ]]; then
  cewl -d 2 -m 5 --with-numbers -w cewl-out.txt "$URL" || true
else
  : > cewl-out.txt
fi

# 2) abréviations/variantes des expressions multi-mots (keywords + cewl)
: > cewl-variants.txt
grep -h ' ' keywords.txt cewl-out.txt 2>/dev/null | while read -r line; do
  "$HERE/variants.sh" "$line" || true
done >> cewl-variants.txt
# repli mono-mot : troncatures + Capitalize
while read -r wrd; do
  [[ -n "$wrd" ]] || continue
  echo "${wrd:0:4}"; echo "${wrd:0:5}"; echo "${wrd^}"
done < cewl-out.txt >> cewl-variants.txt

# 3) base dédoublonnée
cat keywords.txt cewl-out.txt cewl-variants.txt | sort -u > base.txt
echo "[*] base.txt : $(wc -l < base.txt) entrées"

# 4) mutations
hashcat --stdout base.txt -r "$RULE" > mutated.txt
echo "[*] mutated.txt : $(wc -l < mutated.txt) entrées (règle : $RULE)"

# 5) filtrage politique de complexité (>= 8 car. + au moins un chiffre)
awk 'length>=8' mutated.txt | grep -E '[0-9]' | sort -u > final.txt
echo "[*] final.txt : $(wc -l < final.txt) entrées -> prêt pour Burp"
