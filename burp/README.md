# Burp Suite — Documentation & TP

Documentation pratique sur Burp Suite pour les tests d'intrusion web, avec des travaux pratiques pas à pas.

> ⚠️ **Cadre légal** : n'utilisez ces techniques que sur des cibles pour lesquelles vous avez une autorisation explicite (labs dédiés, environnements de test, périmètres de pentest sous contrat). Les TP ci-dessous s'appuient sur des applications volontairement vulnérables prévues pour l'entraînement (DVWA, OWASP Juice Shop, PortSwigger Web Security Academy).

## Sommaire

- [01 - Présentation et installation](01-presentation-installation.md)
- [02 - Prise en main de l'interface](02-prise-en-main.md)
- [03 - Proxy et interception](03-proxy-interception.md)
- [04 - Repeater](04-repeater.md)
- [05 - Intruder](05-intruder.md)
- [06 - Scanner (Burp Pro)](06-scanner.md)
- [07 - Extensions (BApp Store)](07-extensions.md)
- [TP récapitulatif](tp-recapitulatif.md)

## Environnement de lab recommandé

| Outil | Usage |
|---|---|
| [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/) | Application vulnérable moderne (Node.js), idéale pour s'entraîner en local via Docker |
| [DVWA](https://github.com/digininja/DVWA) | Application PHP volontairement vulnérable, niveaux de difficulté configurables |
| [PortSwigger Web Security Academy](https://portswigger.net/web-security) | Labs en ligne gratuits, conçus spécifiquement pour Burp Suite |

Lancer Juice Shop en local avec Docker :

```bash
docker run --rm -p 3000:3000 bkimminich/juice-shop
```

Lancer DVWA en local avec Docker :

```bash
docker run --rm -p 8080:80 vulnerables/web-dvwa
```
