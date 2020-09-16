# kubernetes-raspberry4b
Https home cluster based on kubespray with github actions deployment.

- [ ] modify k8s.yaml to use docker image with commited hash - kubernetest that way will know when to pull new image

Content:
- [Pre requirements](#pre-requirements)
    - [Hardware](#hardware)
    - [Software](#software)
    - [Domain](#domain)
    - [Network](#network)
- [Installation](#installation)
    - [Kubernetes](#kubernetes)
    - [https](#https)
    - [github actions deployment](#github-actions-deployment)
    - [github packages](#github-packages)
- [Development](#development)
    - [rust](#rust)

## Pre requirements

### Hardware

- [Raspberry pi 4b 8gb](https://www.raspberrypi.org/products/raspberry-pi-4-model-b/)
- SD Card. I used 32gb with installed ubuntu 20.04 64bit (https://www.raspberrypi.org/blog/raspberry-pi-imager-imaging-utility/)
- Cooler. I used [this one](https://www.amazon.com/Raspberry-Model-Aluminum-Cooling-Metal/dp/B07VQLBSNC)
- Ethernet connection

### Software

- Docker on your computer

### Domain

- forward domain to your public IP (I'll call it example.com).

- add additional configuration to handle subdomains and www:

```
*          IN CNAME  example.com.
www        IN CNAME  example.com.
```

### Network

On my network provider - UPC I have to:

- disable ipv6
- forward port 80, 443, 6443 to raspberrypi ip
- make smaller DHCP range to prevent conflicts in kubernetes

## Installation

### Kubernetes

I used this video  https://www.youtube.com/watch?v=8fYtvRazzpo with https://github.com/netdevopsx/youtube/blob/master/kubernetes_raspberrypi.txt but with some changes to make it work as I want. All commands are executed mostly in docker environment:

```sh
# Prepare docker:
docker run -it ubuntu:20.04 bash
apt-get update -y && apt-get --with-new-pkgs upgrade -y
apt install python3-pip git vim curl -y
ssh-keygen

# login and change password
ssh ubuntu@{RASPBERRY PI IP}
# upload public key
ssh-copy-id ubuntu@{RASPBERRY PI IP}

Prepare Raspbeeri
#### --------------------------------------------------------
sudo -i
vim /etc/netplan/50-cloud-init.yaml
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

vim /boot/firmware/cmdline.txt
cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
sudo apt-get update -y && sudo apt-get --with-new-pkgs upgrade -y
sudo apt install python3-pip git -y

#### --------------------------------------------------------

git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
git checkout v2.13.0
pip3 install -r requirements.txt
cp -rfp inventory/sample inventory/mycluster
declare -a IPS=(192.168.0.233)
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
vim roles/bootstrap-os/tasks/bootstrap-debian.yml
>>>>     DEBIAN_FRONTEND=noninteractive apt-get install -y python3-minimal
vim inventory/mycluster/hosts.yaml
>>> ansible_user: ubuntu
vim inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml
find and modify line with "supplementary_addresses_in_ssl_keys":
>>>> supplementary_addresses_in_ssl_keys: ["example.com"]
# The installation process
ansible-playbook -i inventory/mycluster/hosts.yaml  --become --become-user=root cluster.yml \
-e "ansible_distribution_release=bionic kube_resolv_conf=/run/systemd/resolve/resolv.conf local_path_provisioner_enabled=true"

# We need to get kube config from the cluster
ssh ubuntu@192.168.0.233
sudo cp /root/.kube/config /home/ubuntu/
sudo chown ubuntu /home/ubuntu/config

#### --------------------------------------------------------

mkdir /root/.kube/
scp ubuntu@192.168.0.233:/home/ubuntu/config ~/.kube/config

# We have config but we need to have kubectl as well
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.18.0/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl


# we have only one node,  we don't need to more one pod for core-dns
# we will remove dns-autoscaler
kubectl delete deployment dns-autoscaler --namespace=kube-system
# scale current count of replicas to 1
kubectl scale deployments.apps -n kube-system coredns --replicas=1

# to be able to recieve incoming connection to K8S we need to install metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml

create configmap and apply it
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.0.234-192.168.0.247

# On first install only
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"

curl -LO https://get.helm.sh/helm-v3.2.1-linux-amd64.tar.gz
tar -zxvf helm-v3.2.1-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
# install ingress we must set image ARM64
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress ingress-nginx/ingress-nginx --set "controller.extraArgs.enable-ssl-passthrough=" -n nginx

```

After that you should be able get nginx 404 response from your server. Just: `curl -I example.com`

### https

I used cert-manager for kubernetes. It's great tool with many solutions to serve https. 
We basically want to free https, such as letsencrypt. To do it we use https://cert-manager.io/docs/configuration/acme/ with dns01 challange provider.

I used YOURNAMESPACE as my domain

run: `kubectl create namespace <YOURNAMESPACE>`


If you have domain in ovh then you can follow [this tutorial](https://github.com/morriq/cert-manager-webhook-ovh#ovh-webhook-for-cert-manager). 

If no then you should pick one on bottom of https://cert-manager.io/docs/configuration/acme/dns01/. Alternatively you can use [generic webhook resolver](https://cert-manager.io/docs/configuration/acme/dns01/webhook/)


### github actions deployment

We're going to use `<NAMESPACE>` created in #https section.

Create service account in kubernetes. It will be used in github:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-deployment
  namespace: <NAMESPACE>
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: <NAMESPACE>
  name: github-deployment
rules:
- apiGroups: ["extensions"] # "" indicates the core API group
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"] # "" indicates the core API group
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["services", "pods"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: <NAMESPACE>
  name: github-deployment
subjects:
- kind: ServiceAccount
  name: github-deployment
  namespace: <NAMESPACE>
roleRef:
  kind: ClusterRole
  name: github-deployment
  apiGroup: rbac.authorization.k8s.io
```

Add this to your repository in .github/workflows/deploy.yml:

```
name: CD

on:
  push:
    branches: [ master ]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v2

    - name: Kubernetes set context
      uses: Azure/k8s-set-context@v1
      with:
        method: service-account
        k8s-url: https://example.com:6443
        k8s-secret: ${{ secrets.KUBECONFIG }}

    - uses: Azure/k8s-deploy@v1
      with:
        namespace: <NAMESPACE>
        manifests: |
          manifets/sample.yaml
```

Get service account secrent name:

`kubectl get serviceAccounts github-deployment -o 'jsonpath={.secrets[*].name}' -n <namespace>`

Get secret and copy it to your repository in settings/secrets value of `KUBECONFIG`

`kubectl get secret <service-account-secret-name> -n <namespace> -o yaml`

Test your github action by adding manifets/sample.yaml with pod **or** deployment:

### Pod

```yaml
kind: Pod
apiVersion: v1
metadata:
  name: hello-app
  labels:
    app: hello
spec:
  containers:
    - name: hello-app
      image: hypriot/rpi-busybox-httpd
      env:
      - name: PORT
        value: "80"

---

kind: Service
apiVersion: v1
metadata:
  name: hello-service
spec:
  selector:
    app: hello
  ports:
    - port: 80 # Default port for image

---

apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
    cert-manager.io/issuer: "letsencrypt"
spec:
  tls:
  - hosts:
    - www.example.com
    - example.com
    - test.example.com
    - www.test.example.com
    secretName: example-tls
  rules:
  - host: example.com
    http:
      paths:
        - path: /
          backend:
            serviceName: hello-service
            servicePort: 80
  - host: test.example.com
    http:
      paths:
        - path: /
          backend:
            serviceName: hello-service
            servicePort: 80
```

### Deployment

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
    cert-manager.io/issuer: "letsencrypt"
spec:
  tls:
  - hosts:
    - www.example.com
    - example.com
    - test.example.com
    - www.test.example.com
    secretName: example-tls
  rules:
  - host: example.com
    http:
      paths:
        - path: /
          backend:
            serviceName: hello-kubernetes
            servicePort: 80
  - host: test.example.com
    http:
      paths:
        - path: /
          backend:
            serviceName: hello-kubernetes
            servicePort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hello-kubernetes
spec:
  ports:
  - port: 80
  #type: ClusterIP
  selector:
    app: hello-kubernetes
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-kubernetes
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-kubernetes
  template:
    metadata:
      labels:
        app: hello-kubernetes
    spec:
      containers:
      - name: hello-kubernetes
        image: hypriot/rpi-busybox-httpd
        ports:
        - containerPort: 80
        env:
        - name: PORT
          value: "80"
```

## github packages

I use github packages to create docker image and push it to github registry. Next this image is deployed on kubernetes.

My k8s deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-kubernetes
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-kubernetes
  template:
    metadata:
      labels:
        app: hello-kubernetes
    spec:
      imagePullSecrets:
        - name: ghcr
      containers:
        - name: readme-deployment
          image: docker.pkg.github.com/<organisation>/<repository name>/<image name>:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 80
          env:
            - name: HOST
              value: '0.0.0.0:80'

```

firstly create github token with access to `read:packages` and add secret in `<NAMESPACE>` where you have pod/deployment with used image.


`kubectl create secret docker-registry ghcr --docker-server=docker.pkg.github.com --docker-username=USERNAME --docker-password=PASSWORD --docker-email=EMAIL -n NAMESPACE`

Last part is to create build image and push it to github repository. Sample with github actions:

```
name: Deploy

on:
  push:
    branches: [master]

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - uses: whoan/docker-build-with-cache-action@v5
        with:
          username: USERNAME
          password: '${{ secrets.GITHUB_TOKEN }}'
          registry: docker.pkg.github.com
          image_name: ORGANISATION/REPOSITORY/IMAGE NAME

  deploy:
    runs-on: ubuntu-latest
    needs: publish
    timeout-minutes: 4

    steps:
      - uses: actions/checkout@v2

      - name: Kubernetes set context
        uses: Azure/k8s-set-context@v1
        with:
          method: service-account
          k8s-url: https://example.com:6443
          k8s-secret: ${{ secrets.KUBECONFIG }}

      - uses: Azure/k8s-deploy@v1
        with:
          namespace: NAMESPACE
          manifests: |
            k8s.yaml
```

## Development

### Rust

to compile rust for raspberyy pi on ubuntu 64bit I had to add `.cargo/config` with value:

```
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"
rustflags = [ "-C", "target-feature=+crt-static", "-C", "link-arg=-lgcc" ]
```

next Dockerfile

```dockerfile
FROM rust:1.46 AS builder

WORKDIR /usr/src/PROJECT

RUN cargo install cargo-watch systemfd

RUN apt-get update
RUN apt-get install -y gcc-aarch64-linux-gnu

RUN rustup target add aarch64-unknown-linux-gnu

RUN mkdir src && touch src/lib.rs
COPY Cargo.lock .
COPY Cargo.toml .
COPY .cargo .cargo

RUN cargo build --target aarch64-unknown-linux-gnu --release

ADD . .
RUN cargo build --target aarch64-unknown-linux-gnu --release

FROM arm64v8/debian:buster-slim
COPY --from=builder \
    /usr/src/PROJECT/target/aarch64-unknown-linux-gnu/release/PROJECT \
    /usr/local/bin/PROJECT
CMD ["PROJECT"]
```

and for local development I created `docker-compose.yaml`:

```
version: '3.4'
services:
  readme:
    command: systemfd --no-pid -s http::0.0.0.0:3000 -- cargo watch -x run
    ports:
      - '3000:3000'
    environment:
      - HOST=0.0.0.0:3000
    build:
      context: .
      target: builder
    volumes:
      - ./:/usr/src/readme
```

With such configuration I could easily deploy this `main.rs`:

```rust
use actix_web::{get, web, App, HttpServer, Responder};
use listenfd::ListenFd;
use std::env;

mod graphic;

#[get("/{id}/{name}/index.html")]
async fn index(web::Path((id, name)): web::Path<(u32, String)>) -> impl Responder {
    format!("Hello {}! id:{}", name, id)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    println!("Hello World!");

    let mut listenfd = ListenFd::from_env();
    let mut server = HttpServer::new(|| App::new().service(index));
    let host = env::var("HOST").expect("HOST avaiable must be set");

    server = if let Some(l) = listenfd.take_tcp_listener(0).unwrap() {
        server.listen(l)?
    } else {
        server.bind(host)?
    };

    server.run().await
}
```
