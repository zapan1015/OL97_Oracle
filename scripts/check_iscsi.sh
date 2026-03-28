#!/usr/bin/env bash
# ======================================================================
#  check_iscsi.sh – iSCSI 연결 상태 진단 스크립트
#
#  storage1 에서 실행: ./scripts/check_iscsi.sh target
#  racnode  에서 실행: ./scripts/check_iscsi.sh initiator
#
#  사용법:
#    vagrant ssh storage1 -- sudo /vagrant/scripts/check_iscsi.sh target
#    vagrant ssh racnode1 -- sudo /vagrant/scripts/check_iscsi.sh initiator
# ======================================================================
set -euo pipefail

MODE="${1:-help}"
SEPARATOR="─────────────────────────────────────────────"

print_section() {
  echo ""
  echo "┌─ $1"
  echo "$SEPARATOR"
}

case "$MODE" in

  target)
    echo "======================================================"
    echo "  iSCSI TARGET Diagnostics – $(hostname)"
    echo "======================================================"

    print_section "1. target service status"
    systemctl status target --no-pager -l || true

    print_section "2. targetcli configuration"
    targetcli ls || true

    print_section "3. iSCSI port listening (3260)"
    ss -tlnp | grep ':3260' || echo "  WARNING: port 3260 not listening"

    print_section "4. Block devices (to be exported)"
    lsblk -d -o NAME,SIZE,TYPE /dev/sdb /dev/sdc /dev/sdd 2>/dev/null || \
      echo "  WARNING: /dev/sdb|sdc|sdd not found"

    print_section "5. Firewall rules"
    firewall-cmd --list-ports 2>/dev/null || iptables -L -n | grep 3260 || \
      echo "  (firewalld not running or no rules)"

    print_section "6. saveconfig.json summary"
    if [ -f /etc/target/saveconfig.json ]; then
      python3 -c "
import json
with open('/etc/target/saveconfig.json') as f:
    d = json.load(f)
print('  Targets:', [t['wwn'] for t in d.get('targets', [])])
print('  Backstores:', [s['name'] for s in d.get('storage_objects', [])])
for t in d.get('targets', []):
    for tpg in t.get('tpgs', []):
        acls = [a['node_wwn'] for a in tpg.get('node_acls', [])]
        luns = len(tpg.get('luns', []))
        print(f'  ACLs: {acls}')
        print(f'  LUNs: {luns}')
"
    else
      echo "  saveconfig.json not found"
    fi
    ;;

  initiator)
    echo "======================================================"
    echo "  iSCSI INITIATOR Diagnostics – $(hostname)"
    echo "======================================================"

    print_section "1. Initiator IQN"
    cat /etc/iscsi/initiatorname.iscsi 2>/dev/null || echo "  File not found"

    print_section "2. iscsid service status"
    systemctl status iscsid --no-pager -l || true

    print_section "3. Active iSCSI sessions"
    iscsiadm -m session 2>/dev/null || echo "  No active sessions"

    print_section "4. iSCSI node DB"
    iscsiadm -m node 2>/dev/null || echo "  No nodes discovered"

    print_section "5. Block devices (iSCSI)"
    lsblk -d -o NAME,SIZE,TRAN --noheadings | grep iscsi || \
      echo "  No iSCSI block devices found"

    print_section "6. ASM disk symlinks"
    ls -la /dev/oracleasm/ 2>/dev/null || \
      echo "  /dev/oracleasm not found"

    print_section "7. udev rules"
    if [ -f /etc/udev/rules.d/99-asm-disks.rules ]; then
      cat /etc/udev/rules.d/99-asm-disks.rules
    else
      echo "  udev rules file not found"
    fi
    ;;

  all)
    # storage1 에서 모든 노드 상태를 한 번에 확인 (Ansible 사용)
    echo "======================================================"
    echo "  Full Lab iSCSI Status Check (via Ansible)"
    echo "======================================================"
    cd /vagrant
    ansible -i inventories/vagrant/hosts.ini storage \
      -m shell -a "/vagrant/scripts/check_iscsi.sh target" \
      --become

    ansible -i inventories/vagrant/hosts.ini racnodes \
      -m shell -a "/vagrant/scripts/check_iscsi.sh initiator" \
      --become
    ;;

  help|*)
    echo "Usage: $0 {target|initiator|all}"
    echo ""
    echo "  target    – iSCSI target diagnostics (run on storage1)"
    echo "  initiator – iSCSI initiator diagnostics (run on racnode)"
    echo "  all       – Check all nodes via Ansible (run on storage1)"
    exit 1
    ;;

esac

echo ""
echo "======================================================"
echo "  Diagnostics complete"
echo "======================================================"
