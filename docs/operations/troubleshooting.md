# Troubleshooting

## Commandes de diagnostic rapide

```bash
# État global de toutes les ressources Flux
flux --context production check

# Kustomizations en erreur
flux --context production -n flux-system get kustomizations | grep -v True

# HelmReleases en erreur
flux --context production get helmreleases -A | grep -v True

# Événements récents (erreurs en priorité)
flux --context production -n flux-system events --for Kustomization/applications
```

---

## Problèmes fréquents

### Kustomization bloquée en `Progressing`

**Symptôme** : `flux get kustomizations` affiche `Progressing` depuis plusieurs minutes.

**Diagnostic** :
```bash
flux --context production -n flux-system describe kustomization <nom>
kubectl -n flux-system logs deploy/kustomize-controller --tail=50
```

**Causes possibles** :
- Dépendance (`dependsOn`) non résolue → vérifier la Kustomization parente
- Timeout dépassé (configuré à `5m`) → les ressources déployées sont peut-être en `Pending`
- Erreur SOPS → voir section [Erreur de déchiffrement](#erreur-de-dechiffrement)

---

### HelmRelease en `Failed`

```bash
flux --context production -n <namespace> describe helmrelease <nom>
kubectl -n <namespace> logs deploy/helm-controller --tail=50
```

**Causes fréquentes** :
- Valeurs Helm invalides dans `values.yaml`
- Chart introuvable (HelmRepository inaccessible)
- CRD manquante (infrastructure pas encore déployée)

Pour forcer un re-déploiement :
```bash
flux --context production -n <namespace> reconcile helmrelease <nom> --reset
```

---

### Erreur de déchiffrement

**Symptôme** :
```
decryption failed: ...
```

**Vérifications** :

1. Le secret `sops-age-private-key` existe dans `flux-system` :
   ```bash
   kubectl -n flux-system get secret sops-age-private-key
   ```

2. La clé correspond au bon environnement (localhost vs production)

3. Le fichier `.enc.yaml` a bien été chiffré avec la bonne clé :
   ```bash
   sops --decrypt path/to/secrets.enc.yaml
   ```

!!! warning "Ne jamais recréer la clé age sans re-chiffrer tous les secrets"

---

### Image non mise à jour (Alterconso)

Si l'image automation ne fonctionne pas pour `alterconso` :

```bash
# Vérifier ImageRepository
flux --context production -n le-portail-alterconso get imagerepositories

# Vérifier ImagePolicy
flux --context production -n le-portail-alterconso get imagepolicies

# Forcer un scan
flux --context production -n le-portail-alterconso reconcile image repository alterconso
```

---

### Pod en `Pending` après déploiement

```bash
kubectl -n <namespace> describe pod <nom>
```

**Causes possibles en production** :
- PVC en attente → vérifier Longhorn : `kubectl -n longhorn-system get pods`
- Ressources insuffisantes → `kubectl describe node`
- Secret non répliqué → vérifier Reflector : `kubectl -n <namespace> get secret <nom>`

---

## Logs des controllers Flux

```bash
# Source controller (Git, Helm repos)
kubectl -n flux-system logs deploy/source-controller -f

# Kustomize controller
kubectl -n flux-system logs deploy/kustomize-controller -f

# Helm controller
kubectl -n flux-system logs deploy/helm-controller -f

# Image automation controller
kubectl -n flux-system logs deploy/image-automation-controller -f

# Image reflector controller
kubectl -n flux-system logs deploy/image-reflector-controller -f
```
