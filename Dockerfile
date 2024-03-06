FROM python:3.10-slim-buster

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends git sshpass openssh-client && \
    rm -rf /var/lib/apt/lists/* && \
    pip install ansible ansible-lint[yamllint]

WORKDIR /home/ubuntu/ansible