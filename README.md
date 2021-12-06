# kubernetes-raspberry4b

## Requirements

- Docker

- Raspberry servers with ubuntu 20.04 64bit version (I used three: 1x master, 1x worker, 1x github agent)

- Ansible if Ubuntu CIS is not mounted in docker-compose

## Usage

### Hardening

I used https://github.com/ansible-lockdown/UBUNTU20-CIS but feel free to use another.
Mentioned repo operates on `grub` and on raspberry it might fail in these steps, because `grub` it's not accessible.
I just set these steps on false:

```yaml
ubtu20cis_rule_1_1_1_6: false
ubtu20cis_rule_1_4_1: false
ubtu20cis_rule_1_6_1_2: false
ubtu20cis_rule_3_1_1: false
ubtu20cis_rule_4_1_1_3: false
ubtu20cis_rule_4_1_1_4: false
```

### Installation

```bash
git clone https://github.com/morriq/kubernetes-raspberry4b.git && cd kubernetes-raspberry4b
```

Fill in inventory-k3s.yml

```bash
docker-compose up -d
docker-compose exec ansible bash
ansible-playbook -i inventory-k3s.yml cluster.yml
```

It will fail due to executing commands without waiting on installing some helm charts. **Run it again**. In futhure I should address it in playbooks.

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
