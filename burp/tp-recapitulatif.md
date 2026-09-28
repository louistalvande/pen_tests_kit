# TP récapitulatif — Mini-audit guidé de Juice Shop

Objectif : enchaîner un scénario complet mobilisant Proxy, Repeater, Intruder et Decoder sur une cible unique, comme lors d'un mini-audit réel.

**Prérequis** : Juice Shop lancé en local (`docker run --rm -p 3000:3000 bkimminich/juice-shop`), certificat Burp installé (TP 1.1), scope défini sur `localhost:3000` (TP 2.1).

## Étape 1 — Reconnaissance passive

1. Naviguer manuellement sur l'ensemble des pages accessibles (catalogue produits, recherche, panier, compte, contact...) avec Intercept désactivé.
2. Dans **Target > Site map**, examiner l'arborescence construite automatiquement : repérer les endpoints d'API (`/rest/...`, `/api/...`).

## Étape 2 — Analyse de l'authentification

1. Créer un compte de test, se connecter, envoyer la requête de login vers **Decoder** et décoder le JWT reçu (voir TP 3.2).
2. Vérifier dans le payload décodé si des informations sensibles (rôle, email) sont exposées sans nécessiter la clé de signature.

## Étape 3 — Recherche d'IDOR

1. Repérer un endpoint manipulant un identifiant numérique lié à l'utilisateur (panier, commande, adresse).
2. Envoyer la requête vers **Intruder**, faire varier l'ID sur une plage (TP 5.2).
3. Documenter les IDs pour lesquels des données appartenant à un autre compte sont retournées.

## Étape 4 — Recherche d'injection

1. Sur le champ de recherche produit (`/rest/products/search?q=...`), envoyer une requête vers **Repeater**.
2. Tester des payloads d'injection basiques (`'`, `' OR 1=1--`) et observer les codes d'erreur ou changements de comportement révélant une éventuelle injection SQL/NoSQL.

## Étape 5 — Restitution

Rédiger une synthèse courte pour chaque constat, avec :
- la requête/réponse illustrant le problème (export possible depuis Repeater : clic droit → **Save item**)
- une estimation de sévérité (ex. échelle CVSS simplifiée : Critique/Élevée/Moyenne/Faible)
- une recommandation de correction

> Cet exercice reproduit la structure d'un rapport de pentest réel : preuve technique + impact + remédiation, à adapter au format attendu par le client ou l'organisme certifiant lors d'un examen pratique.
