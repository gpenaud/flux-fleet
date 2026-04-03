# Gestion des secrets

Les secrets sont chiffrés dans Git avec **SOPS + age** et déchiffrés à la volée par Flux au moment de l'application.

---

## Clés age par environnement

Deux clés age sont utilisées, une par cluster :

| Environnement | Clé age (publique) |
|---------------|-------------------|
| `localhost`   | `age126qcg2kfl…` |
| `production`  | `age1jhryunagv…` |

Les secrets `base/` (partagés) sont chiffrés avec les **deux clés** (key_groups), afin d'être déchiffrables par les deux clusters.

---

## Règles de chiffrement (`.sops.yaml`)

```yaml
creation_rules:
  # Secrets d'environnement localhost
  - path_regex: .*localhost.*/secrets\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age126qcg2kfl...

  # Secrets d'environnement production
  - path_regex: .*production.*/secrets\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1jhryunagv...

  # Secrets partagés (base/) : les deux clés
  - path_regex: .*base.*/secrets/.*\.yaml$
    encrypted_regex: ^(data|stringData)$
    key_groups:
      - age:
          - age126qcg2kfl...
          - age1jhryunagv...

  # Secrets des tasks Taskfile
  - path_regex: tasks/.*\.yaml$
    age: age126qcg2kfl...
```

!!! tip "Seuls les champs `data` et `stringData` sont chiffrés"
    Les métadonnées Kubernetes (nom, namespace, labels) restent en clair, ce qui permet de naviguer dans le dépôt sans clé de déchiffrement.

---

## Déchiffrement par Flux

Chaque Kustomization qui manipule des secrets déclare le provider SOPS :

```yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age-private-key
```

Le secret `sops-age-private-key` contient la clé privée age et est créé manuellement lors du bootstrap du cluster.

---

## Chiffrer / déchiffrer un secret

=== "Chiffrer"

    ```bash
    # Chiffrer un nouveau secret (la règle .sops.yaml s'applique automatiquement)
    sops --encrypt secrets.yaml > secrets.enc.yaml

    # Ou éditer directement un secret existant
    sops secrets.enc.yaml
    ```

=== "Déchiffrer (lecture seule)"

    ```bash
    sops --decrypt secrets.enc.yaml
    ```

=== "Via Taskfile"

    ```bash
    task cluster:encrypt
    ```

---

## Réplication des secrets (Reflector)

Le contrôleur [Reflector](https://github.com/emberstack/kubernetes-reflector) réplique certains secrets entre namespaces. Exemple : le secret `mysql-operator` est annoté pour être répliqué dans tous les namespaces qui en ont besoin.

```yaml
metadata:
  annotations:
    reflector.v1.k8s.emberstack.com/reflection-allowed: "true"
    reflector.v1.k8s.emberstack.com/reflection-auto-enabled: "true"
```

!!! warning "Ne jamais committer de secrets en clair"
    Les fichiers `secrets.yaml` (non chiffrés) sont dans `.gitignore`. Seuls les fichiers `secrets.enc.yaml` doivent être committés.
