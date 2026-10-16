# Livrable Phase 1 — Cartographie des endpoints

> Cible locale : `anonymous_eshop` via host VirtualBox `10.0.2.2`
> Fronts : buyer `:5173`, vendor `:5174`, admin `:5175` — tous proxifient `/api/*` vers le backend `:8080`.
> Colonnes « testé » à compléter en Phase 3 (rejeu avec un JWT d'un autre rôle).

## Endpoints publics (sans authentification attendue)

| Méthode | Endpoint | Rôle attendu | Buyer JWT | Vendor JWT | Aucun token | Constat |
|---|---|---|---|---|---|---|
| GET | /api/public/maintenance | public | | | | |
| GET | /api/public/payment-config | public | | | | |
| GET | /api/public/seo | public | | | | |
| GET | /api/public/shipping-fee-tiers | public | | | | |
| GET | /api/public/theme | public | | | | |
| GET | /api/public/vat-rate | public | | | | |
| GET | /api/announcements | public | | | | |
| GET | /api/countries | public | | | | |
| GET | /api/carriers?countryCode=FR | public | | | | |

## Authentification (commun aux 3 fronts)

| Méthode | Endpoint | Rôle attendu | Constat |
|---|---|---|---|
| POST | /api/auth/login | public (émet le JWT) | |
| GET | /api/auth/me | authentifié | |
| GET | /api/me | authentifié | |

## Zone BUYER (`/api/buyer`, `/api/cart`, `/api/orders`, `/api/profile`)

| Méthode | Endpoint | Rôle attendu | Vendor JWT | Admin absent | Constat |
|---|---|---|---|---|---|
| GET | /api/buyer/products?page=&size= | buyer | | | |
| GET | /api/buyer/products/distinct-themes | buyer | | | |
| GET | /api/buyer/products/distinct-types | buyer | | | |
| GET | /api/cart | buyer | | | |
| POST | /api/cart/items | buyer | | | |
| GET | /api/orders | buyer | | | |
| POST | /api/orders | buyer | | | |
| GET | /api/orders/{id} | buyer (propriétaire) | | | **IDOR horizontal à tester** |
| POST | /api/orders/{id}/confirm-payment | buyer (propriétaire) | | | **Phase 4 paiement** |
| GET | /api/profile | buyer | | | |
| GET/POST | /api/profile/addresses | buyer | | | |

## Zone VENDOR (`/api/vendor/*`) — réservé rôle vendor

| Méthode | Endpoint | Rôle attendu | Buyer JWT | Constat |
|---|---|---|---|---|
| GET | /api/vendor/alerts | vendor | **à rejouer buyer** | |
| GET | /api/vendor/announcements | vendor | **à rejouer buyer** | |
| GET | /api/vendor/campaigns | vendor | **à rejouer buyer** | |
| GET | /api/vendor/campaigns/recipients(/count) | vendor | | fuite d'emails ? |
| GET | /api/vendor/email-settings | vendor | | secret SendGrid ? |
| GET | /api/vendor/orders | vendor | | |
| GET | /api/vendor/orders/{id} | vendor (propriétaire) | | **IDOR vendeur A→B** |
| POST | /api/vendor/orders/{id}/prepare | vendor (propriétaire) | | |
| GET/POST | /api/vendor/products | vendor | | |
| GET | /api/vendor/products/{id} | vendor (propriétaire) | | **IDOR vendeur A→B** |
| GET | /api/vendor/promo-codes | vendor | | |
| GET | /api/vendor/reports/sales?startDate=&endDate= | vendor | | fuite CA d'autrui ? |
| GET/POST | /api/vendor/seo(/products/{id}) | vendor | | |
| GET | /api/vendor/settings/bank | vendor | | **IBAN sensible** |
| GET | /api/vendor/settings/vat | vendor | | |
| GET | /api/vendor/shipping-fee-tiers | vendor | | |
| GET/POST | /api/vendor/shop/theme | vendor | | |

## Zone ADMIN (`/api/admin/*`) — réservé rôle admin

| Méthode | Endpoint | Rôle attendu | Buyer JWT | Vendor JWT | Constat |
|---|---|---|---|---|---|
| GET/POST | /api/admin/accounts | admin | **à rejouer** | **à rejouer** | **BFLA critique** |
| GET | /api/admin/accounts/revoked | admin | | | |
| GET | /api/admin/audit-logs?page=&size= | admin | | | fuite de logs |
| GET | /api/admin/carriers | admin | | | |
| GET | /api/admin/mail/config | admin | | | secret SMTP/SendGrid ? |
| GET | /api/admin/settings/maintenance | admin | | | |

## Observations immédiates (hors tableau)

- **Vite dev exposé** : `/@fs/workspace/...`, `/src/...`, `/node_modules/...` servent le code source brut. `/@fs/` = lecture de fichiers par chemin absolu → à documenter en Phase 7 (exposition). Vérifier aussi qu'aucun secret ne traîne dans les sources servies (clé Stripe secrète, JWT secret).
- **Backend unique partagé** par les 3 fronts : toute la sécurité d'accès repose sur la validation du rôle dans le JWT côté backend — cœur de la Phase 3.
- **UUID déjà capturés** : order `90088eb4-f1f1-43cf-afbe-160fab2868e7`, product `cb9bdfec-4a48-4e90-9ced-6026049d448d` — à réutiliser pour les tests IDOR.
