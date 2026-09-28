# 03 - Proxy et interception

Le module **Proxy** est le cœur de Burp : il intercepte chaque requête sortante du navigateur avant qu'elle n'atteigne le serveur, permettant de l'inspecter et de la modifier à la volée.

## Interception en direct

- **Proxy > Intercept > Intercept is on/off** : bascule le mode interception.
- Quand une requête est interceptée, elle est mise en pause ; on peut :
  - **Forward** : la laisser passer telle quelle
  - **Drop** : l'annuler
  - Modifier le corps/les en-têtes avant de la forwarder

## HTTP history

Chaque requête/réponse passée par le proxy (interceptée ou non) est loggée dans **Proxy > HTTP history**, avec la possibilité de filtrer par méthode, code de statut, extension de fichier, scope, etc.

### TP 3.1 — Modifier un paramètre de connexion à la volée

Objectif : comprendre comment intercepter et modifier une requête de login sur DVWA.

1. Démarrer DVWA, se connecter avec le compte par défaut (`admin` / `password`) une première fois pour repérer la requête normale.
2. Activer **Intercept is on**.
3. Sur la page de login DVWA, soumettre le formulaire avec un utilisateur quelconque.
4. Dans Burp, observer la requête `POST /login.php` interceptée : identifier les paramètres `username`, `password`, `Login`.
5. Modifier la valeur de `username` en `admin' -- ` (test d'injection SQL basique, DVWA en sécurité "low").
6. Cliquer **Forward** et observer la réponse.

**Validation** : sur le niveau de sécurité "low" de DVWA, cette manipulation contourne l'authentification — la réponse redirige vers la page authentifiée sans connaître le mot de passe.

### TP 3.2 — Repérer les paramètres cachés et cookies de session

1. Avec Intercept désactivé, naviguer sur Juice Shop, se connecter avec un compte de test.
2. Dans **Proxy > HTTP history**, filtrer sur `Content-Type: application/json` pour ne voir que les appels API.
3. Ouvrir une requête vers `/rest/user/login`, examiner la réponse : repérer le token JWT renvoyé (`authentication.token`).
4. Chercher dans les requêtes suivantes l'en-tête `Authorization: Bearer <token>` pour comprendre comment la session est maintenue.
5. Copier ce token dans **Decoder** (voir onglet Decoder) et décoder la partie payload en Base64 pour lire le contenu du JWT (email, rôle, iat, exp...).

**Validation** : vous devez pouvoir lire en clair le rôle de l'utilisateur (`"role":"customer"` par exemple) directement depuis le payload du JWT décodé, ce qui illustre pourquoi un JWT ne doit jamais contenir d'information sensible non protégée par la signature seule.

## Match and Replace

**Proxy > Options > Match and Replace** permet de réécrire automatiquement des motifs dans les requêtes/réponses (utile pour désactiver un CSP en response header, forcer un en-tête custom, etc.).

### TP 3.3 — Désactiver une Content-Security-Policy via Match and Replace

1. Ajouter une règle **Match and Replace** de type "Response header", motif `Content-Security-Policy:.*`, remplacement vide.
2. Recharger une page servant un CSP restrictif et vérifier dans les DevTools du navigateur que l'en-tête n'est plus présent.

**Validation** : cette technique sert par exemple à tester des payloads XSS qui seraient normalement bloqués par la CSP du site cible, dans un cadre d'audit autorisé.
