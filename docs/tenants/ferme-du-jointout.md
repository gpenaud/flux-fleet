# Tenant — ferme-du-jointout

Tenant dédié à la coopérative agricole **Ferme du Jointout**, hébergée sur `fermedujointout.fr`.

---

## Capsule Tenant

```yaml
spec:
  owners:
    - name: ferme-du-jointout-admin
      kind: User
    - name: local
      kind: User
  namespaceOptions:
    quota: 10
    additionalMetadata:
      labels:
        capsule.clastix.io/tenant: ferme-du-jointout
```

---

## Applications

| Application | Namespace | Environnements | Domaine production |
|-------------|-----------|----------------|-------------------|
| Dolibarr | `ferme-du-jointout-dolibarr` | localhost + production | — |
| Nextcloud | `ferme-du-jointout-nextcloud` | localhost + production | — |
| WordPress | `ferme-du-jointout-wordpress` | localhost + production | `fermedujointout.fr` |

!!! note "Application wordpress nommée wordpress-gaec en localhost"
    L'overlay localhost nomme l'application `wordpress-gaec` tandis que la production utilise `wordpress-site`.

---

## Structure des overlays

```
applications/ferme-du-jointout/
├── sync.yaml                     ← path: ./applications/ferme-du-jointout/${ENVIRONMENT}
├── base/
│   └── nextcloud/                ← Nextcloud spécifique à ce tenant
│       ├── namespace.yaml
│       ├── helm.yaml
│       ├── init-db.yaml
│       ├── backup.yaml
│       └── kustomization.yaml
├── localhost/
│   ├── dolibarr/
│   ├── nextcloud/
│   └── wordpress-gaec/
└── production/
    ├── dolibarr/
    ├── nextcloud/
    └── wordpress-site/
```

---

## Sauvegardes manuelles

```bash
# Dolibarr
task backup:k8up:ferme-du-jointout:dolibarr

# Nextcloud
task backup:k8up:ferme-du-jointout:nextcloud

# WordPress
task backup:k8up:ferme-du-jointout:wordpress-site
```

Les buckets S3 cibles :
- `backup-srv1515851-ferme-du-jointout-dolibarr`
- `backup-srv1515851-ferme-du-jointout-nextcloud`
- `backup-srv1515851-ferme-du-jointout-wordpress-site`

---

## Credentials OVH DNS

Ce tenant utilise un compte OVH API **distinct** (`dns-ovh-ferme-du-jointout`) pour les challenges DNS-01 sur `fermedujointout.fr`, séparé des credentials utilisés pour `leportail.org` et `labergeronnette.org`.
