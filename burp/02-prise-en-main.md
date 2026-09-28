# 02 - Prise en main de l'interface

## Les onglets principaux

| Onglet | Rôle |
|---|---|
| **Dashboard** | Vue d'ensemble du projet, tâches en cours, issues détectées |
| **Target** | Arborescence du site cible (Site map), définition du scope |
| **Proxy** | Interception et historique du trafic HTTP/HTTPS |
| **Intruder** | Attaques automatisées par substitution de payloads |
| **Repeater** | Rejeu manuel et modification de requêtes individuelles |
| **Sequencer** | Analyse de l'aléa des tokens (session, CSRF...) |
| **Decoder** | Encodage/décodage (Base64, URL, Hex, hash...) |
| **Comparer** | Diff entre deux requêtes/réponses |
| **Extender / BApp Store** | Gestion des extensions (Community : "Extensions") |

## Définir le scope (périmètre)

Le **scope** permet de restreindre les actions de Burp (et l'affichage) au périmètre autorisé du test — une bonne pratique indispensable en engagement réel pour éviter de toucher des systèmes hors périmètre.

### TP 2.1 — Définir un scope sur Juice Shop

1. Lancer Juice Shop (`docker run --rm -p 3000:3000 bkimminich/juice-shop`) et y naviguer via le navigateur proxifié.
2. Dans **Target > Site map**, faire un clic droit sur `http://localhost:3000` → **Add to scope**.
3. Aller dans **Proxy > Options** (ou **Proxy > HTTP history**, filtre) et activer « Show only in-scope items ».
4. Naviguer sur quelques pages de Juice Shop puis vérifier que seuls les échanges avec `localhost:3000` apparaissent, même si le navigateur charge des ressources tierces (fonts, CDN, etc.).

**Validation** : la Site map ne contient plus que l'arborescence de Juice Shop, et le bruit des requêtes hors cible a disparu.

## Le navigateur intégré (Burp's Browser)

Depuis les versions récentes, Burp embarque un Chromium préconfiguré (**Proxy > Intercept > Open Browser**), ce qui évite de configurer manuellement le proxy système. Recommandé pour les TP suivants si disponible dans votre version.
