#!/bin/bash
set -eux

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io curl

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu
mkdir -p /home/ubuntu/app
chown -R ubuntu:ubuntu /home/ubuntu/app