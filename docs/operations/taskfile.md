# Référence Taskfile

Le `Taskfile.yml` à la racine du dépôt orchestre toutes les opérations courantes via [Task](https://taskfile.dev).

---

## Structure

```
Taskfile.yml                               ← Point d'entrée, inclut tous les sous-fichiers
tools/tasks/
├── cluster.yml                            ← Gestion du cluster
├── infrastructure.yml                     ← Snapshots VPS
├── reconcile.yml                          ← Réconciliation Flux
├── database.yml                           ← Opérations base de données
├── backup.yml                             ← Sauvegardes K8up manuelles
└── backup/
    ├── from-local-to-s3.yml               ← Export S3
    ├── import-from-le-portail-to-local.yml
    └── import-from-le-portail-to-production.yml
```

---

## cluster:*

| Tâche | Description |
|-------|-------------|
| `task cluster:recreate:flux` | Redéploie k3s avec Flux via Ansible |
| `task cluster:recreate:lab` | Redéploie k3s en mode lab via Ansible |
| `task cluster:encrypt` | Chiffre tous les `secrets.yaml` modifiés avec SOPS |

### Détail — cluster:encrypt

Cette tâche intelligente :
1. Parcourt tous les `secrets.yaml` du dépôt
2. Si pas encore chiffré → chiffre vers `.enc.yaml`
3. Si jamais commité → rechiffre par sécurité
4. Si contenu identique au dernier commit → ignore
5. Si contenu modifié → rechiffre

```bash
task cluster:encrypt
```

---

## infrastructure:*

| Tâche | Description |
|-------|-------------|
| `task infrastructure:vps:snapshot` | Crée un snapshot du VPS `srv1515851.hstgr.cloud` |
| `task infrastructure:vps:snapshot:old-vm` | Crée un snapshot de l'ancien VPS |

!!! warning "Confirmation requise"
    La tâche snapshot demande de taper `je confirme` pour éviter d'écraser accidentellement un snapshot existant.

---

## reconcile:*

| Tâche | Description |
|-------|-------------|
| `task reconcile:source` | Réconcilie la source Git flux-system |
| `task reconcile:kustomization:infrastructure` | Réconcilie controllers + configurations |
| `task reconcile:kustomization:infrastructure:controllers` | Réconcilie controllers uniquement |
| `task reconcile:kustomization:infrastructure:configurations` | Réconcilie configurations uniquement |
| `task reconcile:kustomization:applications` | Réconcilie les applications |

Voir [Réconciliation](reconcile.md) pour les détails.

---

## backup:k8up:*

Déclenche une sauvegarde K8up one-shot et attend sa complétion.

| Tâche | Tenant / Service |
|-------|-----------------|
| `task backup:k8up:la-bergeronnette:wordpress-site` | la-bergeronnette / WordPress |
| `task backup:k8up:le-portail:wordpress-site` | le-portail / WordPress |
| `task backup:k8up:le-portail:wordpress-epilibres` | le-portail / WordPress Épi-Libres |
| `task backup:k8up:le-portail:dolibarr` | le-portail / Dolibarr |
| `task backup:k8up:le-portail:alterconso` | le-portail / Alterconso |
| `task backup:k8up:le-portail:grist` | le-portail / Grist |
| `task backup:k8up:ferme-du-jointout:wordpress-site` | ferme-du-jointout / WordPress |
| `task backup:k8up:ferme-du-jointout:dolibarr` | ferme-du-jointout / Dolibarr |
| `task backup:k8up:ferme-du-jointout:nextcloud` | ferme-du-jointout / Nextcloud |

---

## backup:import-from-le-portail-to-*

Tâches de migration pour importer les données depuis l'environnement `le-portail` vers localhost ou production.

```bash
task "backup:import-from-le-portail-to-local"
task "backup:import-from-le-portail-to-production"
```

---

## backup:from-local-to-s3

Exporte les sauvegardes locales vers S3.

```bash
task "backup:from-local-to-s3"
```

---

## Lister toutes les tâches disponibles

```bash
task --list
```
