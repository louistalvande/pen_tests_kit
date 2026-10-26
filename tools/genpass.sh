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
    # combos de nombres AVEC leur taille : index 0 = "" (taille 0)
    NCMB[0]=""; NSZ[0]=0; nc=1
    if(NUMMAX>=1) for(i=1;i<=nn;i++){ NCMB[nc]=NUM[i]; NSZ[nc]=1; nc++ }
    if(NUMMAX>=2) for(i=1;i<=nn;i++) for(j=1;j<=nn;j++){ NCMB[nc]=NUM[i] NUM[j]; NSZ[nc]=2; nc++ }
    if(NUMMAX>=3) for(i=1;i<=nn;i++) for(j=1;j<=nn;j++) for(k=1;k<=nn;k++){ NCMB[nc]=NUM[i] NUM[j] NUM[k]; NSZ[nc]=3; nc++ }
  }
  # Placement : [nombres prefixe] [coeur] [nombres suffixe] (total nombres <= NUMMAX) ;
  # le special est insere a n importe quelle jointure (debut, entre segments, fin).
  # Ex. couvert : 20262027-JP2 = pre 20262027, coeur JP, suf 2, special entre pre et coeur.
  {
    w=$0
    CF[1]=tolower(w); CF[2]=toupper(w); CF[3]=toupper(substr(w,1,1)) substr(w,2)
    for(ci=1;ci<=3;ci++){ core=CF[ci]
      for(a=0;a<nc;a++){ pre=NCMB[a]
        for(bb=0;bb<nc;bb++){ suf=NCMB[bb]
          if(NSZ[a]+NSZ[bb] > NUMMAX) continue
          m=0
          if(pre!="") SEG[++m]=pre
          SEG[++m]=core
          if(suf!="") SEG[++m]=suf
          # sans spécial
          t=""; for(z=1;z<=m;z++) t=t SEG[z]; emit(t)
          # un spécial inséré à une jointure (g=0 début .. g=m fin)
          if(SPECMAX>=1) for(g=0;g<=m;g++) for(k=1;k<=ns;k++){
            t=""
            for(z=1;z<=m;z++){ if(z-1==g) t=t SP[k]; t=t SEG[z] }
            if(g==m) t=t SP[k]
            emit(t)
          }
          # deux spéciaux : un au tout début ET un à la toute fin (besoin SPECMAX>=2)
          if(SPECMAX>=2){ core2=""; for(z=1;z<=m;z++) core2=core2 SEG[z]
            for(p=1;p<=ns;p++) for(q=1;q<=ns;q++) emit(SP[p] core2 SP[q])
          }
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
