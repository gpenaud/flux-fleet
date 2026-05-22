# ovh-consumer-keys

Outil en ligne de commande pour générer des **consumer keys OVH** à partir d'un fichier YAML, sans passer par l'interface web.

Conçu pour le cas d'usage **cert-manager + DNS-01 OVH** sur un cluster k8s multi-tenant, avec deux stratégies :

- **`per-domain`** : un consumer key séparé par domaine (isolation forte, recommandé).
- **`all-in-one`** : un seul consumer key couvrant tous les domaines (simple à gérer).

## Prérequis

1. Une application OVH créée sur https://eu.api.ovh.com/createApp/. Tu récupères :
   - `application_key`
   - `application_secret` (pas utilisée par cet outil, mais à conserver pour cert-manager).

2. Go 1.22+ pour compiler.

## Build

```bash
git clone <repo>
cd ovh-consumer-keys
go build -o ovh-consumer-keys .
```

## Configuration

Copie `config.example.yaml` en `config.yaml` et adapte la liste des domaines.

Les permissions par défaut sont celles requises par **cert-manager DNS-01** :

```yaml
permissions:
  - { method: GET,    path: "/domain/zone/{domain}" }
  - { method: GET,    path: "/domain/zone/{domain}/record" }
  - { method: GET,    path: "/domain/zone/{domain}/record/*" }
  - { method: POST,   path: "/domain/zone/{domain}/record" }
  - { method: DELETE, path: "/domain/zone/{domain}/record/*" }
  - { method: POST,   path: "/domain/zone/{domain}/refresh" }
```

Le placeholder `{domain}` est remplacé par chaque nom de domaine de la section `domains`.

## Usage

```bash
# Mode "un token par domaine" (isolation forte)
export OVH_APPLICATION_KEY="ton_application_key"
./ovh-consumer-keys -config config.yaml -mode per-domain -output keys.yaml

# Mode "un seul token pour tout" (simple à gérer)
./ovh-consumer-keys -config config.yaml -mode all-in-one -output keys.yaml

# Sortie en JSON au lieu de YAML
./ovh-consumer-keys -config config.yaml -format json -output keys.json

# Sortie sur stdout
./ovh-consumer-keys -config config.yaml -output -
```

## Flags

| Flag | Défaut | Description |
|------|--------|-------------|
| `-config` | `config.yaml` | Chemin du fichier de config YAML |
| `-mode` | `per-domain` | `per-domain` ou `all-in-one` |
| `-output` | `-` (stdout) | Chemin du fichier de sortie |
| `-format` | `yaml` | `yaml` ou `json` |

## Étape de validation (manuelle)

Pour chaque consumer key généré, OVH renvoie une `validation_url`.
**Tu dois ouvrir cette URL dans un navigateur logué sur ton compte OVH** et cliquer "Autoriser".
Tant que ce n'est pas fait, le consumer key reste en état `pendingValidation` et est inutilisable.

C'est le seul moment où une action manuelle est requise. Tu peux scripter l'ouverture en série :

```bash
yq '.results[].validation_url' keys.yaml | xargs -n1 xdg-open
```

## Sécurité

- Le fichier de sortie contient des secrets (`consumer_key`). Permissions `0600` appliquées automatiquement.
- Stocker les keys via SOPS pour intégration GitOps.
- Préférer `OVH_APPLICATION_KEY` en variable d'environnement plutôt que dans `config.yaml`.

## Limitations

- L'API OVH ne permet pas de modifier les rules d'un consumer key existant. Pour ajouter un domaine, regénérer le token concerné.
- L'étape de validation par navigateur est imposée par OVH, pas contournable en pur API.
- Pour une gestion réellement headless et mutable, considérer OAuth2 client_credentials d'OVH (non couvert par cet outil).
