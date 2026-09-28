# 04 - Repeater

**Repeater** permet de reprendre une requête capturée, de la modifier manuellement et de la renvoyer autant de fois que nécessaire, en observant la réponse à chaque envoi. C'est l'outil de prédilection pour explorer une vulnérabilité en détail après l'avoir repérée dans le Proxy.

## Envoyer une requête vers Repeater

- Depuis **Proxy > HTTP history**, clic droit sur une requête → **Send to Repeater** (raccourci `Ctrl+R`).
- Dans **Repeater**, modifier librement la requête (URL, en-têtes, corps) puis cliquer **Send**.

## TP 4.1 — Exploiter une injection SQL avec Repeater (DVWA, niveau low)

1. Sur DVWA, aller dans le module **SQL Injection**, soumettre l'ID `1`.
2. Envoyer la requête `GET /vulnerabilities/sqli/?id=1&Submit=Submit` vers Repeater.
3. Dans Repeater, remplacer `id=1` par `id=1' OR '1'='1`.
4. Envoyer et comparer la réponse : plusieurs enregistrements doivent apparaître au lieu d'un seul.
5. Tester ensuite `id=1' UNION SELECT user, password FROM users-- -` pour extraire des identifiants (adapter selon la structure de la table connue de DVWA).

**Validation** : la réponse contient des données provenant d'une table différente de celle attendue, confirmant l'injection.

## TP 4.2 — Tester une IDOR (Insecure Direct Object Reference) sur Juice Shop

1. Se connecter sur Juice Shop avec un compte utilisateur standard.
2. Consulter son propre panier ou ses commandes ; repérer une requête du type `GET /rest/basket/6` (l'ID `6` correspond à l'utilisateur courant).
3. Envoyer cette requête vers Repeater.
4. Modifier l'ID (`/rest/basket/1`, `/rest/basket/2`, etc.) en conservant le même token d'authentification.
5. Observer si le serveur renvoie le panier d'un autre utilisateur.

**Validation** : si le contenu retourné correspond à un panier différent du vôtre, il s'agit d'une IDOR — l'application ne vérifie pas que l'utilisateur authentifié est bien le propriétaire de la ressource demandée.

## Astuces Repeater

- **Ctrl+Espace** insère/retire un curseur multiple utile pour tester plusieurs points rapidement.
- L'onglet **History** de Repeater (icône horloge) garde la trace de tous les envois successifs pour une même requête, pratique pour comparer les réponses au fil des essais.
- Utiliser des onglets Repeater nommés (clic droit sur l'onglet → Rename) pour organiser plusieurs pistes de test en parallèle.
