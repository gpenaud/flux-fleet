# Sources Helm

Référence de toutes les sources Helm utilisées dans le dépôt.

---

## HelmRepository

| Nom | URL | Utilisé par | Interval |
|-----|-----|-------------|---------|
| `dolibarr` | `https://cowboysysop.github.io/charts/` | Dolibarr (base) | 5m |
| `nextcloud` | `https://nextcloud.github.io/helm/` | Nextcloud (ferme-du-jointout/base) | 5m |
| `alterconso` | `https://raw.githubusercontent.com/gpenaud/helm-charts/master` | Alterconso (le-portail/base) | 5m |
| `longhorn` | `https://charts.longhorn.io` | Longhorn (infrastructure/production) | 24h |
| `mysql-operator` | `https://mysql.github.io/mysql-operator/` | MySQL Operator (infrastructure/production) | 1h |

---

## OCIRepository

| Nom | URL OCI | Tag / Version | Utilisé par | Interval |
|-----|---------|--------------|-------------|---------|
| `traefik` | `oci://ghcr.io/traefik/helm/traefik` | `39.0.0` | Traefik (infrastructure/production) | 24h |
| `bitnami` (WordPress) | `oci://registry-1.docker.io/bitnamicharts` | chart `wordpress` v`28.1.7` | WordPress (base) | 24h |
| cert-manager | `oci://quay.io/jetstack/cert-manager` | `v1.x` | cert-manager (infrastructure/base) | — |

---

## GitRepository

| Nom | URL | Branche | Utilisé par | Interval |
|-----|-----|---------|-------------|---------|
| `flux-system` | Ce dépôt (`flux-fleet`) | `main` | Tous les Kustomizations | 1h |
| `dirnum-forked` | `https://github.com/gpenaud/helm-charts-dirnum` | `feature/make-loadbalancer-component-optional` | Grist (base) | 5m |

---

## Notes

!!! tip "Interval de 24h pour les sources OCI"
    Les sources OCIRepository (Traefik, Bitnami) ont un interval de 24h car ce sont des dépendances stables. Les HelmRepository d'applications (Dolibarr, Nextcloud) ont un interval de 5m pour détecter rapidement les mises à jour.

!!! warning "Chart Grist — branche de feature"
    Le chart Grist provient d'une branche `feature/` d'un fork. Une montée de version nécessite de vérifier que cette branche est toujours à jour avec l'upstream.

!!! note "WordPress — version épinglée"
    Le chart Bitnami WordPress est épinglé à `28.1.7`. Pour mettre à jour, modifier la version dans `applications/base/wordpress/helm.yaml` et tester en localhost avant de merger.
