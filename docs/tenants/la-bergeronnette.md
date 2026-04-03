# Tenant — la-bergeronnette

Tenant dédié à **La Bergeronnette**, hébergée sur `labergeronnette.org`.

---

## Capsule Tenant

```yaml
spec:
  owners:
    - name: la-bergeronnette-admin
      kind: User
  namespaceOptions:
    quota: 10
    additionalMetadata:
      labels:
        capsule.clastix.io/tenant: la-bergeronnette
```

---

## Applications

| Application | Namespace | Environnements | Domaine production |
|-------------|-----------|----------------|-------------------|
| WordPress | `la-bergeronnette-wordpress` | production uniquement | `labergeronnette.org` |

!!! note "Pas d'environnement localhost"
    `la-bergeronnette` n'a pas d'overlay localhost. Le `sync.yaml` pointe directement vers `./applications/la-bergeronnette/production` sans substitution d'environnement.

---

## Structure des overlays

```
applications/la-bergeronnette/
├── sync.yaml
└── production/
    └── wordpress-site/
        ├── kustomization.yaml
        ├── values.yaml
        └── secrets.enc.yaml
```

---

## Sauvegarde manuelle

```bash
task backup:k8up:la-bergeronnette:wordpress-site
```

Bucket S3 cible : `backup-srv1515851-la-bergeronnette-wordpress-site`

- `USER_ID: 1001` / `GROUP_ID: 1001` (utilisateur WordPress)
