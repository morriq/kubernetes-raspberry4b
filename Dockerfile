FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive 

RUN apt update
RUN apt install -y software-properties-common && \
    add-apt-repository --yes --update ppa:ansible/ansible && \
    apt install -y ansible python3 python3-pip yamllint sshpass git && \
    pip3 install "ansible-lint[yamllint]"

WORKDIR /home/ubuntu/ansible