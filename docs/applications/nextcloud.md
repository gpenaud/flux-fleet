# Nextcloud

**Nextcloud** est une plateforme de collaboration et partage de fichiers, déployée uniquement pour le tenant `ferme-du-jointout`.

---

## Sources Helm

| Ressource | Type | URL |
|-----------|------|-----|
| HelmRepository `nextcloud` | HelmRepository | `https://nextcloud.github.io/helm/` |
| HelmRelease `nextcloud` | — | chart: `nextcloud` |

---

## Particularité — Base spécifique au tenant

Contrairement à Dolibarr et WordPress qui sont dans `applications/base/`, Nextcloud est défini dans la base spécifique au tenant :

```
applications/ferme-du-jointout/base/nextcloud/
├── namespace.yaml
├── helm.yaml
├── init-db.yaml
├── backup.yaml
└── kustomization.yaml
```

Cela reflète le fait que Nextcloud n'est utilisé que par `ferme-du-jointout`.

---

## Configuration HelmRelease

```yaml
spec:
  releaseName: nextcloud
  chart:
    spec:
      chart: nextcloud
      # version: "4.x.x"  # chart 4.x = Nextcloud 14
      sourceRef:
        kind: HelmRepository
        name: nextcloud
  interval: 5m
  timeout: 3m
```

!!! note "Version non épinglée"
    La version du chart est commentée, ce qui signifie que Flux utilisera la dernière version disponible. Épingler une version est recommandé pour les environnements de production.

---

## Instances déployées

| Tenant | Namespace | Environnements |
|--------|-----------|----------------|
| ferme-du-jointout | `ferme-du-jointout-nextcloud` | localhost + production |

---

## Sauvegarde

```bash
task backup:k8up:ferme-du-jointout:nextcloud
```

- `USER_ID: 0` / `GROUP_ID: 0` (root)
- Bucket : `backup-srv1515851-ferme-du-jointout-nextcloud`

La sauvegarde inclut un dump MySQL du schéma Nextcloud via PreBackupPod.
