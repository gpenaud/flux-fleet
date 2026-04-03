# Démarrage

## Prérequis

### Outils requis

| Outil | Usage | Installation |
|-------|-------|-------------|
| `kubectl` | Interagir avec le cluster | [doc](https://kubernetes.io/docs/tasks/tools/) |
| `flux` | CLI Flux CD | `brew install fluxcd/tap/flux` |
| `sops` | Déchiffrer / chiffrer les secrets | `brew install sops` |
| `age` | Générer et gérer les clés de chiffrement | `brew install age` |
| `task` | Exécuter les tâches automatisées | `brew install go-task/tap/go-task` |
| `helm` | Inspecter les charts (optionnel) | `brew install helm` |

### Contextes kubectl

Les commandes Flux supposent l'existence de deux contextes kubectl :

| Contexte | Cluster |
|----------|---------|
| `localhost` | k3s local |
| `production` | VPS production (`srv1515851.hstgr.cloud`) |

Vérifier :
```bash
kubectl config get-contexts
```

---

## Bootstrap d'un cluster

### Localhost (développement)

Le cluster localhost est basé sur **k3s** et bootstrappé via Ansible :

```bash
task cluster:recreate:flux
```

Cette tâche exécute le playbook Ansible `install-k3s-with-flux.yml` qui installe k3s et bootstrappe Flux avec ce dépôt comme source.

### Production

1. **Créer le secret age** sur le cluster cible :

    ```bash
    # Exporter la clé privée age (à ne jamais committer)
    cat ~/.config/sops/age/keys.txt | kubectl --context production \
      -n flux-system create secret generic sops-age-private-key \
      --from-file=age.agekey=/dev/stdin
    ```

2. **Bootstrapper Flux** :

    ```bash
    flux bootstrap github \
      --context production \
      --owner=gpenaud \
      --repository=flux-fleet \
      --branch=main \
      --path=clusters/production \
      --personal
    ```

    Flux va :
    - Installer les composants dans `flux-system`
    - Créer une GitRepository pointant sur ce dépôt
    - Appliquer `clusters/production/` qui déclenche la chaîne complète

---

## Vérifier l'état après bootstrap

```bash
# Attendre que tous les contrôleurs soient prêts
flux --context production check

# Suivre la progression des Kustomizations
watch flux --context production -n flux-system get kustomizations

# Vérifier les HelmReleases
flux --context production get helmreleases -A
```

L'ordre d'apparition attendu dans `get kustomizations` :

```
infrastructure-controllers     True    Applied
infrastructure-configurations  True    Applied
tenants                        True    Applied
applications                   True    Applied
applications-ferme-du-jointout True    Applied
applications-la-bergeronnette  True    Applied
applications-le-portail        True    Applied
```

---

## Chiffrer ses premiers secrets

Copier un fichier de secrets en clair, l'éditer, puis le chiffrer :

```bash
# Créer le secret en clair (ne jamais committer ce fichier)
cp applications/le-portail/production/dolibarr/secrets.enc.yaml \
   applications/le-portail/production/dolibarr/secrets.yaml
sops --decrypt applications/le-portail/production/dolibarr/secrets.yaml

# Éditer le fichier en clair, puis rechiffrer
task cluster:encrypt

# Vérifier que le .enc.yaml est bien mis à jour
git diff applications/le-portail/production/dolibarr/secrets.enc.yaml
```

!!! warning "Ne jamais committer de `secrets.yaml`"
    Ces fichiers sont dans `.gitignore`. Seuls les `*.enc.yaml` doivent aller dans Git.

---

## Forcer une réconciliation

```bash
# Recharger la source Git et toute la chaîne
task reconcile:source

# Voir les détails si ça bloque
flux --context production -n flux-system events --watch
```

Voir [Réconciliation](operations/reconcile.md) pour plus de détails.
