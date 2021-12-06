This file is for historical purpose. At first I tried to prepare md file with snippets, but it started to be lot of text, so I decided to use ansible

# kubernetes-raspberry4b-v2

Well, I used [https://github.com/kubernetes-sigs/kubespray](kubespray) which is nice, but I would go with something smaller. Also I did not care about security etc. And I made some mess in cluster for sure.

I picked [k3s](https://k3s.io/) distribution and moved my domainnameservers to cloudflare, which even in free plan gives more tools than ovh - for example no worries about https.

## Targets

so with migration to k3s I hope that:

- [ ] [Prepare raspberry](#prepare-raspberry)
- [ ] [Install k3s](#install-k3s)
- [ ] [lens](#lens)
- [ ] [safety of credentials](#safety-of-credentials)
- [ ] [Prevent exposing wildcard in cloudflare](#prevent-exposing-wildcard-in-cloudflare)
- [ ] [www to non www in ingress-and-drop-traefik](#www-to-non-www-in-ingress-and-drop-traefik)
- [ ] [metrics server works](#metric-server-works)
- [ ] [monitoring](#monitoring)
- [ ] [elk stack](#elk-stack)
- [ ] [auto updates](#auto-updates)
- [ ] [backup](#backup)
- [ ] [access to kubectl outside local network](#access-to-kubectl-outside-local-network)
- [ ] [sample application](#sample-application)
- [ ] [Deploy sample application on githubactions](#deploy-sample-application-on-githubactions)
- [ ] [security](#security)
- [ ] [fan](#fan)

## Plan

### prepare raspberry

- Install ubuntu server from raspberry image writer
- repeat code below, it's from [Prepare Raspberry](https://github.com/morriq/kubernetes-raspberry4b/blob/master/README.md):

```sh
export HOME_CLUSTER={ip}
ssh ubuntu@$HOME_CLUSTER

sudo vim /etc/netplan/50-cloud-init.yaml
network:
    ethernets:
        eth0:
            dhcp4: false
            addresses:
                - 192.168.0.233/14
            gateway4: 192.168.0.1
            nameservers:
                addresses: [8.8.8.8, 8.8.4.4]
    version: 2

sudo vim /boot/firmware/cmdline.txt
append: >>> cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
sudo apt-get update -y && sudo apt-get --with-new-pkgs upgrade -y

sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
>>>> Unattended-Upgrade::Automatic-Reboot "true";
# ...and so on.
sudo reboot
```

### install k3s

Being still on cluster:

```sh
curl -sfL https://get.k3s.io | sh -s - --node-name=node-1
```

After some seconds, entrance on ip of node will give you 404.

Entrance on domain in cloudflare would give nginx 404 too, if not - make sure 443, 80 are exposed (and only these ports) from local network to the world and cloudflare cname points to IP.

### lens

Download https://k8slens.dev/.

copy `/etc/rancher/k3s/k3s.yaml` as described [here](https://rancher.com/docs/k3s/latest/en/cluster-access/#accessing-the-cluster-from-outside-with-kubectl)

### safety of credentials

I use [this](https://github.com/external-secrets/kubernetes-external-secrets). Create account in IAC and execute:

```sh
sudo bash -c 'cat <<EOF >>/var/lib/rancher/k3s/server/manifests/aws-secrets.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
---
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: external-secrets
data:
  ACCESS_KEY: XXX
  SECRET_KEY: XXX
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: external-secrets
  namespace: kube-system
spec:
  targetNamespace: external-secrets
  chart: kubernetes-external-secrets
  repo: https://external-secrets.github.io/kubernetes-external-secrets/
  valuesContent: |-
    env:
      AWS_REGION: eu-central-1
    envVarsFromSecret:
      AWS_ACCESS_KEY_ID:
        secretKeyRef: aws-credentials
        key: ACCESS_KEY
      AWS_SECRET_ACCESS_KEY:
        secretKeyRef: aws-credentials
        key: SECRET_KEY
EOF'
```

### Prevent exposing wildcard in cloudflare

why? because:

<img width="914" alt="Screenshot 2021-08-01 at 16 07 33" src="https://user-images.githubusercontent.com/2962338/127773847-9cc25e6e-cddf-4983-8fef-62861832f7a5.png">

**Remove every \* CNAME records**

Going to install external-dns. It would add records to zones in cloudflare, even subdomain which exist in ingress definition only

Execute code below, it's created based [external-dns RBAC](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md#manifest-for-clusters-with-rbac-enabled)

Keep it in `default` namespace, use `CF_API_TOKEN`. In case of issues visit [FAQ](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/faq.md)

```sh
sudo bash -c 'cat <<EOF >>/var/lib/rancher/k3s/server/manifests/external-dns.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
  - apiGroups: ['']
    resources: ['services', 'endpoints', 'pods']
    verbs: ['get', 'watch', 'list']
  - apiGroups: ['extensions', 'networking.k8s.io']
    resources: ['ingresses']
    verbs: ['get', 'watch', 'list']
  - apiGroups: ['']
    resources: ['nodes']
    verbs: ['list', 'watch']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
  - kind: ServiceAccount
    name: external-dns
    namespace: default
---
apiVersion: "kubernetes-client.io/v1"
kind: ExternalSecret
metadata:
  name: cloudflare-secret
spec:
  backendType: secretsManager
  data:
    - key: home-cluster
      property: CLOUDFLARE_API_TOKEN
      name: CF_API_TOKEN
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: k8s.gcr.io/external-dns/external-dns:v0.7.6
          args:
            - --source=ingress # service is also possible
            - --provider=cloudflare
            - --cloudflare-proxied # (optional) enable the proxy feature of Cloudflare (DDOS protection, CDN...)
          envFrom:
            - secretRef:
                name: cloudflare-secret
EOF'
```

### www to non www in ingress and drop traefik

cloudflare wants 10$ monthly to handle www.subdomain.domain and calls it "two level subdomain", so I'm going to handle only www.domain.

... and traefik - shipped with k3s - has really poor documentation, resources in google are outdated and honestly I spent many hours to find how to make redirect www to non www.

[Here](https://github.com/k3s-io/k3s/issues/817) is nice discussion. It leads to [this PR](https://github.com/k3s-io/k3s/pull/1466) and [this PR](https://github.com/k3s-io/k3s/pull/1519/files)

```sh
curl -sfL https://get.k3s.io | sh -s - --disable=traefik --node-name=node-1

sudo wget https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-3.35.0/ingress-nginx-3.35.0.tgz -P /var/lib/rancher/k3s/server/static/charts

sudo bash -c 'cat <<EOF >>/var/lib/rancher/k3s/server/manifests/nginx.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: nginx-ingress
  namespace: kube-system
spec:
  chart: https://%{KUBERNETES_API}%/static/charts/ingress-nginx-3.35.0.tgz
  targetNamespace: kube-system
  set:
    rbac.create: 'true'
    controller.service.enableHttps: 'true'
    controller.metrics.enabled: 'true'
    controller.publishService.enabled: 'true'
EOF'
```

Redirect from www to non-www comes with annotation `nginx.ingress.kubernetes.io/from-to-www-redirect: 'true'` and that's it!
traefik >10hours without success, nginx with installation <1h

### metrics server works

Got issue?

> unable to fetch node metrics for node "ubuntu": no metrics known for node "ubuntu"

based on [this comment](https://github.com/kubernetes-sigs/metrics-server/issues/237#issuecomment-541697966):

```sh
sudo vim /var/lib/rancher/k3s/server/manifests/metrics_server/metrics-server-deployment.yaml
```

add after line `image: rancher/metrics-server:xxx`:

```sh
command:
    - /metrics-server
    - --kubelet-preferred-address-types=InternalIP
    - --kubelet-insecure-tls
    - --v=2
```

### monitoring

means prometheus which is required in [Lens](https://k8slens.dev/).

```sh
sudo git clone https://github.com/prometheus-operator/kube-prometheus.git /var/lib/rancher/k3s/server/static/charts
sudo kubectl create namespace monitoring
sudo kubectl create -f manifests/setup
until sudo kubectl get servicemonitors --all-namespaces ; do date; sleep 1; echo ""; done
sudo kubectl create -f manifests/
```

All access is described [here](https://github.com/prometheus-operator/kube-prometheus#quickstart).
Whether after deploy not all pods are running - for example alert manager can't access 9093, execute:

```sh
sudo kubectl edit -n monitoring statefulset.apps/alertmanager-main

# find spec.containers and at spec level add:
hostNetwork: true
```

Solution above is described [here](https://github.com/prometheus-operator/kube-prometheus/issues/653#issuecomment-677758822), how to append hostNetwork: [here](https://stackoverflow.com/questions/49859408/is-it-possible-to-set-hostname-to-pod-when-using-hostnetwork-in-kubernetes).

### elk stack

follow [quickstart](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-quickstart.html):

```sh
sudo mkdir /var/lib/rancher/k3s/server/static/charts/eck
sudo wget https://download.elastic.co/downloads/eck/1.7.0/crds.yaml -P /var/lib/rancher/k3s/server/static/charts/eck
sudo wget https://download.elastic.co/downloads/eck/1.7.0/operator.yaml -P /var/lib/rancher/k3s/server/static/charts/eck

sudo kubectl create -f /var/lib/rancher/k3s/server/static/charts/eck/crds.yaml
sudo kubectl apply -f /var/lib/rancher/k3s/server/static/charts/eck/operator.yaml

sudo mkdir /var/lib/rancher/k3s/server/manifests/elk
sudo bash -c 'cat <<EOF >>elasticsearch.yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
spec:
  http:
    service:
      spec:
        type: NodePort
        ports:
          - port: 9200
            targetPort: 9200
            protocol: TCP
            nodePort: 31920
  version: 7.14.0
  nodeSets:
    - name: default
      count: 1
      podTemplate:
        spec:
          initContainers:
            - name: sysctl
              securityContext:
                privileged: true
              command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
EOF

sudo cat <<EOF >>kibana.yaml
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: quickstart
spec:
  version: 7.14.0
  count: 1
  elasticsearchRef:
    name: quickstart
EOF'
```

and next https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-beat.html:

```sh

sudo bash -c 'cat <<EOF >>filebeat.yaml
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: quickstart
spec:
  type: filebeat
  version: 7.14.0
  elasticsearchRef:
    name: quickstart
  config:
    filebeat.inputs:
    - type: container
      paths:
      - /var/log/containers/*.log
  daemonSet:
    podTemplate:
      spec:
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true
        securityContext:
          runAsUser: 0
        containers:
        - name: filebeat
          volumeMounts:
          - name: varlogcontainers
            mountPath: /var/log/containers
          - name: varlogpods
            mountPath: /var/log/pods
          - name: varlibdockercontainers
            mountPath: /var/lib/docker/containers
        volumes:
        - name: varlogcontainers
          hostPath:
            path: /var/log/containers
        - name: varlogpods
          hostPath:
            path: /var/log/pods
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
EOF'
```

access to kibana is

login elastic
password PASSWORD=$(kubectl get secret quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')

After all that set remove policy: https://www.cloudsavvyit.com/7152/how-to-rotate-and-delete-old-elasticsearch-records-after-a-month/

### auto updates

following https://rancher.com/docs/k3s/latest/en/upgrades/automated/

```sh
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/download/v0.6.2/system-upgrade-controller.yaml

sudo bash -c 'cat <<EOF >>/var/lib/rancher/k3s/server/manifests/auto-updates.yaml
# Server plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: server-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/master
      operator: In
      values:
      - "true"
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/k3s-upgrade
  channel: https://update.k3s.io/v1-release/channels/stable
---
# Agent plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: agent-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  cordon: true
  nodeSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/master
      operator: DoesNotExist
  prepare:
    args:
    - prepare
    - server-plan
    image: rancher/k3s-upgrade:v1.17.4-k3s1
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/k3s-upgrade
  channel: https://update.k3s.io/v1-release/channels/stable
EOF'
```

### backup

k3s makes backup automatically but local. It has functionality to store it in [s3](https://rancher.com/docs/k3s/latest/en/backup-restore/#s3-compatible-api-support). Create in IAC user and execute:

```sh
curl -sfL https://get.k3s.io | sh -s - --node-name=node-1 server --disable=traefik --etcd-s3 --etcd-s3-region=eu-central-1 --etcd-s3-bucket=morriq-homecluster --etcd-s3-access-key=XXXX --etcd-s3-secret-key=XXX --etcd-snapshot-schedule-cron='0 */6 * * *'
```

And check if its ok:

```sh
cat /etc/systemd/system/k3s.service
```

### access to kubectl outside local network

Meaning router with VPN. I chosed `TP-LINK Archer C6` which has posibility to use OpenVPN.

My final network

Connect Box(Bridge mode) -> Archer router

netis router - used to connect raspberries with network - connected via wifi with archer, working in bridge mode:

![Untitled](https://user-images.githubusercontent.com/2962338/128087482-8aaafb69-90c7-42cb-8191-b0ab9c8feeab.jpg)

![Untitled](https://user-images.githubusercontent.com/2962338/128087573-0fe5f924-d376-446c-9a36-76f98f5401f2.jpg)

since Archer is main router now, I set in ACP -> Nat Forwarding -> Virtual servers ports 80, 443. In cloudflare changed target ip.

Setup VPN in Archer: VPN Server -> Open VPN:

<img width="575" alt="Screenshot 2021-08-05 at 18 19 32" src="https://user-images.githubusercontent.com/2962338/128385220-892de34c-a837-43de-8b26-d50704c7924a.png">

generate key, and export it. From now I can use this key in https://openvpn.net/vpn-client/

### sample application

```sh
sudo cat <<EOF >>/var/lib/rancher/k3s/server/manifests/sample-app.yaml
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
    external-dns.alpha.kubernetes.io/target: { NETWORK IP }
    external-dns.alpha.kubernetes.io/hostname: example.com,www.example.com
spec:
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
EOF
```

### Deploy sample application on githubactions

Here are ready to use Dockerfiles: https://github.com/myoung34/docker-github-actions-runner

Dockerfile for github runner (run it on own computer):

```Dockerfile
version: '3.4'
services:
  worker:
    image: myoung34/github-runner:latest
    environment:
      ORG_NAME: dawid-winiarczyk
      RUNNER_NAME: example-name
      RUNNER_TOKEN: xxxxx
      RUNNER_WORKDIR: /tmp/runner/work
      RUNNER_SCOPE: 'org'
      LABELS: linux,x64,gpu
    security_opt:
      # needed on SELinux systems to allow docker container to manage other docker containers
      - label:disable
    volumes:
      - '/var/run/docker.sock:/var/run/docker.sock'
      - '/tmp/runner:/tmp/runner'
```

.github/deploy.yaml:

```yaml
name: Deploy

on:
  push:
    branches: [master]

jobs:
  publish:
    runs-on: [self-hosted]

    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Cache Docker layers
        uses: actions/cache@v2
        with:
          path: /tmp/.buildx-cache
          key: ${{ runner.os }}-buildx-${{ github.sha }}
          restore-keys: |
            ${{ runner.os }}-buildx-
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v1
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v1
      - name: Login to DockerHub
        uses: docker/login-action@v1
        with:
          username: username
          password: '${{ secrets.GHCR_TOKEN }}'
          registry: ghcr.io

      - name: Build and push
        uses: docker/build-push-action@v2
        timeout-minutes: 300
        with:
          context: FOLDER
          file: FOLDER/Dockerfile
          platforms: linux/arm64
          push: true
          tags: |
            ghcr.io/ORGANISATION/REPOSITORY/IMAGE:commit-${{ github.sha }}
            ghcr.io/ORGANISATION/REPOSITORY/IMAGE:latest
          cache-from: type=local,src=/tmp/.buildx-cache
          cache-to: type=local,dest=/tmp/.buildx-cache,mode=max

  deploy:
    runs-on: [self-hosted]
    needs: publish
    timeout-minutes: 4

    steps:
      - uses: actions/checkout@v2

      - name: Resolve environment variables in k8s.yaml
        env:
          DOCKER_IMAGE: ghcr.io/<organisation>/<repository name>/<image name>:commit-${{ github.sha }}
        run: |
          envsubst < k8s.yaml > _k8s.yaml

      - name: Kubernetes set context
        uses: Azure/k8s-set-context@v1
        with:
          method: kubeconfig
          kubeconfig: ${{ secrets.KUBECONFIG }}

      - uses: Azure/k8s-deploy@v1
        with:
          manifests: |
            _k8s.yaml
```

lets create ${{ secrets.KUBECONFIG }}

```sh
kubectl create namespace example-com-at-gh
kubectl create serviceaccount -n example-com-at-gh github-example-project
kubectl create rolebinding -n example-com-at-gh github-example-project-editor --clusterrole=edit --serviceaccount=example-com-at-gh:github-example-project

# your server name goes here
server=https://localhost:8443
# the name of the secret containing the service account token goes here
name=default-token-sg96k

ca=$(kubectl get secret/$name -o jsonpath='{.data.ca\.crt}')
token=$(kubectl get secret/$name -o jsonpath='{.data.token}' | base64 --decode)
namespace=$(kubectl get secret/$name -o jsonpath='{.data.namespace}' | base64 --decode)

echo "
apiVersion: v1
kind: Config
clusters:
- name: default-cluster
  cluster:
    certificate-authority-data: ${ca}
    server: ${server}
contexts:
- name: default-context
  context:
    cluster: default-cluster
    namespace: default
    user: default-user
current-context: default-context
users:
- name: default-user
  user:
    token: ${token}
" > sa.kubeconfig
```

k8s.yaml:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: simple-rest-golang-deployment
  namespace: example-com-at-gh
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
  namespace: example-com-at-gh
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
  namespace: example-com-at-gh
  annotations:
    kubernetes.io/ingress.class: 'nginx'
    external-dns.alpha.kubernetes.io/target: { NETWORK IP }
    external-dns.alpha.kubernetes.io/hostname: example.com,www.example.com
spec:
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

### security

Worth reading: https://digitalis.io/blog/technology/k3s-lightweight-kubernetes-made-ready-for-production-part-2/

and https://digitalis.io/blog/kubernetes/k3s-lightweight-kubernetes-made-ready-for-production-part-3

Following https://rancher.com/docs/k3s/latest/en/security/:

- ensure protect-kernel-defaults is set

```sh
curl -sfL https://get.k3s.io | sh -s - --node-name=node-1 server --disable=traefik --etcd-s3 --etcd-s3-region=eu-central-1 --etcd-s3-bucket=morriq-homecluster --etcd-s3-access-key=XXXX --etcd-s3-secret-key=XXX --etcd-snapshot-schedule-cron='0 */6 * * *' --kubelet-arg=protect-kernel-defaults=true
```

Create a file called /etc/sysctl.d/90-kubelet.conf and add the snippet below. Then run sysctl -p /etc/sysctl.d/90-kubelet.conf.

```sh
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
```

[pod security policies](https://rancher.com/docs/k3s/latest/en/security/hardening_guide/#podsecuritypolicies)

[network policies](https://rancher.com/docs/k3s/latest/en/security/hardening_guide/#networkpolicies)

### fan

```sh
sudo kubectl label nodes node-1 fan-connected=true

sudo cat <<EOF >>/var/lib/rancher/k3s/server/manifests/fan.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: hardware-tools
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fan-deployment
  namespace: hardware-tools
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fan
  template:
    metadata:
      labels:
        app: fan
    spec:
      containers:
        - name: fan-driver
          image: pilotak/rpi-fan
          env:
          - name: DESIRED_TEMP
            value: "45"
          - name: FAN_PIN
            value: "17"
          - name: FAN_PWM_MIN
            value: "25"
          - name: FAN_PWM_MAX
            value: "100"
          - name: FAN_PWM_FREQ
            value: "25"
          - name: P_TEMP
            value: "15"
          - name: I_TEMP
            value: "0.4"
          ports:
            - containerPort: 80
          imagePullPolicy: Always
          securityContext:
            privileged: true
      nodeSelector:
        fan-connected: "true"
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: "app"
                operator: In
                values:
                - fan
            topologyKey: "kubernetes.io/hostname"
EOF
```
