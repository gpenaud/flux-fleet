# Référence des environnements

## Variables de substitution Flux

Les variables sont injectées par les Kustomizations des clusters via `postBuild.substitute`.

| Variable | Localhost | Production | Portée |
|----------|-----------|------------|--------|
| `ENVIRONMENT` | `localhost` | `production` | Kustomization `applications` et `tenants` |
| `TENANT` | `ferme-du-jointout` / `le-portail` | idem | Kustomization `sync.yaml` de chaque tenant |

### Utilisation dans les chemins

```yaml
# sync.yaml d'un tenant
path: ./applications/ferme-du-jointout/${ENVIRONMENT}
# → ./applications/ferme-du-jointout/localhost  (en dev)
# → ./applications/ferme-du-jointout/production (en prod)
```

---

## Différences localhost / production

| Composant | Localhost | Production |
|-----------|-----------|------------|
| TLS | mkcert (auto-signé local) | Let's Encrypt (DNS-01 OVH) |
| ClusterIssuer | `mkcert` | `letsencrypt-staging` / `letsencrypt-production` |
| Stockage | `local-path` (k3s) | Longhorn (XFS, ext4) |
| Base de données | MariaDB embarqué (charts) | MySQL Operator InnoDB 8.4.3 |
| Traefik | Pas de redirect HTTPS | Redirect HTTP→HTTPS permanente |
| Longhorn | Absent | Présent |
| MySQL Operator | Absent | Présent |
| Sauvegardes K8up | Présent (non actif par défaut) | Actif |

---

## Namespaces par environnement

### Convention

```
{tenant}-{application}
```

### Exemples

| Application | Namespace |
|-------------|-----------|
| WordPress (le-portail) | `le-portail-wordpress` |
| WordPress (la-bergeronnette) | `la-bergeronnette-wordpress` |
| Dolibarr (ferme-du-jointout) | `ferme-du-jointout-dolibarr` |
| Nextcloud (ferme-du-jointout) | `ferme-du-jointout-nextcloud` |
| Alterconso (le-portail) | `le-portail-alterconso` |
| Grist (le-portail) | `le-portail-grist` |

### Namespaces d'infrastructure

| Composant | Namespace |
|-----------|-----------|
| Flux CD | `flux-system` |
| Traefik | `controller-traefik` |
| cert-manager | `controller-cert-manager` |
| Capsule | `controller-capsule` |
| K8up | `controller-k8up` |
| Reflector | `controller-reflector` |
| Longhorn | `controller-longhorn` |
| MySQL Operator | `controller-mysql-operator` |

---

## Contexts kubectl

| Context | Cluster | Usage |
|---------|---------|-------|
| `localhost` | k3s local | Développement et tests |
| `production` | `srv1515851.hstgr.cloud` | Production |

Toutes les commandes `flux` et `kubectl` dans ce dépôt utilisent `--context production` (cible production par défaut dans le Taskfile).

---

## Secrets SOPS par environnement

| Fichier | Clé age utilisée |
|---------|-----------------|
| `*/localhost/*/secrets.yaml` | Clé localhost uniquement |
| `*/production/*/secrets.yaml` | Clé production uniquement |
| `*/base/secrets/*.yaml` | Les deux clés (key_groups) |
| `tools/tasks/*.yaml` | Clé localhost |

Voir [Gestion des secrets](../architecture/secrets.md) pour les détails.
