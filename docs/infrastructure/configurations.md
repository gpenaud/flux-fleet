# Configurations d'infrastructure

Les configurations sont des ressources Kubernetes cluster-wide qui dépendent des contrôleurs. Elles sont déployées après `infrastructure-controllers`.

---

## ClusterIssuers

Deux `ClusterIssuer` cert-manager sont définis pour Let's Encrypt :

### letsencrypt-staging

Utiliser pour tester la configuration TLS sans consommer le quota Let's Encrypt production (limite : 5 certificats / domaine / semaine).

```bash
# Annoter une ressource pour utiliser le staging
cert-manager.io/cluster-issuer: letsencrypt-staging
```

### letsencrypt-production

Émet des certificats valides. Le challenge DNS-01 est résolu via le webhook OVH.

```yaml
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops.gpenaud@gmail.com
    solvers:
      # leportail.org et labergeronnette.org
      - dns01:
          webhook:
            solverName: ovh
            config:
              endpoint: ovh-eu
              applicationKeyRef:
                name: dns-ovh
                key: applicationKey
        selector:
          dnsZones:
            - leportail.org
            - labergeronnette.org

      # fermedujointout.fr (credentials séparés)
      - dns01:
          webhook:
            solverName: ovh
            config:
              applicationKeyRef:
                name: dns-ovh-ferme-du-jointout
                key: applicationKey
        selector:
          dnsZones:
            - fermedujointout.fr
```

!!! tip "Passer en production"
    Changer l'annotation `cert-manager.io/cluster-issuer: letsencrypt-staging` en `letsencrypt-production` et supprimer le secret du certificat pour forcer le renouvellement.

---

## MySQL InnoDB Cluster

Un seul cluster MySQL est partagé par toutes les applications en production.

```yaml
kind: InnoDBCluster
metadata:
  name: mysql-version-8-lts
  namespace: controller-mysql-operator
spec:
  secretName: mysql-operator   # mot de passe root (SOPS chiffré)
  instances: 1
  version: "8.4.3"
  edition: community
  router:
    instances: 1
  tlsUseSelfSigned: true
```

**Hostname interne** (utilisé dans les `backupCommand` K8up) :
```
mysql-version-8-lts.controller-mysql-operator.svc.cluster.local
```

**Accéder au cluster MySQL** :
```bash
kubectl --context production exec -it -n controller-mysql-operator \
  mysql-version-8-lts-0 -- mysqlsh --uri root@localhost
```

---

## Configurations localhost

En localhost, les configurations sont différentes :

### mkcert ClusterIssuer

Émet des certificats locaux auto-signés via `mkcert` sans passer par ACME :

```yaml
# infrastructure/configurations/localhost/mkcert/cluster-issuer.yaml
kind: ClusterIssuer
metadata:
  name: mkcert
spec:
  ca:
    secretName: mkcert-ca
```

### Traefik Dashboard (localhost)

IngressRoute et Certificate pour accéder au dashboard Traefik localement.

---

## Traefik Dashboard (production)

Un patch est appliqué par le cluster production pour personnaliser le hostname du dashboard :

```yaml
# clusters/production/infrastructure.yaml
patches:
  - target:
      kind: Certificate
      name: traefik-dashboard
    patch: |
      - op: replace
        path: /spec/dnsNames/0
        value: traefik.gpenaud.production
  - target:
      kind: IngressRoute
      name: traefik-dashboard
    patch: |
      - op: replace
        path: /spec/routes/0/match
        value: traefik.gpenaud.production
```
