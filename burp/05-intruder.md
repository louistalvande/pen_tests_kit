# 05 - Intruder

**Intruder** automatise l'envoi d'une même requête avec des valeurs variables (payloads) injectées à des positions marquées. En Community Edition, la vitesse d'envoi est volontairement limitée (throttling), ce qui reste néanmoins suffisant pour les TP pédagogiques.

## Les 4 modes d'attaque

| Mode | Comportement |
|---|---|
| **Sniper** | Un seul jeu de payloads, injecté position par position (une position à la fois) |
| **Battering ram** | Un seul jeu de payloads, injecté **simultanément** à toutes les positions |
| **Pitchfork** | Plusieurs jeux de payloads, un jeu par position, envoyés en parallèle (index par index) |
| **Cluster bomb** | Plusieurs jeux de payloads, toutes les combinaisons possibles testées |

## TP 5.1 — Brute-force d'un login avec Sniper (DVWA, Brute Force module)

1. Sur DVWA, aller dans **Brute Force**, soumettre un login quelconque (`admin` / `test`).
2. Envoyer la requête `GET /vulnerabilities/brute/?username=admin&password=test&Login=Login` vers **Intruder** (`Ctrl+I`).
3. Dans l'onglet **Positions**, cliquer **Clear §** puis sélectionner uniquement la valeur de `password` et cliquer **Add §** pour marquer la position (`password=§test§`).
4. Choisir le mode **Sniper**.
5. Dans l'onglet **Payloads**, charger une petite wordlist (ex. `rockyou-top100.txt` ou une liste custom contenant `password` en premier).
6. Lancer l'attaque (**Start attack**).
7. Trier les résultats par **Length** ou par code de statut : la réponse de connexion réussie a généralement une taille différente (redirection ou contenu de page authentifiée).

**Validation** : identifier la ligne dont la longueur de réponse diverge des autres — c'est le mot de passe correct.

## TP 5.2 — Fuzzing de paramètre avec Pitchfork (recherche d'IDOR sur une plage d'IDs)

1. Sur Juice Shop, reprendre la requête `GET /rest/basket/6` du TP 4.2, l'envoyer vers Intruder.
2. Marquer `6` comme position unique.
3. Mode **Sniper**, payload de type **Numbers** : de `1` à `20`, step `1`.
4. Lancer l'attaque et comparer les codes de statut / tailles de réponse.

**Validation** : les IDs valides renverront un code 200 avec un contenu JSON exploitable ; les IDs invalides ou hors périmètre utilisateur renverront une erreur (401/403) selon le contrôle d'accès en place.

## TP 5.3 — Cluster bomb pour tester des combinaisons login/mot de passe

1. Reprendre la requête de login DVWA.
2. Marquer à la fois `username` et `password` comme positions.
3. Mode **Cluster bomb**.
4. Payload set 1 (username) : petite liste `admin, gordonb, 1337, pablo` (comptes par défaut connus de DVWA).
5. Payload set 2 (password) : petite wordlist de mots de passe courants.
6. Lancer l'attaque, trier par longueur de réponse pour repérer les couples valides.

**Validation** : DVWA en base de données par défaut contient plusieurs comptes avec des mots de passe faibles — l'objectif est d'en retrouver au moins un couple valide.

> 💡 Sur des cibles réelles, un brute-force massif peut déclencher un verrouillage de compte ou une alerte de sécurité (WAF, SOC). Toujours respecter les règles d'engagement définies avec le client (rate limiting, horaires autorisés, comptes de test dédiés).
