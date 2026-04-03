# Cluster Production

Cluster de production hébergé sur un VPS Hostinger (`srv1515851.hstgr.cloud`), avec Flux CD comme opérateur GitOps principal.

---

## Caractéristiques

| Paramètre | Valeur |
|-----------|--------|
| Distribution | k3s |
| VPS | `srv1515851.hstgr.cloud` (Hostinger) |
| TLS | Let's Encrypt (DNS-01 via webhook OVH) |
| Stockage | Longhorn (distribué, XFS par défaut) |
| Base de données | MySQL Operator (InnoDB Cluster 8.4.3) |
| Ingress | Traefik v39.0.0 (HTTP → HTTPS redirect) |

---

## Kustomizations actives

```
clusters/production/
├── flux-system/
│   └── kustomization.yaml   ← même tuning que localhost (concurrent=20)
├── applications.yaml         ← path: ./applications, ENVIRONMENT=production
├── infrastructure.yaml       ← controllers + configurations production
└── tenant.yaml               ← path: ./tenants
```

### Chaîne de dépendances

```yaml
# infrastructure.yaml
infrastructure-controllers:
  path: ./infrastructure/controllers/production
  decryption: sops

infrastructure-configurations:
  dependsOn: [infrastructure-controllers]
  path: ./infrastructure/configurations/production
  patches:
    - traefik.gpenaud.production (IngressRoute & Certificate)
```

---

## Infrastructure production

Contrôleurs actifs en production (`infrastructure/controllers/production/`) :

| Contrôleur | Namespace | Version |
|------------|-----------|---------|
| cert-manager | `controller-cert-manager` | v1.x (OCI) |
| cert-manager-webhook-ovh | `controller-cert-manager` | — |
| capsule | `controller-capsule` | — |
| k8up | `controller-k8up` | — |
| reflector | `controller-reflector` | — |
| traefik | `controller-traefik` | v39.0.0 |
| longhorn | `controller-longhorn` | v1.x |
| mysql-operator | `controller-mysql-operator` | — |

---

## Configurations production

### ClusterIssuers Let's Encrypt

Deux issuers coexistent pour permettre les tests sans consommer le quota de rate-limit production :

| Issuer | Serveur ACME | Usage |
|--------|-------------|-------|
| `letsencrypt-staging` | `acme-staging-v02…` | Tests de configuration |
| `letsencrypt-production` | `acme-v02…` | Certificats réels |

La validation utilise **DNS-01** via le webhook cert-manager-ovh, avec des credentials OVH distincts par domaine :

| Credentials | Domaines |
|-------------|---------|
| Secret `dns-ovh` | `leportail.org`, `labergeronnette.org` |
| Secret `dns-ovh-ferme-du-jointout` | `fermedujointout.fr` |

### MySQL InnoDB Cluster

```yaml
# infrastructure/configurations/production/mysql-servers/version_8_lts.yaml
kind: InnoDBCluster
metadata:
  name: mysql-version-8-lts
  namespace: controller-mysql-operator
spec:
  instances: 1
  version: "8.4.3"
  edition: community
  router:
    instances: 1
```

Le cluster MySQL est accessible depuis tous les namespaces via :
```
mysql-version-8-lts.controller-mysql-operator.svc.cluster.local
```

---

## Secrets production

Les secrets SOPS sont déchiffrés par Flux via la clé age stockée dans :

```bash
kubectl -n flux-system get secret sops-age-private-key
```

Secrets infrastructure déployés :

| Secret | Contenu |
|--------|---------|
| `dns-ovh` | Credentials OVH API pour cert-manager |
| `dns-ovh-ferme-du-jointout` | Credentials OVH API (tenant spécifique) |
| `mysql-operator` | Mot de passe root MySQL |
| `s3-ovh` | Credentials S3 OVH pour les sauvegardes K8up |

---

## Applications déployées en production

| Tenant | Applications |
|--------|-------------|
| ferme-du-jointout | Dolibarr, Nextcloud, WordPress |
| la-bergeronnette | WordPress |
| le-portail | Alterconso, Dolibarr, Grist, WordPress (×2) |

---

## Snapshots VPS

Avant toute opération risquée, créer un snapshot du VPS :

```bash
task infrastructure:vps:snapshot
```

!!! warning "Confirmation requise"
    Cette tâche demande de taper `je confirme` pour éviter les écrasements accidentels de snapshots.
