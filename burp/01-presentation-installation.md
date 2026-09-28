# 01 - Présentation et installation

## Qu'est-ce que Burp Suite ?

Burp Suite (PortSwigger) est une suite d'outils dédiée aux tests de sécurité des applications web. Elle fonctionne comme un **proxy intercepteur** placé entre le navigateur et le serveur cible, ce qui permet d'observer, de modifier et de rejouer toutes les requêtes HTTP/HTTPS échangées.

### Éditions

| Édition | Usage |
|---|---|
| **Community Edition** (gratuite) | Proxy, Repeater, Decoder, Comparer, Sequencer manuel — suffisant pour la plupart des TP de ce dossier |
| **Professional** | Ajoute le Scanner automatique, Intruder sans limite de vitesse, extensions collaborator |
| **Enterprise** | Intégration CI/CD, scans planifiés à grande échelle |

Ce dossier se concentre sur les fonctionnalités disponibles en **Community Edition**, en signalant les cas où la version Pro apporte un vrai plus.

## Installation

### Téléchargement

Depuis le site officiel : https://portswigger.net/burp/communitydownload

### Linux

```bash
chmod +x burpsuite_community_linux_v*.sh
./burpsuite_community_linux_v*.sh
```

### Windows / macOS

Utiliser l'installeur graphique téléchargé (`.exe` ou `.dmg`).

### Kali Linux

Burp Suite Community Edition est **préinstallée par défaut** sur Kali — aucune installation nécessaire. Lancer directement :

```bash
burpsuite
```

ou via le menu **Applications > 03 - Web Application Analysis > burpsuite**.

Pour vérifier la version installée et la mettre à jour si besoin :

```bash
burpsuite --version
sudo apt update && sudo apt install --only-upgrade burpsuite
```

### Prérequis

- Java (embarqué dans l'installeur PortSwigger depuis les versions récentes, donc pas besoin de l'installer séparément)
- Un navigateur pour configurer le proxy (Firefox est recommandé car il permet une configuration de proxy indépendante du système, contrairement à Chrome)

## Installation du certificat CA de Burp

Pour intercepter le trafic **HTTPS**, Burp doit signer à la volée des certificats pour chaque domaine visité. Le navigateur doit donc faire confiance au certificat racine de Burp.

### TP 1.1 — Installer le certificat CA de Burp dans Firefox

1. Lancer Burp Suite, créer un projet temporaire (`Temporary project` → `Next` → `Use Burp defaults`).
2. Dans l'onglet **Proxy > Options** (ou **Proxy > Settings** selon la version), vérifier que le listener tourne sur `127.0.0.1:8080`.
3. Configurer Firefox pour utiliser un proxy manuel :
   - `Paramètres` → `Réseau` → `Paramètres` → `Configuration manuelle du proxy`
   - Hôte HTTP : `127.0.0.1`, Port : `8080`
   - Cocher « Utiliser aussi ce proxy pour HTTPS »
4. Dans Firefox, naviguer vers `http://burp` (une page spéciale servie par Burp).
5. Cliquer sur **CA Certificate** pour télécharger `cacert.der`.
6. Dans Firefox : `Paramètres` → `Vie privée et sécurité` → `Certificats` → `Afficher les certificats` → onglet `Autorités` → `Importer`, sélectionner `cacert.der`.
7. Cocher « Faire confiance à cette AC pour identifier des sites web ».
8. Retourner sur un site HTTPS (ex. `https://example.com`) : le cadenas doit s'afficher sans avertissement, et la requête doit apparaître dans l'onglet **Proxy > HTTP history** de Burp.

**Validation** : si l'historique HTTP de Burp affiche la requête en clair (méthode, URL, en-têtes) alors que le navigateur affiche un cadenas valide, l'interception HTTPS fonctionne.
