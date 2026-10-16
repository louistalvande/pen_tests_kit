# 08 - Génération de wordlists ciblées & brute-force d'une API

> ⚠️ **Cadre légal** : ces techniques ne s'appliquent qu'à des cibles pour lesquelles vous disposez d'une autorisation écrite (règles d'engagement, périmètre bug bounty, lab personnel). Un brute-force non autorisé est une infraction (art. 323-1 et suivants du Code pénal en France). Privilégiez toujours des comptes de test dédiés.

L'efficacité d'un brute-force ne vient pas du volume (rockyou = 14 M d'entrées) mais de la **pertinence**. Une wordlist de quelques milliers de mots construite à partir du contexte de la cible (nom de l'entreprise, produits, dates, jargon métier) bat souvent une liste générique. Cette fiche couvre deux temps : **construire** la liste, puis la **tester** dans Burp Intruder contre un endpoint d'API.

---

## Partie 1 — Générer une liste de mots de passe à partir de mots-clés

### 1.1 Rassembler les mots-clés de base

Collectez le vocabulaire propre à la cible dans un fichier `keywords.txt` (un mot par ligne) :

- nom de l'entreprise, marques, produits, noms de code
- ville, pays, année de création
- prénoms/noms des cibles (OSINT LinkedIn), animaux de compagnie, équipes sportives
- jargon métier, slogans
- saisons et années courantes (`Automne2025`, `2026`)

```
anonymshop
anonymous
eshop
paris
tournesol
admin
2025
2026
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

Script réutilisable [`tools/variants.sh`](../tools/variants.sh) (prend une expression en argument, sort toutes les variantes) :

```bash
chmod +x tools/variants.sh
tools/variants.sh "anonymous shop" | sort -u >> keywords.txt
```

Ajoutez aussi à la main les synonymes métier que le script ne devine pas (`shop`→`store`/`boutique`). Ces variantes rejoignent `keywords.txt`, donc elles passeront ensuite dans `cewl` (fusion) puis dans les **règles de mutation** de §1.4 (`Anshop2025!`, `Anon@2026`, etc.) — c'est là qu'elles prennent toute leur valeur.

### 1.2 `cewl` — moissonner les mots du site cible

`cewl` explore un site web et extrait les mots les plus fréquents : idéal pour récupérer le vocabulaire réel de la cible.

```bash
# Mots d'au moins 5 lettres, profondeur 2, écrits dans un fichier
cewl -d 2 -m 5 -w cewl-out.txt https://cible.example.com

# Avec les adresses e-mail et métadonnées d'auteurs de documents
cewl -d 2 -m 5 --with-numbers -e --meta -w cewl-out.txt https://cible.example.com
```

Fusionnez ensuite avec vos mots-clés manuels :

```bash
cat keywords.txt cewl-out.txt | sort -u > base.txt
```

**Combiner cewl + dérivation d'abréviations (§1.1bis).** Les mots moissonnés par `cewl` (noms de produits, rubriques, slogans) méritent eux aussi d'être abrégés. Tout ce pipeline (moisson → abréviations → mutations → filtrage) est automatisé dans [`tools/build-wordlist.sh`](../tools/build-wordlist.sh) :

```bash
chmod +x tools/build-wordlist.sh
# keywords.txt doit exister dans le dossier courant
tools/build-wordlist.sh https://cible.example.com
# -> produit base.txt, mutated.txt et final.txt
```

> Ordre du pipeline (ce que fait le script) : `keywords.txt` (manuel) **+** `cewl-out.txt` (site) **+** `cewl-variants.txt` (abréviations des deux) → `base.txt` → règles de mutation §1.4 → filtrage §1.6 → `final.txt`. Pour n'exécuter qu'une étape, voir les sections suivantes.

### 1.3 `cupp` — générer à partir d'un profil (OSINT d'une personne)

`cupp -i` pose des questions (prénom, surnom, date de naissance, partenaire, animal…) et génère des combinaisons probables. Utile quand la cible est une personne précise.

```bash
cupp -i
# répondre aux questions → produit <nom>.txt
```

### 1.4 Appliquer des règles de mutation (le cœur du sujet)

Les utilisateurs transforment leurs mots de façon prévisible : majuscule initiale, chiffres en suffixe, « leet speak » (`a→@`, `e→3`, `s→$`), année ou `!` à la fin. On automatise ces mutations avec les **règles** de `hashcat` ou `John the Ripper`.

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

**Règle maison** — [`tools/mutations.rule`](../tools/mutations.rule) colle à une politique de mot de passe (ex. 1 majuscule + chiffres + symbole) ; adaptez-la à la cible :

```bash
hashcat --stdout base.txt -r tools/mutations.rule > mutated.txt
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

---

## Partie 2 — Tester la liste dans Burp sur une requête d'API (brute-force)

Contexte type : une API expose `POST /api/v1/auth/login` qui attend un JSON `{"email": "...", "password": "..."}` et renvoie `200` + un token si le couple est valide, `401` sinon.

### 2.1 Capturer une requête de référence

1. Configurer le proxy (voir fiche `03-proxy-interception.md`) et laisser passer un essai de connexion depuis l'application (ou depuis un client comme Postman proxifié sur `127.0.0.1:8080`).
2. Dans **Proxy > HTTP history**, retrouver le `POST /api/v1/auth/login`.
3. Clic droit > **Send to Intruder** (`Ctrl+I`).

Exemple de requête :

```http
POST /api/v1/auth/login HTTP/2
Host: api.cible.example.com
Content-Type: application/json
Accept: application/json

{"email":"victime@cible.example.com","password":"test"}
```

### 2.2 Marquer la position du payload

1. Onglet **Positions** de l'Intruder.
2. Cliquer **Clear §** pour retirer les positions auto.
3. Sélectionner uniquement la valeur de `password` et cliquer **Add §** :
   ```json
   {"email":"victime@cible.example.com","password":"§test§"}
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
| Rate limiting | `429 Too Many Requests` après N essais | **Resource pool** : réduire le nombre de threads et ajouter un délai entre requêtes (Settings > Resource pool, ou "throttle" en Pro) |
| Verrouillage de compte | `423`/message de lock après X échecs | Cibler **un mot de passe sur plusieurs comptes** (password spraying) plutôt que l'inverse |
| Token anti-CSRF / nonce | `403` ou valeur unique par requête | Payload type **Recursive grep** pour extraire le token de la réponse précédente |
| WAF / détection | Réponses qui changent de forme, captcha | Réduire la cadence, varier le `User-Agent`, rester dans les horaires autorisés |

En **Community Edition**, l'Intruder est volontairement ralenti (throttling) : suffisant pour un lab, lent sur une vraie liste. Pour un vrai engagement, utiliser Burp Pro ou un outil dédié comme `ffuf` :

```bash
ffuf -u https://api.cible.example.com/api/v1/auth/login \
  -X POST -H "Content-Type: application/json" \
  -d '{"email":"victime@cible.example.com","password":"FUZZ"}' \
  -w final.txt -mc 200 -t 10 -p 0.2
```

### 2.6 Validation du TP

- La wordlist `final.txt` contient des mutations crédibles des mots-clés de la cible.
- L'attaque Intruder isole **une** réponse divergente (status/length/grep) correspondant au mot de passe valide.
- Vous savez expliquer, dans le rapport, pourquoi cette entrée se distingue des autres (ex. `200` + présence de `access_token`).

> 💡 Dans le livrable client, documentez la **remédiation** : politique de mots de passe robuste, limitation du nombre de tentatives (rate limiting + lockout progressif), MFA, et détection côté SOC des pics d'échecs d'authentification.
