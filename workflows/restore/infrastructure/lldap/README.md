# Restauration de lldap

Workflow Argo de restauration de l'annuaire lldap, pendant de ceux des
applications de tenants (`workflows/restore/applications/*`).

```bash
# dernier snapshot du dépôt
argo submit --context admin@<cluster> -n controller-directory \
  --from workflowtemplate/restore

# snapshot imposé, et/ou dépôt d'un autre cluster
argo submit --context admin@<cluster> -n controller-directory \
  --from workflowtemplate/restore \
  -p snapshot-data-id=87eefc09 \
  -p source-bucket=alter-it-infra02-backup-controller-directory
```

## Pourquoi il ne ressemble pas à celui de grist

**Il n'utilise pas `Restore` de k8up.** `controller-directory` applique
PodSecurity `restricted`, là où les namespaces de tenants n'ont aucun label. Or
`Restore` n'expose qu'un `podSecurityContext` de pod : rien ne permet de régler
le `securityContext` du conteneur, et le Job généré est refusé à l'admission.
Le workflow appelle donc restic lui-même, dans un pod qu'il maîtrise. C'est la
même limite que celle déjà documentée dans `components/backup/schedule.yaml`.

**Il ne restaure pas un volume.** lldap n'est pas sauvegardé au niveau fichier :
son `PreBackupPod` produit un instantané SQLite cohérent (`.backup`) poussé sur
stdout. Le snapshot ne contient donc qu'un fichier, et restaurer veut dire
**remplacer `users.db`**.

La bascule vérifie le dump avant d'écraser quoi que ce soit (`integrity_check`,
puis présence d'au moins un compte), conserve l'ancienne base en `.bak`, et
supprime les `-wal` / `-shm` / `-journal`, qui décrivent la base précédente et
seraient rejoués à tort sur la nouvelle.

## ⚠ Le nom du bucket ne suit pas la formule

Trois nommages coexistent aujourd'hui, et deux ne désignent rien :

| Origine | Nom attendu | Existe ? |
|---|---|---|
| `components/backup/schedule.yaml` (`${owner}-${cluster}-backup-${tenant}-${application}`) | `alter-it-infra01-backup-controller-lldap` | **non** |
| `infra02/s3.tf` (`backup_tenants = { controller = ["lldap"] }`) | `alter-it-infra02-backup-controller-lldap` | **non** |
| bucket réellement provisionné | `alter-it-infra02-backup-controller-directory` | oui |

Conséquence directe : **les sauvegardes de lldap échouent sur infra01**, le
Schedule pointant vers un bucket inexistant. Et le seul snapshot disponible
(`/controller-directory-lldap-dump.sqlite3`) vit dans le dépôt `-directory`,
d'où le paramètre `source-bucket` de ce workflow.

À trancher : soit aligner `s3.tf` et le Schedule sur `controller-directory`,
soit créer le bucket `controller-lldap` et migrer le dépôt existant. Tant que
ce n'est pas fait, la restauration exige de passer `source-bucket` à la main.
