#!/bin/bash
set -eux

# If script is executed manually without root, rerun with sudo
if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io curl

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu || true

mkdir -p /home/ubuntu/app
chown -R ubuntu:ubuntu /home/ubuntu/app

docker --version
systemctl is-active docker