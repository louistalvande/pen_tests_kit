# 07 - Extensions (BApp Store)

Burp propose un catalogue d'extensions communautaires accessible dans l'onglet **Extensions > BApp Store** (certaines nécessitent Jython/JRuby, configurables dans **Extensions > Options**).

## Extensions utiles à connaître

| Extension | Usage |
|---|---|
| **Logger++** | Journalisation avancée avec filtres puissants, exportable en CSV |
| **Autorize** | Détection automatisée de failles de contrôle d'accès (IDOR, élévation de privilèges) en rejouant les requêtes avec une session à moindre privilège |
| **JSON Web Tokens** | Manipulation et attaque de JWT (test d'algorithme `none`, clés faibles) |
| **Param Miner** | Découverte de paramètres cachés (GET/POST/headers) non documentés |
| **Turbo Intruder** | Fuzzing haute performance via scripts Python, contourne le throttling de la Community |
| **Software Vulnerability Scanner** | Détection de versions de logiciels vulnérables via bannières/en-têtes |

## TP 7.1 — Installer et utiliser Autorize pour détecter une IDOR automatiquement

1. **Extensions > BApp Store**, rechercher `Autorize`, cliquer **Install**.
2. Se connecter à Juice Shop avec deux comptes : un compte "victime" (session basse privilège) et naviguer normalement avec le compte "attaquant" configuré comme session principale dans Burp.
3. Dans l'onglet **Autorize**, coller le cookie/token du compte victime dans le champ prévu à cet effet.
4. Naviguer sur l'application avec le compte attaquant : Autorize rejoue automatiquement chaque requête avec la session victime et compare les réponses.
5. Repérer dans la colonne **Enforced/Bypassed** les requêtes marquées comme "Bypassed!", signalant que la ressource du compte attaquant reste accessible avec la session victime (ou inversement selon le sens configuré).

**Validation** : au moins une requête doit apparaître en "Bypassed", confirmant une faille de contrôle d'accès horizontal ou vertical.

## TP 7.2 — Param Miner pour découvrir un paramètre caché

1. Installer **Param Miner** depuis la BApp Store.
2. Sur une requête de Juice Shop envoyée vers Repeater, clic droit → **Extensions > Param Miner > Guess params > Guess GET parameters**.
3. Lancer la recherche et observer les résultats dans **Extensions > Param Miner > Output** : un paramètre provoquant un changement de réponse (taille, code de statut) est potentiellement actif côté serveur.

**Validation** : un paramètre découvert modifie effectivement le comportement de l'application lorsqu'il est renvoyé manuellement avec une valeur dans Repeater.
