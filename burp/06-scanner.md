# 06 - Scanner (Burp Suite Professional)

Le **Scanner** automatise la détection de vulnérabilités (XSS, SQLi, exposition d'informations, en-têtes de sécurité manquants...). Il n'est disponible qu'en édition **Professional**. Si vous n'avez que la Community Edition, ce chapitre reste utile pour comprendre le fonctionnement, mais les TP ne sont réalisables qu'avec une licence Pro (y compris une licence d'essai).

## Types de scan

- **Crawl** : découverte de l'arborescence du site (liens, formulaires, endpoints d'API) en simulant une navigation.
- **Audit** : envoi de payloads sur les points d'entrée découverts pour détecter des vulnérabilités.
- **Crawl and Audit** : les deux enchaînés.

## TP 6.1 — Scanner Juice Shop de bout en bout (nécessite Burp Pro)

1. Ajouter `http://localhost:3000` au scope (voir TP 2.1).
2. **Dashboard > New scan > Crawl and Audit this host**.
3. Configurer le scan : cocher « Use existing site map to seed the crawl » si vous avez déjà navigué manuellement au préalable (accélère et fiabilise la découverte).
4. Lancer le scan et observer les **Issues** remontées au fur et à mesure dans le Dashboard, classées par sévérité (High/Medium/Low/Information).
5. Ouvrir une issue de sévérité "High" (souvent une XSS réfléchie sur Juice Shop), lire le détail : requête, réponse, et l'explication de la vulnérabilité fournie par Burp.
6. Reproduire manuellement la vulnérabilité dans Repeater à partir de la requête fournie par le Scanner, pour valider le résultat (éviter les faux positifs).

**Validation** : vous devez pouvoir déclencher vous-même, manuellement, le comportement anormal identifié par le scan (ex. exécution du payload XSS dans la réponse).

## Limiter le bruit et le scope du scan

- **Scan configuration > Crawl limits** : limiter la profondeur et le nombre de requêtes pour un scan pédagogique rapide.
- Exclure les endpoints de déconnexion/suppression de compte pour éviter que le crawler ne casse l'état de session pendant le test.

## Sans licence Pro : alternative Community

- Utiliser **Repeater** et **Intruder** manuellement en s'appuyant sur une checklist (type OWASP Testing Guide) pour couvrir les mêmes catégories de vulnérabilités qu'un scan automatisé.
- L'extension gratuite **Logger++** (BApp Store) aide à visualiser et filtrer un volume important de requêtes sans avoir le Scanner Pro.
