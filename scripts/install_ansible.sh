#!/usr/bin/env bash
# ======================================================================
#  install_ansible.sh – storage1 에 Ansible 부트스트랩
#  Vagrantfile shell provisioner 에서 인라인으로 실행되거나
#  수동으로 실행 가능
# ======================================================================
set -euo pipefail

echo "==> Installing Ansible on $(hostname)..."

# EPEL
if ! dnf repolist enabled | grep -q epel; then
  dnf install -y epel-release
fi

# Ansible
dnf install -y ansible

echo "==> Ansible version: $(ansible --version | head -1)"

# Ansible Galaxy 의존성
if [ -f /vagrant/requirements.yml ]; then
  echo "==> Installing Galaxy collections..."
  ansible-galaxy collection install -r /vagrant/requirements.yml
fi

echo "==> Done. Run: cd /vagrant && ansible-playbook -i inventories/vagrant/hosts.ini playbooks/site.yml"
