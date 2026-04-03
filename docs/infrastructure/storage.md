# Stockage — Longhorn

**Longhorn** est le système de stockage distribué utilisé en production. Il fournit des volumes persistants (PVC) répliqués pour toutes les applications.

---

## Configuration déployée

```yaml
# infrastructure/controllers/production/longhorn.yaml
values:
  defaultSettings:
    defaultDataPath: /var/lib/longhorn
    snapshotDataIntegrity: disabled
    autoCleanupSystemGeneratedSnapshot: true
    disableScheduledBackup: true    # Les sauvegardes sont gérées par K8up
  persistence:
    defaultClass: true
    defaultClassReplicaCount: 1
    defaultFsType: xfs
```

---

## StorageClasses disponibles

| StorageClass | Filesystem | Répliques | Reclaim Policy | Usage |
|---|---|---|---|---|
| `longhorn` (défaut) | XFS | 1 | Delete | Applications standard |
| `longhorn-ext4` | ext4 | 2 | **Retain** | Données critiques |

!!! tip "Choisir la bonne StorageClass"
    Utiliser `longhorn-ext4` pour les volumes de base de données ou tout volume dont la perte serait critique. La policy `Retain` conserve le PV même si le PVC est supprimé.

---

## UI Longhorn

L'UI est accessible via Traefik avec un certificat Let's Encrypt staging :

- **URL** : `https://longhorn.leportail.org`
- **Ingress** : IngressRoute Traefik avec TLS

!!! warning "Certificat staging"
    L'UI utilise un certificat Let's Encrypt staging (non approuvé par les navigateurs). Ajouter une exception de sécurité ou passer en `letsencrypt-production`.

---

## Sauvegardes Longhorn

Longhorn a ses sauvegardes schedulées **désactivées** (`disableScheduledBackup: true`). Les sauvegardes des données sont entièrement gérées par **K8up** (voir [Stratégie de sauvegarde](../backups/overview.md)).

---

## Localhost

En localhost, k3s utilise la StorageClass `local-path` fournie nativement. Les données sont stockées dans `/var/lib/rancher/k3s/storage/` sur le nœud.

```bash
# Vérifier la StorageClass par défaut en localhost
kubectl --context localhost get storageclass
```

---

## Opérations courantes

### Vérifier l'état des volumes

```bash
kubectl --context production -n controller-longhorn get volumes
```

### Agrandir un volume

Longhorn supporte l'extension de volumes à chaud (sans redémarrage du pod) :

```bash
kubectl --context production patch pvc <nom> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"<nouvelle-taille>"}}}}'
```

### Forcer un snapshot manuel

```bash
kubectl --context production -n controller-longhorn create -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: manual-$(date +%Y%m%d)
spec:
  volume: <nom-du-volume>
EOF
```
