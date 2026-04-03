# Cluster Localhost

Cluster de développement local basé sur **k3s**, utilisé pour tester les changements avant de les pousser en production.

---

## Caractéristiques

| Paramètre | Valeur |
|-----------|--------|
| Distribution | k3s |
| TLS | mkcert (certificats locaux auto-signés) |
| Stockage | emptyDir / local-path (défaut k3s) |
| Base de données | Pas de MySQL Operator (MariaDB embarqué dans les charts) |
| Ingress | Traefik (version embarquée k3s ou Helm) |

---

## Kustomizations actives

```
clusters/localhost/
├── flux-system/
│   └── kustomization.yaml   ← tuning des controllers Flux
├── applications.yaml         ← path: ./applications, ENVIRONMENT=localhost
├── infrastructure.yaml       ← path: ./infrastructure/controllers/localhost
└── tenant.yaml               ← path: ./tenants
```

### Tuning des controllers Flux

Le cluster localhost augmente la concurrence des controllers pour accélérer la réconciliation en développement :

```yaml
patches:
  - patch: |
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --concurrent=20
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --requeue-dependency=5s
    target:
      kind: Deployment
      name: "(kustomize-controller|helm-controller|source-controller)"
```

---

## Infrastructure localhost

Contrôleurs actifs en localhost (`infrastructure/controllers/localhost/`) :

| Contrôleur | Présent | Notes |
|------------|---------|-------|
| cert-manager | Oui | avec webhook OVH |
| capsule | Oui | |
| k8up | Oui | |
| reflector | Oui | |
| traefik | Oui | config simplifiée sans redirect HTTPS |
| longhorn | **Non** | stockage local-path k3s utilisé |
| mysql-operator | **Non** | MariaDB embarqué dans les charts |

### Configurations localhost

- **mkcert ClusterIssuer** — émet des certificats TLS locaux via mkcert
- **Traefik Dashboard** — accessible via IngressRoute locale avec certificat mkcert

---

## Applications déployées en localhost

| Tenant | Applications |
|--------|-------------|
| ferme-du-jointout | Dolibarr, Nextcloud, WordPress (GAEC) |
| le-portail | Alterconso, Dolibarr, Écolieu, Épi-Libres, Grist |

!!! note "la-bergeronnette absente du localhost"
    Le tenant `la-bergeronnette` n'a pas d'overlay localhost. Il est déployé uniquement en production.

---

## Bootstrap localhost

```bash
# Via Ansible (recommandé)
task cluster:recreate:flux

# Ou pour un environnement lab
task cluster:recreate:lab
```

## Vérifier l'état

```bash
flux --context localhost check
flux --context localhost -n flux-system get kustomizations
kubectl --context localhost get pods -A
```
