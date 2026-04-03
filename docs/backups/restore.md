# Restauration des sauvegardes

Les sauvegardes sont stockées dans des dépôts **Restic** sur S3 OVH. La restauration peut être effectuée via K8up ou directement avec la CLI `restic`.

---

## Prérequis

```bash
# Installer restic
brew install restic

# Récupérer les credentials S3 depuis le secret (production)
kubectl --context production -n le-portail-wordpress get secret s3-ovh -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d
kubectl --context production -n le-portail-wordpress get secret s3-ovh -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d
kubectl --context production -n le-portail-wordpress get secret s3-ovh -o jsonpath='{.data.RESTIC_PASSWORD}' | base64 -d
```

---

## Restaurer avec restic CLI

### 1. Configurer les variables d'environnement

```bash
export AWS_ACCESS_KEY_ID="<valeur>"
export AWS_SECRET_ACCESS_KEY="<valeur>"
export RESTIC_PASSWORD="<valeur>"
export RESTIC_REPOSITORY="s3:https://s3.sbg.io.cloud.ovh.net/backup-srv1515851-<tenant>-<service>"
```

### 2. Lister les snapshots disponibles

```bash
restic snapshots
```

Exemple de sortie :
```
ID        Time                 Host    Tags    Paths
--------  -------------------  ------  ------  -----
a1b2c3d4  2025-03-15 21:03:42  k8up            /data
e5f6g7h8  2025-03-01 21:02:18  k8up            /data, /pre-backup/dump.sql
```

### 3. Restaurer un snapshot

=== "Restaurer dans un répertoire local"

    ```bash
    restic restore <snapshot-id> --target /tmp/restore/
    ```

=== "Restaurer le dernier snapshot"

    ```bash
    restic restore latest --target /tmp/restore/
    ```

=== "Restaurer uniquement le dump SQL"

    ```bash
    restic restore latest --target /tmp/restore/ --include /pre-backup/
    ```

---

## Restaurer une base de données MySQL

Après avoir extrait le dump SQL via restic :

```bash
# Copier le dump dans le pod MySQL
kubectl --context production cp /tmp/restore/pre-backup/dump.sql \
  controller-mysql-operator/mysql-version-8-lts-0:/tmp/dump.sql

# Importer le dump
kubectl --context production exec -n controller-mysql-operator mysql-version-8-lts-0 -- \
  mysqlsh --uri root@localhost --sql \
  -e "SOURCE /tmp/dump.sql"
```

---

## Restaurer des volumes (données fichiers)

Pour les applications comme WordPress ou Nextcloud :

```bash
# 1. Télécharger les données depuis Restic
restic restore latest --target /tmp/restore/

# 2. Copier dans le PVC via un pod temporaire
kubectl --context production run restore-helper \
  --image=busybox --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"wordpress-data"}}],"containers":[{"name":"restore-helper","image":"busybox","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}' \
  -n le-portail-wordpress

kubectl --context production cp /tmp/restore/data/ \
  le-portail-wordpress/restore-helper:/data/

kubectl --context production delete pod restore-helper -n le-portail-wordpress
```

---

## Importer depuis le-portail vers local ou production

Des tâches Taskfile dédiées existent pour les migrations de données :

```bash
# Importer depuis le-portail vers localhost
task "backup:import-from-le-portail-to-local"

# Importer depuis le-portail vers production
task "backup:import-from-le-portail-to-production"
```

---

## Vérifier l'intégrité d'un dépôt

```bash
# Vérification complète (lecture de tous les blocs)
restic check --read-data

# Vérification rapide (métadonnées uniquement)
restic check
```

!!! warning "Vérification régulière"
    K8up déclenche automatiquement une vérification après chaque sauvegarde (`check.schedule`). En cas de doute sur l'intégrité, exécuter `restic check --read-data` manuellement.
