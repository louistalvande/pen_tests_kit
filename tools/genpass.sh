#!/usr/bin/env bash
# genpass.sh — générateur de mots de passe à partir de 3 listes
#   words.txt     : tokens-mots (se combinent entre eux)
#   numbers.txt   : tokens-nombres (ajoutés en préfixe ou suffixe, pas au milieu d'un mot)
#   specials.txt  : caractères spéciaux
#
# Combine, pour chaque mot (ou paire de mots) : casse + 0..NUMMAX nombres + 0..SPECMAX spéciaux.
# Réglages (variables d'env) :
#   MAXWORDS=1|2   nb max de mots-tokens collés          (défaut 1)
#   NUMMAX=0..3    nb max de nombres ajoutés             (défaut 1)
#   SPECMAX=0|1|2  nb max de spéciaux ajoutés            (défaut 1)
#   MINLEN=N       longueur minimale conservée           (défaut 8)
#   MAXLEN=N       longueur maximale conservée           (défaut 18)
#   COUNT=1        affiche seulement l'ESTIMATION, ne génère pas
#   OUT=fichier    fichier de sortie                     (défaut final.txt)
#
# Les 3 listes sont lues dans le DOSSIER DE DONNÉES : 1er argument, sinon dossier courant.
# Exemples :
#   cd wordlists/ma-cible && MAXWORDS=2 bash ../../tools/genpass.sh
#   MAXWORDS=2 bash tools/genpass.sh wordlists/ma-cible      # depuis la racine du repo
set -euo pipefail

MAXWORDS=${MAXWORDS:-1}; NUMMAX=${NUMMAX:-1}; SPECMAX=${SPECMAX:-1}
MINLEN=${MINLEN:-8}; MAXLEN=${MAXLEN:-18}; OUT=${OUT:-final.txt}; COUNT=${COUNT:-0}

DATADIR="${1:-.}"
cd "$DATADIR" 2>/dev/null || { echo "ERREUR: dossier introuvable: $DATADIR"; exit 1; }

for f in words.txt numbers.txt specials.txt; do
  [[ -f $f ]] || { echo "ERREUR: $f manquant dans $(pwd)"; exit 1; }
done

# 1) base de mots : mots simples + troncatures + ACRONYMES (premières lettres de
#    combinaisons de mots : jp, sjp, csjp, cjp…) + concaténations de 1..MAXWORDS mots.
#    Les lignes multi-mots de words.txt sont éclatées en mots individuels.
awk -v MAXWORDS="$MAXWORDS" '
{ for(i=1;i<=NF;i++) G[++M]=$i }                 # séquence globale de mots
END{
  # mots simples + troncatures (4 et 5 premières lettres)
  # (pas de generation d acronymes : ajoute tes sigles voulus directement dans words.txt)
  for(i=1;i<=M;i++){ print G[i];
    if(length(G[i])>=5){ print substr(G[i],1,4); print substr(G[i],1,5) } }
  # concaténations ordonnées de mots DISTINCTS, longueur 2..MAXWORDS (+ séparateurs)
  if(MAXWORDS>=2) for(i=1;i<=M;i++) for(j=1;j<=M;j++){ if(i==j) continue;
    print G[i] G[j]; print G[i]"-"G[j]; print G[i]"."G[j];
    if(MAXWORDS>=3) for(k=1;k<=M;k++){ if(k==i||k==j) continue;
      print G[i] G[j] G[k]; print G[i]"-"G[j]"-"G[k]; print G[i]"."G[j]"."G[k]; }
  }
}' words.txt | { grep -v ' ' || true; } | sed '/^[[:space:]]*$/d' | sort -u > .base.txt
NB=$(wc -l < .base.txt)

# 2bis) base "nombre ENTRE les mots" (cours2026jean) — traitée ensuite SANS nombre ajouté,
#       pour ne pas recréer de doublon de nombre. Seulement si MAXWORDS>=2.
rm -f .base-mid.txt
if [[ "$MAXWORDS" -ge 2 ]]; then
  awk -v MAXWORDS="$MAXWORDS" '
  BEGIN{ while((getline x<"numbers.txt")>0) if(x ~ /^[0-9]+$/ && !(x in s)){ s[x]=1; NB[++bn]=x } }
  { for(i=1;i<=NF;i++) G[++M]=$i }
  END{
    for(i=1;i<=M;i++) for(j=1;j<=M;j++){ if(i==j) continue
      for(t=1;t<=bn;t++){ print G[i] NB[t] G[j]; print G[i]"-"NB[t]"-"G[j]; print G[i]"."NB[t]"."G[j] }
      if(MAXWORDS>=3) for(k=1;k<=M;k++){ if(k==i||k==j) continue
        for(t=1;t<=bn;t++){ print G[i] NB[t] G[j] G[k]; print G[i] G[j] NB[t] G[k] } }
    }
  }' words.txt | { grep -v ' ' || true; } | sed '/^[[:space:]]*$/d' | sort -u > .base-mid.txt
fi

# 3) génération (awk) : casse x (0..NUMMAX nombres) x (0..SPECMAX spéciaux), suffixe + préfixe-spécial
gen() {   # $1 = fichier base ; $2 = NUMMAX effectif pour cette passe
  awk -v NUMMAX="$2" -v SPECMAX="$SPECMAX" -v MINLEN="$MINLEN" -v MAXLEN="$MAXLEN" -v COUNT="$COUNT" '
  function emit(s,  L){ L=length(s); if(L>=MINLEN && L<=MAXLEN){ if(COUNT) c++; else print s } }
  # place le coeur avec nombres en prefixe/suffixe + 1 special insere a toute jointure
  function place(core, pre, suf,   SEG, m, z, t, g, k, p, q, core2){
    m=0
    if(pre!="") SEG[++m]=pre
    SEG[++m]=core
    if(suf!="") SEG[++m]=suf
    t=""; for(z=1;z<=m;z++) t=t SEG[z]; emit(t)
    if(SPECMAX>=1) for(g=0;g<=m;g++) for(k=1;k<=ns;k++){
      t=""
      for(z=1;z<=m;z++){ if(z-1==g) t=t SP[k]; t=t SEG[z] }
      if(g==m) t=t SP[k]
      emit(t)
    }
    if(SPECMAX>=2){ core2=""; for(z=1;z<=m;z++) core2=core2 SEG[z]
      for(p=1;p<=ns;p++) for(q=1;q<=ns;q++) emit(SP[p] core2 SP[q])
    }
  }
  BEGIN{
    while((getline x < "numbers.txt")>0)  if(x!="" && !(x in seenN)){ seenN[x]=1; NUM[++nn]=x }
    while((getline x < "specials.txt")>0) if(x!="") SP[++ns]=x
  }
  # Placement : [nombres prefixe] [coeur] [nombres suffixe] (total nombres <= NUMMAX) ;
  # le special est insere a n importe quelle jointure (debut, entre segments, fin).
  # Ex. couvert : 20262027-JP2 = pre 20262027, coeur JP, suf 2, special entre pre et coeur.
  {
    w=$0
    CF[1]=tolower(w); CF[2]=toupper(w); CF[3]=toupper(substr(w,1,1)) substr(w,2)
    for(ci=1;ci<=3;ci++){ core=CF[ci]
      place(core, "", "")                                   # aucun nombre
      if(NUMMAX>=1) for(i=1;i<=nn;i++){ place(core, NUM[i], ""); place(core, "", NUM[i]) }   # 1 nombre
      if(NUMMAX>=2) for(i=1;i<=nn;i++) for(j=1;j<=nn;j++){   # 2 nombres DISTINCTS (i!=j)
        if(i==j) continue
        place(core, "",            NUM[i] NUM[j])
        place(core, NUM[i],        NUM[j])
        place(core, NUM[i] NUM[j], "")
      }
      if(NUMMAX>=3) for(i=1;i<=nn;i++) for(j=1;j<=nn;j++) for(k=1;k<=nn;k++){   # 3 nombres DISTINCTS
        if(i==j||i==k||j==k) continue
        place(core, "",                   NUM[i] NUM[j] NUM[k])
        place(core, NUM[i],               NUM[j] NUM[k])
        place(core, NUM[i] NUM[j],        NUM[k])
        place(core, NUM[i] NUM[j] NUM[k], "")
      }
    }
  }
  END{ if(COUNT) printf "%d\n", c }
  ' "$1"
}

if [[ "$COUNT" == "1" ]]; then
  echo "base (mots) : $NB$([[ -f .base-mid.txt ]] && echo " | base nombre-entre-mots : $(wc -l < .base-mid.txt)")"
  n1=$(gen .base.txt "$NUMMAX")
  n2=0; [[ -f .base-mid.txt ]] && n2=$(gen .base-mid.txt 0)   # passe "entre les mots" : AUCUN nombre ajouté
  n=$((n1 + n2))
  printf "ESTIMATION (MAXWORDS=%s NUMMAX=%s SPECMAX=%s) : ~%d lignes, ~%d Mo\n" \
    "$MAXWORDS" "$NUMMAX" "$SPECMAX" "$n" "$((n*22/1000000))"
  rm -f .base.txt .base-mid.txt
else
  echo "[*] base : $NB mots | NUMMAX=$NUMMAX SPECMAX=$SPECMAX MAXWORDS=$MAXWORDS"
  { gen .base.txt "$NUMMAX"; [[ -f .base-mid.txt ]] && gen .base-mid.txt 0; } | sort -u > "$OUT"
  rm -f .base.txt .base-mid.txt
  echo "[*] $OUT : $(wc -l < "$OUT") mots de passe (${MINLEN}–${MAXLEN} car.)"
fi
