#!/usr/bin/env bash
# One-time setup for EC2-A (Ubuntu 22.04/24.04): DevOps Jenkins + the server the demo app is deployed to.
# Installs: swap, JDK 17, Docker + compose plugin, git, curl, Jenkins.
# Also lets the jenkins user SSH to ubuntu@127.0.0.1 (this is how the pipeline "deploys to the server").
# Run as the ubuntu user:   bash setup-devops-ec2.sh
set -euo pipefail

echo "== 1. Swap (2 GB) =="
if ! swapon --show | grep -q swapfile; then
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

echo "== 2. Base packages + JDK 17 =="
sudo apt-get update -y
sudo apt-get install -y fontconfig openjdk-17-jre git curl wget gnupg ca-certificates

echo "== 3. Docker =="
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo apt-get install -y docker-compose-plugin || true
sudo usermod -aG docker "$USER"

echo "== 4. Jenkins =="
if [ ! -d /var/lib/jenkins ]; then
  sudo wget -q -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y jenkins
fi
sudo systemctl enable --now jenkins

echo "== 5. SSH key for the jenkins user, allowed to log in as ubuntu on this machine =="
sudo -u jenkins mkdir -p /var/lib/jenkins/.ssh
sudo -u jenkins chmod 700 /var/lib/jenkins/.ssh
if [ ! -f /var/lib/jenkins/.ssh/id_ed25519 ]; then
  sudo -u jenkins ssh-keygen -t ed25519 -N "" -C "jenkins-demo" -f /var/lib/jenkins/.ssh/id_ed25519
fi
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
PUB="$(sudo cat /var/lib/jenkins/.ssh/id_ed25519.pub)"
grep -qF "$PUB" "$HOME/.ssh/authorized_keys" 2>/dev/null || echo "$PUB" >> "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"

echo "== 6. Trust this machine's SSH host key for the jenkins user (StrictHostKeyChecking=yes) =="
ssh-keyscan -H 127.0.0.1 2>/dev/null | sudo -u jenkins tee -a /var/lib/jenkins/.ssh/known_hosts >/dev/null

echo "== 7. Test: jenkins -> ubuntu@127.0.0.1 =="
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/id_ed25519 -o StrictHostKeyChecking=yes -o BatchMode=yes ubuntu@127.0.0.1 hostname

echo "== Versions =="
java -version 2>&1 | head -1
docker --version
docker compose version
git --version
sudo systemctl is-active jenkins

echo
echo "Initial Jenkins admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo
echo "Private key to paste into the Jenkins credential 'demo-server-ssh' (shown once below):"
echo "----------------------------------------------------------------"
sudo cat /var/lib/jenkins/.ssh/id_ed25519
echo "----------------------------------------------------------------"
echo
echo "IMPORTANT: log out and back in (or run: newgrp docker) so the docker group applies to the ubuntu user."
echo "Then open http://<this-server-public-ip>:8080 (security group must allow 8080 from your IP)."
