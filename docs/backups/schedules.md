# Planifications des sauvegardes

Chaque application dispose de sa propre ressource K8up `Schedule` avec une planification cron indépendante.

---

## Planification commune (WordPress, Dolibarr, Nextcloud)

| Opération | Cron | Description |
|-----------|------|-------------|
| `backup` | `0 21 1,15 * *` | 1er et 15 de chaque mois à 21h00 |
| `check` | `30 21 1,15 * *` | Vérification 30 min après le backup |
| `prune` | `0 22 1,15 * *` | Nettoyage 1h après le backup |

### Politique de rétention

```yaml
retention:
  keepWeekly: 8     # 8 sauvegardes hebdomadaires (~4 mois glissants)
  keepMonthly: 6    # 6 sauvegardes mensuelles (~6 mois)
```

---

## Récapitulatif par application

| Application | Tenant | Namespace | Bucket S3 |
|-------------|--------|-----------|-----------|
| WordPress | ferme-du-jointout | `ferme-du-jointout-wordpress` | `backup-srv1515851-ferme-du-jointout-wordpress-site` |
| WordPress | la-bergeronnette | `la-bergeronnette-wordpress` | `backup-srv1515851-la-bergeronnette-wordpress-site` |
| WordPress | le-portail | `le-portail-wordpress` | `backup-srv1515851-le-portail-wordpress-site` |
| WordPress Épi-Libres | le-portail | `le-portail-wordpress-epilibres` | `backup-srv1515851-le-portail-wordpress-epilibres` |
| Dolibarr | ferme-du-jointout | `ferme-du-jointout-dolibarr` | `backup-srv1515851-ferme-du-jointout-dolibarr` |
| Dolibarr | le-portail | `le-portail-dolibarr` | `backup-srv1515851-le-portail-dolibarr` |
| Nextcloud | ferme-du-jointout | `ferme-du-jointout-nextcloud` | `backup-srv1515851-ferme-du-jointout-nextcloud` |
| Grist | le-portail | `le-portail-grist` | `backup-srv1515851-le-portail-grist` |
| Alterconso | le-portail | `le-portail-alterconso` | `backup-srv1515851-le-portail-alterconso` |

---

## Déclencher une sauvegarde manuelle

La tâche Taskfile applique une ressource K8up `Backup` one-shot et attend sa complétion :

```bash
# Syntaxe générale
task backup:k8up:<tenant>:<service>

# Exemples
task backup:k8up:le-portail:wordpress-site
task backup:k8up:ferme-du-jointout:nextcloud
task backup:k8up:la-bergeronnette:wordpress-site
```

La tâche :
1. Applique un `Backup` CR dans le namespace cible
2. Attend la condition `Completed` (timeout 30 min)
3. Supprime le `Backup` CR après complétion

---

## Vérifier l'état des Schedules

```bash
# Lister tous les schedules K8up
kubectl --context production get schedules -A

# Détail d'un schedule
kubectl --context production -n le-portail-wordpress describe schedule wordpress

# Derniers jobs de sauvegarde
kubectl --context production get jobs -A -l k8up.io/owned-by=Schedule
```

---

## Limites des historiques de jobs

```yaml
failedJobsHistoryLimit: 2      # Conserve les 2 derniers jobs échoués
successfulJobsHistoryLimit: 3  # Conserve les 3 derniers jobs réussis
```
