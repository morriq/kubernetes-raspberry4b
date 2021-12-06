FROM ubuntu:21.10

RUN apt update && \
    apt install -y software-properties-common && \
    add-apt-repository --yes --update ppa:ansible/ansible && \
    apt install -y ansible python3 python3-pip yamllint sshpass git && \
    pip3 install "ansible-lint[yamllint]"

WORKDIR /home/ubuntu/ansible