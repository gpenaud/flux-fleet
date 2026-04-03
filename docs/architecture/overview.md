# Architecture — Vue d'ensemble

## Chaîne de dépendances Flux

Flux applique les ressources dans un ordre strict défini par `dependsOn`. Aucune étape ne démarre tant que la précédente n'est pas `Ready`.

```mermaid
flowchart TD
    subgraph "1 — infrastructure-controllers"
        CM[cert-manager]
        CAP[capsule]
        K8UP[k8up]
        REF[reflector]
        SEC[secrets SOPS]
    end

    subgraph "2 — infrastructure-configurations"
        CI[ClusterIssuers\nLet's Encrypt]
        MY[MySQL InnoDB\nCluster]
        TD[Traefik Dashboard]
    end

    subgraph "3 — tenants"
        FDJ[ferme-du-jointout\nCapsule Tenant]
        LB[la-bergeronnette\nCapsule Tenant]
        LP[le-portail\nCapsule Tenant]
    end

    subgraph "4 — applications"
        direction LR
        A1[ferme-du-jointout\nDolibarr · Nextcloud · WP]
        A2[la-bergeronnette\nWordPress]
        A3[le-portail\nAlterconso · Dolibarr\nGrist · WordPress ×2]
    end

    SEC --> CI
    CM --> CI
    CI --> MY
    MY --> FDJ & LB & LP
    CAP --> FDJ & LB & LP
    FDJ --> A1
    LB --> A2
    LP --> A3
```

---

## Structure du dépôt

```
flux-fleet/
├── clusters/          # Bootstrap Flux par cluster (localhost / production)
├── infrastructure/    # Contrôleurs et configurations cluster-wide
│   ├── controllers/   # Helm releases des opérateurs
│   └── configurations/# ClusterIssuers, MySQL servers…
├── tenants/           # Définitions Capsule Tenant (RBAC)
├── applications/      # Applications par tenant et par environnement
│   ├── base/          # Templates Helm partagés
│   ├── ferme-du-jointout/
│   ├── la-bergeronnette/
│   └── le-portail/
└── tools/             # Taskfile, backup-validator (DevSpace)
```

---

## Flux de réconciliation

```mermaid
sequenceDiagram
    participant Dev as Développeur
    participant Git as Git (flux-fleet)
    participant Flux as Flux CD
    participant K8s as Kubernetes

    Dev->>Git: git push
    Flux->>Git: pull (interval: 1h)
    Flux->>Flux: Kustomize build + SOPS decrypt
    Flux->>K8s: kubectl apply
    K8s-->>Flux: status Ready / Failed
    Flux-->>Dev: alert (si erreur)
```

!!! info "Interval de réconciliation"
    Toutes les Kustomizations sont configurées avec `interval: 1h` et `retryInterval: 2m`.
    Pour forcer une réconciliation immédiate, voir [Réconciliation](../operations/reconcile.md).

---

## Environnements et substitution de variables

Chaque cluster injecte `ENVIRONMENT` via `postBuild.substitute` dans les Kustomizations `applications` et `tenants`. Les `sync.yaml` des tenants utilisent cette variable pour pointer vers le bon overlay :

```yaml
# clusters/production/applications.yaml
postBuild:
  substitute:
    ENVIRONMENT: production
```

```yaml
# applications/le-portail/sync.yaml
path: ./applications/le-portail/${ENVIRONMENT}
```
