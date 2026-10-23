# 08 - Génération de wordlists ciblées & brute-force d'une API

> ⚠️ **Cadre légal** : ces techniques ne s'appliquent qu'à des cibles pour lesquelles vous disposez d'une autorisation écrite (règles d'engagement, périmètre bug bounty, lab personnel). Un brute-force non autorisé est une infraction (art. 323-1 et suivants du Code pénal en France). Privilégiez toujours des comptes de test dédiés.

L'efficacité d'un brute-force ne vient pas du volume (rockyou = 14 M d'entrées) mais de la **pertinence**. Une wordlist de quelques milliers de mots construite à partir du contexte de la cible (nom de l'entreprise, produits, dates, jargon métier) bat souvent une liste générique. Cette fiche couvre deux temps : **construire** la liste, puis la **tester** dans Burp Intruder contre un endpoint d'API.

---

## Partie 1 — Générer une liste de mots de passe à partir de mots-clés

### 1.1 Rassembler les mots-clés de base

Le générateur de §1.7 travaille à partir de **trois listes séparées**. Collectez le vocabulaire propre à la cible dedans :

- **`words.txt`** — les mots (un par ligne) : nom de l'entreprise, marques, produits, noms de code, ville, prénoms/noms (OSINT LinkedIn), jargon métier, slogans. Les expressions multi-mots (`anonymous shop`) sont acceptées : leurs abréviations/variantes sont dérivées automatiquement (§1.1bis).
- **`numbers.txt`** — les nombres pertinents (années, code postal, numéros récurrents) : `2025`, `2026`, `44`, etc. Ajoutés en **préfixe ou suffixe** (`cours2026` et `2026cours`).
- **`specials.txt`** — les caractères spéciaux à tester (`!`, `@`, `.`, `-`…).

Exemple pour l'app d'entraînement du kit, `anonymous_eshop` (marketplace multi-rôles — cf [anonymous-shop/tp-pentest-anonymous-shop.md](../anonymous-shop/tp-pentest-anonymous-shop.md)) :

```bash
# words.txt
anonymous shop
anonymous
eshop
shop
marketplace
vendor
buyer
admin
stripe
# numbers.txt
2024
2025
2026
# specials.txt
!
@
.
```

### 1.1bis Dériver les abréviations et variantes

Les utilisateurs internes écrivent rarement le nom complet de l'entreprise dans leur mot de passe : ils abrègent (`anonymous shop` → `anshop`, `as`), tronquent (`anonymous` → `anon`), changent les séparateurs ou substituent des synonymes. `cewl` ne capte que ce qui est écrit **tel quel** sur le site ; ces variantes-là, il faut les **générer**. C'est souvent ce qui fait la différence entre une liste qui trouve et une liste qui passe à côté.

Les transformations à produire systématiquement, à partir de chaque mot/expression de base :

| Transformation | `anonymous shop` → |
|---|---|
| Acronyme (initiales) | `as`, `ansh` |
| Troncature | `anon`, `anonym`, `shp` |
| Concaténation | `anonymousshop`, `anonshop` |
| Séparateurs | `anonymous-shop`, `anonymous_shop`, `anonymous.shop` |
| Casse | `AnonShop`, `ANON`, `AnonymousShop` |
| Synonymes de domaine | `shop` → `store`, `eshop`, `boutique`, `market` |

Ces dérivations sont **générées automatiquement** par [`tools/genpass.sh`](../tools/genpass.sh) (cf §1.7) à partir des mots de `words.txt` : troncatures, concaténations (collé / tiret / point), et surtout **acronymes de toute combinaison de mots** (premières lettres → `as`, `am`, `ae`…). Tu n'as donc qu'à lister les **mots simples**, un par ligne :

```
anonymous
shop
marketplace
eshop
```

Ajoutez aussi à la main les synonymes métier que le script ne devine pas (`shop`→`store`/`boutique`/`market`). Toutes ces variantes passent ensuite dans les mutations (casse × nombres × spéciaux) de §1.7 — c'est là qu'elles prennent toute leur valeur.

### 1.2 `cewl` — moissonner les mots du site cible

`cewl` explore un site web et extrait les mots les plus fréquents : idéal pour récupérer le vocabulaire réel de la cible.

```bash
# Mots d'au moins 5 lettres, profondeur 2, écrits dans un fichier
cewl -d 2 -m 5 -w cewl-out.txt http://localhost:5173

# Avec les adresses e-mail et métadonnées d'auteurs de documents
cewl -d 2 -m 5 --with-numbers -e --meta -w cewl-out.txt http://localhost:5173
```

Fusionnez ensuite la sortie avec votre liste de mots manuelle :

```bash
cat words.txt cewl-out.txt | sort -u > words-merged.txt   # puis renommer en words.txt
```

> `cewl` alimente le pool de **mots** : ajoute sa sortie à `words.txt` avant de lancer le générateur de §1.7. Les sections 1.3–1.6 détaillent les étapes (cupp, règles hashcat/John, filtrage) si tu veux affiner à la main ; sinon le générateur [`tools/genpass.sh`](../tools/genpass.sh) (§1.7) fait tout à partir des 3 listes.

### 1.3 `cupp` — générer à partir d'un profil (OSINT d'une personne)

`cupp -i` pose des questions (prénom, surnom, date de naissance, partenaire, animal…) et génère des combinaisons probables. Utile quand la cible est une personne précise.

```bash
cupp -i
# répondre aux questions → produit <nom>.txt
```

### 1.4 Appliquer des règles de mutation (le cœur du sujet)

Les utilisateurs transforment leurs mots de façon prévisible : majuscule initiale, chiffres en suffixe, « leet speak » (`a→@`, `e→3`, `s→$`), année ou `!` à la fin.

`tools/genpass.sh` (§1.7) applique déjà casse (min/MAJ/Capitalize) + nombres (préfixe/suffixe) + spéciaux. Pour aller **plus loin ou plus agressif** (leet systématique, règles complexes), utilisez les **règles** de `hashcat` ou `John the Ripper` sur une base de mots :

**Avec `hashcat` (mode stdout, sans cracker)** — les règles `best64.rule` couvrent les mutations les plus courantes :

```bash
hashcat --stdout base.txt -r /usr/share/hashcat/rules/best64.rule > mutated.txt
# règles plus agressives :
hashcat --stdout base.txt -r /usr/share/hashcat/rules/rockyou-30000.rule > mutated.txt
```

**Avec `John the Ripper`** :

```bash
john --wordlist=base.txt --rules=Jumbo --stdout > mutated.txt
```

**Règle maison** — pour coller à une politique de mot de passe précise (ex. 1 majuscule + chiffres + symbole), créez un fichier `.rule` hashcat. Exemple minimal :

```
# ma-regle.rule
c $2 $0 $2 $5          # Capitalize + "2025"
c $2 $0 $2 $6          # Capitalize + "2026"
sa@ se3 so0 c $!       # leet + Capitalize + "!"
```

```bash
hashcat --stdout base.txt -r ma-regle.rule > mutated.txt
```

### 1.5 Combiner / respecter une politique de complexité

- **`crunch`** génère par motif (utile pour un format connu, ex. 4 lettres + 4 chiffres) :
  ```bash
  crunch 8 8 -t ,%%%%@@@ -o crunch.txt    # 1 maj, 4 chiffres, 3 minuscules
  ```
- **Combiner deux listes** (mot + suffixe) avec hashcat en mode combinator :
  ```bash
  hashcat --stdout -a 1 mots.txt suffixes.txt > combined.txt
  ```

### 1.6 Nettoyer et filtrer selon la politique de la cible

Si la cible impose « ≥ 8 caractères, au moins 1 chiffre », autant retirer tout ce qui ne passera jamais — ça réduit le bruit et la durée de l'attaque :

```bash
# longueur >= 8 et contenant au moins un chiffre, dédoublonné
awk 'length>=8' mutated.txt | grep -E '[0-9]' | sort -u > final.txt
wc -l final.txt
```

Vous disposez maintenant d'une wordlist `final.txt` ciblée, prête pour Burp.

> 💡 Wordlists de référence à garder sous la main : le dépôt **SecLists** (`/usr/share/seclists/Passwords/`) pour compléter votre liste custom avec des classiques (`Passwords/Common-Credentials/10-million-password-list-top-1000.txt`).

### 1.7 Générateur à 3 listes (`tools/genpass.sh`)

Pour un contrôle fin, [`tools/genpass.sh`](../tools/genpass.sh) combine **trois listes que tu maintiens** et laisse régler l'ampleur :

- `words.txt` — les **mots** (un par ligne, mots entiers). Les expressions multi-mots sont acceptées (éclatées en mots individuels).
- `numbers.txt` — les **nombres** (ajoutés en **préfixe ou suffixe** — `cours2026` *et* `2026cours` — jamais au milieu d'un mot)
- `specials.txt` — les **caractères spéciaux**

À partir de `words.txt`, le script fabrique automatiquement : les **mots**, leurs **troncatures** (4–5 premières lettres), les **acronymes** (premières lettres de toute combinaison de mots → `jp`, `sjp`, `cjp`, `csjp`…), et les **concaténations** de 1 à `MAXWORDS` mots (collé / tiret / point). Le tout est ensuite décliné en `casse(min/MAJ/Cap) × 0..NUMMAX nombres × 0..SPECMAX spéciaux`, filtré sur la longueur.

Les 3 listes sont lues dans le **dossier de données** : 1er argument, sinon dossier courant.

```bash
# depuis le dossier des listes
cd wordlists/ma-cible
MAXWORDS=3 NUMMAX=2 SPECMAX=1 COUNT=1 bash ../../tools/genpass.sh   # estimer (n'écrit rien)
MAXWORDS=3 NUMMAX=2 SPECMAX=1 bash ../../tools/genpass.sh           # générer -> final.txt

# ou depuis la racine du repo, en passant le dossier en argument
MAXWORDS=3 NUMMAX=2 SPECMAX=1 bash tools/genpass.sh wordlists/ma-cible
```

| Variable | Rôle | Défaut |
|---|---|---|
| `MAXWORDS` | nb max de mots collés (1 à 3) | 1 |
| `NUMMAX` | nb max de nombres ajoutés (0–2) | 1 |
| `SPECMAX` | nb max de spéciaux ajoutés (0–2) | 1 |
| `MINLEN` | longueur minimale conservée | 8 |
| `MAXLEN` | longueur maximale conservée | 18 |
| `COUNT=1` | affiche l'estimation sans générer | — |
| `OUT=` | nom du fichier de sortie | `final.txt` |

> ⚠️ **Les dimensions se multiplient.** `MAXWORDS=1` reste raisonnable ; `MAXWORDS=2` puis `3` font exploser le nombre de combinaisons (×nombre de mots à chaque cran), surtout avec un gros `words.txt`. **Toujours lancer `COUNT=1` d'abord** pour voir la taille estimée. Au-delà de ~10⁶ lignes, c'est du **crackage hors-ligne**, pas du brute-force en ligne (voir §2.5).

---

## Partie 2 — Tester la liste dans Burp sur une requête d'API (brute-force)

Contexte (toujours `anonymous_eshop`) : le backend Spring Boot (`localhost:8080`) expose `POST /api/auth/login` qui attend un JSON `{"email": "...", "password": "..."}` et renvoie `200` + un JWT si le couple est valide, `401` sinon. Tests **en local uniquement**, sur des comptes de test — jamais contre le domaine de production.

### 2.1 Capturer une requête de référence

1. Configurer le proxy (voir fiche `03-proxy-interception.md`) et laisser passer un essai de connexion depuis l'application (ou depuis un client comme Postman proxifié sur `127.0.0.1:8080`).
2. Dans **Proxy > HTTP history**, retrouver le `POST /api/auth/login`.
3. Clic droit > **Send to Intruder** (`Ctrl+I`).

Exemple de requête :

```http
POST /api/auth/login HTTP/1.1
Host: localhost:8080
Content-Type: application/json
Accept: application/json

{"email":"buyer@anonymous.shop","password":"test"}
```

### 2.2 Marquer la position du payload

1. Onglet **Positions** de l'Intruder.
2. Cliquer **Clear §** pour retirer les positions auto.
3. Sélectionner uniquement la valeur de `password` et cliquer **Add §** :
   ```json
   {"email":"buyer@anonymous.shop","password":"§test§"}
   ```
4. Mode d'attaque : **Sniper** (un seul jeu de payloads sur une position).

> Si vous testez aussi plusieurs comptes, marquez `email` **et** `password` et passez en **Cluster bomb** (toutes les combinaisons) ou **Pitchfork** (couples alignés index par index). Voir fiche `05-intruder.md`.

### 2.3 Charger la wordlist

1. Onglet **Payloads**.
2. Payload type : **Simple list**.
3. **Load…** → sélectionner `final.txt` généré en Partie 1.
4. **Payload processing** (optionnel) : si l'API attend le mot de passe encodé/haché côté client, ajouter une règle (ex. **Add prefix/suffix**, **Hash > SHA-256**, **URL-encode**) pour reproduire ce que fait le front.
5. **Payload encoding** : pour du JSON, décocher l'URL-encoding automatique des caractères (`=`, `&`, etc.) sinon vous corrompez le corps.

### 2.4 Distinguer succès et échec

C'est l'étape clé : il faut un **critère observable** qui sépare la bonne réponse du reste.

- **Code de statut** : trier la colonne **Status** → repérer un `200` isolé parmi des `401`.
- **Longueur** : trier la colonne **Length** → la réponse contenant un token a une taille différente.
- **Grep - Match** : onglet **Settings > Grep - Match**, ajouter une chaîne présente seulement en cas de succès (`access_token`, `"role":`) ou d'échec (`Invalid credentials`). Une colonne cochée/décochée apparaît alors dans les résultats.

### 2.5 Gérer le rate limiting et les protections

Les API réelles se défendent. À anticiper :

| Protection | Symptôme | Contournement (si dans le périmètre) |
|---|---|---|
| Compteur brute-force (Redis) | blocage après N échecs | `anonymous_eshop` compte les échecs dans Redis : tester s'il verrouille par **compte** ou par **IP**, et tenter de le contourner en faisant varier l'en-tête `X-Forwarded-For` à chaque requête (payload **Pitchfork** : mot de passe + IP) — cf TP phase 2.4 |
| Rate limiting | `429 Too Many Requests` après N essais | **Resource pool** : réduire le nombre de threads et ajouter un délai entre requêtes (Settings > Resource pool, ou "throttle" en Pro) |
| Verrouillage de compte | `423`/message de lock après X échecs | Cibler **un mot de passe sur plusieurs comptes** (password spraying) plutôt que l'inverse |
| Token anti-CSRF / nonce | `403` ou valeur unique par requête | Payload type **Recursive grep** pour extraire le token de la réponse précédente |

En **Community Edition**, l'Intruder est volontairement ralenti (throttling) : suffisant pour un lab, lent sur une vraie liste. Pour un vrai engagement, utiliser Burp Pro ou un outil dédié comme `ffuf` :

```bash
ffuf -u http://localhost:8080/api/auth/login \
  -X POST -H "Content-Type: application/json" \
  -d '{"email":"buyer@anonymous.shop","password":"FUZZ"}' \
  -w final.txt -mc 200 -t 10 -p 0.2
```

### 2.6 Validation du TP

- La wordlist `final.txt` contient des mutations crédibles des mots-clés de la cible.
- L'attaque Intruder isole **une** réponse divergente (status/length/grep) correspondant au mot de passe valide.
- Vous savez expliquer, dans le rapport, pourquoi cette entrée se distingue des autres (ex. `200` + présence de `access_token`).

> 💡 Dans le livrable client, documentez la **remédiation** : politique de mots de passe robuste, limitation du nombre de tentatives (rate limiting + lockout progressif), MFA, et détection côté SOC des pics d'échecs d'authentification.
