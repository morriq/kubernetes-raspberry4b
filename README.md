# kubernetes-raspberry4b
Home cluster based on kubespray with github actions deployment.

## Pre requirements

### Hardware

- [Raspberry pi 4b 8gb](https://www.raspberrypi.org/products/raspberry-pi-4-model-b/)
- SD Card. I used 32gb
- Cooler. I used [this one](https://www.amazon.com/Raspberry-Model-Aluminum-Cooling-Metal/dp/B07VQLBSNC)
- Ethernet connection

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

- Install on sd card ubuntu 20.04 64bit via https://www.raspberrypi.org/blog/raspberry-pi-imager-imaging-utility/
- Insert sd card to raspberry and connect it to internet
- Make sure your computer has docker
- I used this video  https://www.youtube.com/watch?v=8fYtvRazzpo with https://github.com/netdevopsx/youtube/blob/master/kubernetes_raspberrypi.txt but with some changes to make it work as I want. All commands are executed mostly in docker environment:

```
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
inventory/mycluster/hosts.yaml
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
helm install ingress ingress-nginx/ingress-nginx --set "controller.extraArgs.enable-ssl-passthrough=" -n ingress

```
