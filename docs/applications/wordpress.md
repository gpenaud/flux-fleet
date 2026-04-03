# WordPress

WordPress est le CMS utilisé par tous les tenants. Plusieurs instances coexistent avec des configurations distinctes.

---

## Sources Helm

| Ressource | Type | URL / Ref |
|-----------|------|-----------|
| OCIRepository `bitnami` | OCI | `oci://registry-1.docker.io/bitnamicharts` |
| HelmRelease `wordpress` | — | chart: `wordpress`, version: `28.1.7` |

!!! note "Chart Bitnami"
    WordPress utilise le chart Bitnami via une OCIRepository Docker Hub. L'interval de vérification est de `24h`.

---

## Particularités du HelmRelease

```yaml
spec:
  timeout: 30m       # Timeout long car le chart Bitnami est volumineux
  install:
    timeout: 30m
    remediation:
      retries: -1    # Réessaie indéfiniment (chart lourd en premier déploiement)
  postRenderers:
    - kustomize:
        patches:
          # Ajoute l'annotation K8up sur le PVC pour l'inclure dans les sauvegardes
          - target:
              kind: PersistentVolumeClaim
            patch: |-
              - op: add
                path: /metadata/annotations/k8up.io~1backup
                value: "true"
```

---

## Instances déployées

| Instance | Tenant | Namespace | Environnements | Domaine |
|----------|--------|-----------|----------------|---------|
| wordpress-site | ferme-du-jointout | `ferme-du-jointout-wordpress` | localhost + production | `fermedujointout.fr` |
| wordpress-site | la-bergeronnette | `la-bergeronnette-wordpress` | production | `labergeronnette.org` |
| wordpress-site | le-portail | `le-portail-wordpress` | localhost + production | `leportail.org` |
| wordpress-epilibres | le-portail | `le-portail-wordpress-epilibres` | production | — |

---

## Sauvegarde

Chaque instance dispose de son propre `Schedule` K8up et d'un `PreBackupPod` qui effectue un `mysqldump` avant la sauvegarde :

```bash
# Sauvegardes manuelles
task backup:k8up:ferme-du-jointout:wordpress-site
task backup:k8up:la-bergeronnette:wordpress-site
task backup:k8up:le-portail:wordpress-site
task backup:k8up:le-portail:wordpress-epilibres
```

- `USER_ID: 1001` / `GROUP_ID: 1001` pour toutes les instances WordPress

---

## Planification des sauvegardes automatiques

```
Sauvegarde  : 1er et 15 de chaque mois à 21h00
Vérification: 1er et 15 de chaque mois à 21h30
Nettoyage   : 1er et 15 de chaque mois à 22h00
```

Rétention :
- 8 sauvegardes hebdomadaires (~4 mois)
- 6 sauvegardes mensuelles

---

## Connexion MySQL

Les applications WordPress se connectent au cluster MySQL partagé via :
```
mysql-version-8-lts.controller-mysql-operator.svc.cluster.local
```

Les credentials (user, password, database) sont définis dans le `secrets.enc.yaml` de chaque overlay et montés comme variables d'environnement dans le PreBackupPod.
