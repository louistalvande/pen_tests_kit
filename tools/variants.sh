#!/usr/bin/env bash
# variants.sh — dérive abréviations et variantes d'une expression
# Usage : ./variants.sh "anonymous shop"  >> keywords.txt
# Voir burp/08-wordlists-brute-force-api.md §1.1bis
set -euo pipefail

phrase="${1:?usage: variants.sh \"expression\"}"
read -ra w <<< "$phrase"                           # découpe en mots

# acronyme (initiales de chaque mot) : anonymous shop -> ansh... en fait "as"
printf '%s' "${w[0]:0:1}"; for x in "${w[@]:1}"; do printf '%s' "${x:0:1}"; done; echo

# concaténation + variantes de séparateurs
( IFS= ; echo "${w[*]}" )                           # anonymousshop
( IFS=- ; echo "${w[*]}" )                          # anonymous-shop
( IFS=_ ; echo "${w[*]}" )                          # anonymous_shop
( IFS=. ; echo "${w[*]}" )                          # anonymous.shop

# troncatures (4 et 5 premières lettres de chaque mot)
for x in "${w[@]}"; do echo "${x:0:4}"; echo "${x:0:5}"; done

# chaque mot seul + CamelCase global
cap=""; for x in "${w[@]}"; do echo "$x"; cap+="${x^}"; done; echo "$cap"
