# Dolibarr

**Dolibarr** est un ERP/CRM open source utilisé par les tenants `ferme-du-jointout` et `le-portail`.

---

## Sources Helm

| Ressource | Type | URL |
|-----------|------|-----|
| HelmRepository `dolibarr` | HelmRepository | `https://cowboysysop.github.io/charts/` |
| HelmRelease `dolibarr` | — | chart: `dolibarr` |

---

## Ressources déployées

À partir de `applications/base/dolibarr/` :

| Fichier | Ressource |
|---------|-----------|
| `namespace.yaml` | Namespace (renommé par overlay) |
| `helm.yaml` | HelmRepository + HelmRelease |
| `init-db.yaml` | Job d'init de la base de données MySQL |
| `backup.yaml` | K8up Schedule + PreBackupPod (mysqldump) |

---

## Configuration HelmRelease

```yaml
spec:
  releaseName: dolibarr
  chart:
    spec:
      chart: dolibarr
      sourceRef:
        kind: HelmRepository
        name: dolibarr
  interval: 5m
  timeout: 3m
  install:
    remediation:
      retries: 3
```

Les valeurs spécifiques (URL, credentials DB, domaine) sont définies dans le `values.yaml` de chaque overlay.

---

## Instances déployées

| Tenant | Namespace | Environnements |
|--------|-----------|----------------|
| ferme-du-jointout | `ferme-du-jointout-dolibarr` | localhost + production |
| le-portail | `le-portail-dolibarr` | localhost + production |

---

## Sauvegarde

La sauvegarde inclut un dump MySQL via PreBackupPod avant la sauvegarde des volumes :

```bash
# Déclencher une sauvegarde manuelle
task backup:k8up:ferme-du-jointout:dolibarr
task backup:k8up:le-portail:dolibarr
```

`USER_ID: 0` / `GROUP_ID: 0` (root) pour les deux instances.

---

## Accéder à l'instance en production

```bash
# Logs
kubectl --context production -n le-portail-dolibarr logs deploy/dolibarr -f

# Shell
kubectl --context production -n le-portail-dolibarr exec -it deploy/dolibarr -- bash
```
