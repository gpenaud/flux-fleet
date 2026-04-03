# Ingress — Traefik

**Traefik** est l'ingress controller utilisé sur les deux clusters. Il route le trafic HTTP/HTTPS vers les applications en fonction du hostname.

---

## Configuration production

```yaml
# infrastructure/controllers/production/traefik.yaml
values:
  api:
    dashboard: true
    insecure: true
  logs:
    general:
      level: DEBUG
    access:
      enabled: true
  providers:
    kubernetesCRD:
      allowCrossNamespace: true    # Permet les IngressRoutes multi-namespaces
  ports:
    web:
      http:
        redirections:
          entryPoint:
            to: websecure
            scheme: https
            permanent: true        # Redirection 301 HTTP → HTTPS
```

- **Version** : `39.0.0` (OCIRepository `ghcr.io/traefik/helm/traefik`)
- **Namespace** : `controller-traefik`

---

## Types de ressources Traefik utilisés

### IngressRoute

Ressource CRD Traefik pour router le trafic avec TLS :

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: mon-app
  namespace: mon-namespace
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`mon-app.leportail.org`)
      kind: Rule
      services:
        - name: mon-app
          port: 80
  tls:
    secretName: mon-app-tls
```

### Middleware

Utilisé notamment pour Grist (redirections, headers) :

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-to-https
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

---

## allowCrossNamespace

La configuration `allowCrossNamespace: true` permet à des `IngressRoute` dans des namespaces tenant de référencer des services dans d'autres namespaces. C'est nécessaire pour l'architecture multi-tenant où Traefik est dans `controller-traefik` mais route vers des services dans `le-portail-wordpress`, etc.

---

## Dashboard Traefik

| Environnement | URL | TLS |
|---------------|-----|-----|
| localhost | `traefik.gpenaud.localhost` | mkcert |
| production | `traefik.gpenaud.production` | cert-manager (patch cluster) |

Accéder au dashboard :
```bash
# Port-forward si l'IngressRoute n'est pas accessible
kubectl --context production port-forward -n controller-traefik svc/traefik 9000:9000
# → http://localhost:9000/dashboard/
```

---

## Domaines des applications

| Domaine | Tenant |
|---------|--------|
| `*.leportail.org` | le-portail |
| `*.labergeronnette.org` | la-bergeronnette |
| `*.fermedujointout.fr` | ferme-du-jointout |
| `longhorn.leportail.org` | Infrastructure (Longhorn UI) |

!!! info "Certificats wildcard"
    Les certificats sont émis par cert-manager avec DNS-01 (OVH webhook), ce qui permet des certificats wildcard `*.domaine.tld` sans nécessiter d'exposition du cluster sur le port 80.
