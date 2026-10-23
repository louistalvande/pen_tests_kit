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
BEGIN{ while((getline x < "numbers.txt")>0) if(x ~ /^[0-9]+$/) NB[++bn]=x }
{ for(i=1;i<=NF;i++) G[++M]=$i }                 # séquence globale de mots
END{
  # mots simples + troncatures (4 et 5 premières lettres)
  for(i=1;i<=M;i++){ print G[i];
    if(length(G[i])>=5){ print substr(G[i],1,4); print substr(G[i],1,5) } }
  # acronymes = premières lettres. Pour M<=14 : tous les sous-ensembles ordonnés
  # (donne jp, cjp, csjp…) ; sinon repli sur les runs de mots consécutifs.
  if(M<=14){
    lim=2^M
    for(mask=1; mask<lim; mask++){ a=""; cnt=0
      for(b=1;b<=M;b++) if(int(mask/2^(b-1))%2==1){ a=a substr(G[b],1,1); cnt++ }
      if(cnt>=2 && cnt<=6) print a
    }
  } else {
    cap=(M<8?M:8)
    for(len=2;len<=cap;len++) for(s=1;s+len-1<=M;s++){
      a=""; for(k=0;k<len;k++) a=a substr(G[s+k],1,1); print a }
  }
  # concaténations ordonnées de mots DISTINCTS, longueur 2..MAXWORDS (+ séparateurs)
  # + nombre INSÉRÉ ENTRE les mots (cours2026jean), les nombres venant de numbers.txt
  if(MAXWORDS>=2) for(i=1;i<=M;i++) for(j=1;j<=M;j++){ if(i==j) continue;
    print G[i] G[j]; print G[i]"-"G[j]; print G[i]"."G[j];
    for(t=1;t<=bn;t++){ print G[i] NB[t] G[j]; print G[i]"-"NB[t]"-"G[j] }
    if(MAXWORDS>=3) for(k=1;k<=M;k++){ if(k==i||k==j) continue;
      print G[i] G[j] G[k]; print G[i]"-"G[j]"-"G[k]; print G[i]"."G[j]"."G[k];
      for(t=1;t<=bn;t++){ print G[i] NB[t] G[j] G[k]; print G[i] G[j] NB[t] G[k] } }
  }
}' words.txt | { grep -v ' ' || true; } | sed '/^[[:space:]]*$/d' | sort -u > .base.txt
NB=$(wc -l < .base.txt)

# 3) génération (awk) : casse x (0..NUMMAX nombres) x (0..SPECMAX spéciaux), suffixe + préfixe-spécial
gen() {
  awk -v NUMMAX="$NUMMAX" -v SPECMAX="$SPECMAX" -v MINLEN="$MINLEN" -v MAXLEN="$MAXLEN" -v COUNT="$COUNT" '
  function emit(s,  L){ L=length(s); if(L>=MINLEN && L<=MAXLEN){ if(COUNT) c++; else print s } }
  BEGIN{
    while((getline x < "numbers.txt")>0) if(x!="") NUM[++nn]=x
    while((getline x < "specials.txt")>0) if(x!="") SP[++ns]=x
    # combos de nombres : index 0 = "" ; simples ; paires (NUMMAX>=2) ; triplets (NUMMAX>=3)
    NC[nc++]="";
    if(NUMMAX>=1) for(i=1;i<=nn;i++) NC[nc++]=NUM[i]
    if(NUMMAX>=2) for(i=1;i<=nn;i++) for(j=1;j<=nn;j++) NC[nc++]=NUM[i] NUM[j]
    if(NUMMAX>=3) for(i=1;i<=nn;i++) for(j=1;j<=nn;j++) for(k=1;k<=nn;k++) NC[nc++]=NUM[i] NUM[j] NUM[k]
    # combos de spéciaux
    SCn[sc++]="";
    if(SPECMAX>=1) for(i=1;i<=ns;i++) SCn[sc++]=SP[i]
    if(SPECMAX>=2){ for(i=1;i<=ns;i++) for(j=1;j<=ns;j++) SCn[sc++]=SP[i] SP[j] }
  }
  {
    w=$0
    CF[1]=tolower(w); CF[2]=toupper(w); CF[3]=toupper(substr(w,1,1)) substr(w,2)
    for(ci=1;ci<=3;ci++){ b=CF[ci]
      for(ni=0;ni<nc;ni++){ n=NC[ni]
        for(si=0;si<sc;si++){ s=SCn[si]
          emit(b n s)                     # mot + nombre + spécial   (cours2026!)
          if(s!="") emit(s b n)           # spécial + mot + nombre   (!cours2026)
          if(n!="") emit(n b s)           # nombre + mot + spécial   (2026cours!)
          if(n!="" && s!=""){
            emit(s n b)                   # spécial + nombre + mot   (!2026cours)
            emit(n s b)                   # nombre + spécial + mot   (2026!cours)
            emit(b s n)                   # mot + spécial + nombre   (cours!2026)
          }
        }
        # un spécial (éventuellement différent) à CHAQUE bout — besoin de SPECMAX>=2
        if(SPECMAX>=2) for(p=1;p<=ns;p++) for(q=1;q<=ns;q++){
          emit(SP[p] b SP[q])             # !cours@
          if(n!=""){
            emit(SP[p] b n SP[q])         # !cours2026@
            emit(SP[p] n b SP[q])         # !2026cours@
          }
        }
      }
      # un nombre de CHAQUE côté du mot — besoin de NUMMAX>=2
      if(NUMMAX>=2) for(p=1;p<=nn;p++) for(q=1;q<=nn;q++){
        emit(NUM[p] b NUM[q])             # 2026cours27
        if(SPECMAX>=1) for(k=1;k<=ns;k++){
          emit(NUM[p] b NUM[q] SP[k])     # 2026cours27!
          emit(SP[k] NUM[p] b NUM[q])     # !2026cours27
        }
      }
    }
  }
  END{ if(COUNT) printf "%d\n", c }
  ' .base.txt
}

if [[ "$COUNT" == "1" ]]; then
  echo "base (mots$([[ $MAXWORDS -ge 2 ]] && echo '+paires')) : $NB"
  n=$(gen)
  printf "ESTIMATION (MAXWORDS=%s NUMMAX=%s SPECMAX=%s) : ~%d lignes, ~%d Mo\n" \
    "$MAXWORDS" "$NUMMAX" "$SPECMAX" "$n" "$((n*22/1000000))"
  rm -f .base.txt
else
  echo "[*] base : $NB mots | NUMMAX=$NUMMAX SPECMAX=$SPECMAX MAXWORDS=$MAXWORDS"
  gen | sort -u > "$OUT"
  rm -f .base.txt
  echo "[*] $OUT : $(wc -l < "$OUT") mots de passe (${MINLEN}–${MAXLEN} car.)"
fi
