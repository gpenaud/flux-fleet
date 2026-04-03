# Grist

**Grist** est un tableur collaboratif open source, déployé pour le tenant `le-portail`.

---

## Sources Helm

| Ressource | Type | Détails |
|-----------|------|---------|
| GitRepository `dirnum-forked` | GitRepository | `https://github.com/gpenaud/helm-charts-dirnum` |
| HelmRelease `grist` | — | chart: `charts/grist` (depuis le GitRepository) |

!!! note "Chart forké"
    Grist utilise un **fork** du chart Helm `helm-charts-dirnum`, sur la branche `feature/make-loadbalancer-component-optional`. Ce fork rend le composant LoadBalancer optionnel, nécessaire pour un déploiement derrière Traefik.

---

## Configuration HelmRelease

```yaml
spec:
  releaseName: grist
  chart:
    spec:
      chart: charts/grist
      sourceRef:
        kind: GitRepository
        name: dirnum-forked
  interval: 5m
  timeout: 3m
  install:
    remediation:
      retries: 3
```

La source est un `GitRepository` (pas un `HelmRepository`), ce qui permet d'utiliser des branches de développement.

---

## Middlewares Traefik

Grist dispose de middlewares Traefik spécifiques définis dans `applications/base/grist/middlewares.yaml` pour la gestion des headers et redirections.

---

## Instances déployées

| Tenant | Namespace | Environnements |
|--------|-----------|----------------|
| le-portail | `le-portail-grist` | localhost + production |

---

## Sauvegarde

```bash
task backup:k8up:le-portail:grist
```

- `USER_ID: 0` / `GROUP_ID: 0`
- Bucket : `backup-srv1515851-le-portail-grist`

!!! note "Pas de dump SQL"
    Grist n'a pas de `PreBackupPod` MySQL — les données sont dans des fichiers de volume PVC directement sauvegardés par Restic.
