# Tenant — le-portail

Tenant principal hébergeant plusieurs applications de **Le Portail**, plateforme associative sur `leportail.org`.

---

## Capsule Tenant

```yaml
spec:
  owners:
    - name: le-portail-admin
      kind: User
    - name: local
      kind: User
  namespaceOptions:
    quota: 10
    additionalMetadata:
      labels:
        capsule.clastix.io/tenant: le-portail
```

---

## Applications

| Application | Namespace | Environnements | Notes |
|-------------|-----------|----------------|-------|
| Alterconso | `le-portail-alterconso` | localhost + production | Image automation active |
| Dolibarr | `le-portail-dolibarr` | localhost + production | ERP |
| Grist | `le-portail-grist` | localhost + production | Tableur collaboratif |
| WordPress (site) | `le-portail-wordpress` | localhost + production | Site principal |
| WordPress (Épi-Libres) | `le-portail-wordpress-epilibres` | production uniquement | Site secondaire |
| Écolieu | `le-portail-ecolieu` | localhost uniquement | En cours de développement |
| Épi-Libres | `le-portail-epi-libres` | localhost uniquement | En cours de développement |

---

## Structure des overlays

```
applications/le-portail/
├── sync.yaml                        ← path: ./applications/le-portail/${ENVIRONMENT}
├── base/
│   └── alterconso/                  ← Application + image automation
│       ├── namespace.yaml
│       ├── helm.yaml
│       ├── backup.yaml
│       ├── kustomization.yaml
│       └── image/
│           ├── policy.yaml          ← ImagePolicy: semver 1.0.x
│           ├── repository.yaml      ← ImageRepository
│           └── updateautomation.yaml
├── localhost/
│   ├── alterconso/
│   ├── dolibarr/
│   ├── ecolieu/
│   ├── epi-libres/
│   └── grist/
└── production/
    ├── alterconso/
    ├── dolibarr/
    ├── grist/
    ├── wordpress-epilibres/
    └── wordpress-site/
```

---

## Image Automation — Alterconso

Alterconso est la seule application avec **image automation** Flux active. Les nouvelles versions de l'image container sont détectées automatiquement et committées dans Git :

```yaml
# Image policy : accepte uniquement les patches de la série 1.0.x
spec:
  policy:
    semver:
      range: 1.0.x
```

Le chart Helm provient du dépôt personnel :
`https://raw.githubusercontent.com/gpenaud/helm-charts/master`

---

## Sauvegardes manuelles

```bash
task backup:k8up:le-portail:wordpress-site
task backup:k8up:le-portail:wordpress-epilibres
task backup:k8up:le-portail:dolibarr
task backup:k8up:le-portail:alterconso     # USER_ID: 33 (www-data)
task backup:k8up:le-portail:grist
```

Buckets S3 cibles : `backup-srv1515851-le-portail-<service>`
