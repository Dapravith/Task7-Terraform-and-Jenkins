#!/bin/bash
set -e

echo "=============================="
echo " Updating system packages"
echo "=============================="
sudo apt update -y
sudo apt upgrade -y


echo "=============================="
echo " Installing Java (OpenJDK 21)"
echo "=============================="
sudo apt install -y fontconfig openjdk-21-jre
java -version


echo "=============================="
echo " Installing Jenkins"
echo "=============================="

# Create keyrings dir if not exists
sudo mkdir -p /etc/apt/keyrings

# Add Jenkins key + repo
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Jenkins
sudo apt update -y
sudo apt install -y jenkins

# Enable + start Jenkins
sudo systemctl enable --now jenkins


echo "=============================="
echo " Installing Docker"
echo "=============================="
sudo apt install -y docker.io

# Enable + start Docker
sudo systemctl enable --now docker


echo "=============================="
echo " Configuring Docker permissions"
echo "=============================="
sudo usermod -aG docker ubuntu
sudo usermod -aG docker jenkins

# Allow Jenkins to access Docker socket (⚠️ insecure but common for CI servers)
sudo chmod 666 /var/run/docker.sock


echo "=============================="
echo " Installing Terraform"
echo "=============================="
wget -O - https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

sudo apt update -y
sudo apt install -y terraform


echo "=============================="
echo " Installing AWS CLI v2"
echo "=============================="
sudo apt install -y unzip curl

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install

# Cleanup
rm -rf aws awscliv2.zip


echo "=============================="
echo " Restarting Jenkins"
echo "=============================="
sudo systemctl restart jenkins


echo "=============================="
echo " Jenkins Admin Password"
echo "=============================="
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

echo ""
echo "=============================="
echo " Done ✅ Jenkins is ready"
echo "=============================="