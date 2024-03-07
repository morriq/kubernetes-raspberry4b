# kubernetes-raspberry4b

## Requirements

- Docker

- Raspberry servers with ubuntu 22.04 64bit version (I used three: 1x master, 1x github agent)

## Usage

### Hardening

I used https://github.com/ansible-lockdown/UBUNTU22-CIS but feel free to use another.
To use it, in root of this repository:

```sh
git clone https://github.com/ansible-lockdown/UBUNTU22-CIS.git && cd UBUNTU22-CIS
echo "- 192.168.x.x" > ./inventory.yml
```

For more complex inventory see file ./ansible/inventory-k3s.yml

```sh
docker compose up -d && docker-compose exec ansible bash
cd ../UBUNTU22-CIS
ansible-playbook -i ./inventory.yml ./site.yml
```

Mentioned repo operates on `grub` and on raspberry it might fail in these steps, because `grub` it's not accessible.
I just set these steps on false:

```yaml
ubtu22cis_rule_1_4_3: false
ubtu22cis_rule_1_6_1_2: false
ubtu22cis_rule_3_1_1: false
ubtu22cis_rule_4_1_1_3: false
ubtu22cis_rule_4_1_1_4: false

# https://github.com/ansible-lockdown/UBUNTU22-CIS/issues/13:
ubtu22cis_rule_5_4_1: false
ubtu22cis_rule_5_4_2: false
ubtu22cis_rule_5_4_3: false
ubtu22cis_rule_5_4_4: false
ubtu22cis_rule_5_4_5: false

# changing passwords policy and disabling accounts when not used:
ubtu22cis_rule_5_5_1_1: false
ubtu22cis_rule_5_5_1_2: false
ubtu22cis_rule_5_5_1_3: false
ubtu22cis_rule_5_5_1_4: false
ubtu22cis_rule_5_5_1_5: false
```

### Installation

```bash
git clone https://github.com/morriq/kubernetes-raspberry4b.git && cd kubernetes-raspberry4b
```

Fill in inventory-k3s.yml

```bash
docker compose up -d
docker compose exec ansible bash
ansible-playbook -i inventory-k3s.yml cluster.yml
```

It will fail due to executing commands without waiting on installing some helm charts. **Run it again**. In future I should address it in playbooks.

### Elasticsearch policies

Make sure logs are not stored indefinitely.

set valid time policies. How to do it:

- use Lens, and forward port to local machine to Kibana
- use credentials:

```text
login: elastic
password: kubectl get secret quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'
```

Follow https://www.cloudsavvyit.com/7152/how-to-rotate-and-delete-old-elasticsearch-records-after-a-month/ to set remove policies.

## Components

k3s 1.28.7
pip kubernetes 29.0.0
https://github.com/prometheus-operator/kube-prometheus.git 0.13.0
ingress nginx 4.10.0
rancher/mirrored-metrics-server 0.7.0
external-dns 0.14.0
cloudflared 2024.2.1
external-secrets ???
