# https

cloudflare handles https itself. no need to configure it manually but, if needed:

As described [here](https://rancher.com/docs/k3s/latest/en/helm/) all manifests created here `/var/lib/rancher/k3s/server/manifests` are automatically deployed.

Based on that lets create yaml for [cert-manager](https://cert-manager.io/docs/installation/helm/):

```sh
sudo -i
cd /var/lib/rancher/k3s/server/manifests
vim cert-manager.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: cert-manager
  namespace: kube-system
spec:
  chart: cert-manager
  targetNamespace: cert-manager
  repo: https://charts.jetstack.io
  set:
    installCRDs: 'true'
---
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: cert-manager
type: Opaque
stringData:
  api-token: ## follow readme.md##safety-of-credentials or this https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/ ##
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: 'email'
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - dns01:
          cloudflare:
            email: my-cloudflare-acc@example.com
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
```

```sh
sudo -i
cd /var/lib/rancher/k3s/server/manifests
vim sample-app.yaml
```

insert:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: example-com
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: simple-rest-golang-deployment
  namespace: example-com
spec:
  replicas: 2
  selector:
    matchLabels:
      app: simple-rest-golang
  template:
    metadata:
      labels:
        app: simple-rest-golang
    spec:
      containers:
        - name: simple-rest-golang
          image: nginx:1.14.2
          ports:
            - containerPort: 80
          imagePullPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  name: simple-rest-golang-service
  namespace: example-com
spec:
  ports:
    - port: 80
      targetPort: 80
      name: tcp
  selector:
    app: simple-rest-golang
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-rest-golang-ingress
  namespace: example-com
  annotations:
    kubernetes.io/ingress.class: 'traefik'
    cert-manager.io/cluster-issuer: 'letsencrypt'
spec:
  tls:
    - secretName: cloudflare-api-token-secret
      hosts:
        - www.example.com
        - example.com
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: simple-rest-golang-service
                port:
                  number: 80
```
