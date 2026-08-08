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

## Le nom du bucket

Le suffixe du dépôt est le **namespace** — `controller-directory` — et non
`${tenant}-${application}`, qui donnerait `controller-lldap`. lldap est le seul
service sauvegardé de ce namespace, et c'est sous ce nom que le dépôt restic
existe.

Trois endroits doivent rester alignés :

| Fichier | Rôle |
|---|---|
| `flux-fleet/infrastructure/directory/lldap/components/backup/schedule.yaml` | où k8up écrit |
| `infrastructure-as-code/infrastructure/s3-buckets/locals.tf` | crée le bucket infra01 |
| `infrastructure-as-code/infrastructure/infra02/s3.tf` | crée le bucket infra02 |

Un décalage ne casse rien à l'`apply` : c'est k8up qui échouera, la nuit, sur un
bucket absent. C'est précisément ce qui s'est produit — le Schedule dérivait le
suffixe de `${application}` et visait `controller-lldap`, qui n'a jamais existé,
tandis que les sauvegardes réelles vivaient dans `controller-directory`.

Le dépôt d'infra01 étant neuf, restaurer depuis l'historique d'infra02 demande
encore de désigner son bucket :

```bash
task infra01:restore:infrastructure:lldap \
  SOURCE_BUCKET=alter-it-infra02-backup-controller-directory
```
