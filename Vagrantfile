# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# ======================================================================
#  Oracle RAC 2-Node Lab
# ======================================================================
#  Topology:
#    racnode1  192.168.56.101 / 192.168.57.101  Oracle RAC Node 1
#    racnode2  192.168.56.102 / 192.168.57.102  Oracle RAC Node 2
#    storage1  192.168.56.200                   iSCSI Target + Ansible Master
#
#  Networks:
#    192.168.56.0/24  iSCSI + Public   (VirtualBox host-only)
#    192.168.57.0/24  RAC Interconnect (VirtualBox internal network)
#
#  Shared Disks (on storage1, exported via iSCSI to RAC nodes):
#    /dev/sdb  20 GB  →  +DATA ASM Disk Group
#    /dev/sdc  20 GB  →  +DATA ASM Disk Group
#    /dev/sdd  10 GB  →  +FRA  ASM Disk Group
#
#  Provisioning Flow:
#    1. vagrant up           → All 3 VMs boot + shell bootstrap
#    2. Ansible is installed automatically on storage1
#    3. vagrant ssh storage1 → cd /vagrant && ansible-playbook ...
#       OR: vagrant provision storage1 --provision-with run-ansible
#
#  NOTE: VirtualBox SATA controller name must match your environment.
#        Check with: VBoxManage showvminfo storage1 | grep "Storage Cont"
#        Default expected: "SATA Controller"
# ======================================================================

require 'fileutils'

VAGRANTFILE_API_VERSION = "2"

# ── Network ────────────────────────────────────────────────────────────
ISCSI_NET   = "192.168.56"    # host-only : iSCSI + Public
PRIVATE_NET = "192.168.57"    # internal  : RAC Interconnect

# ── VirtualBox SATA Controller Name ───────────────────────────────────
SATA_CTRL = "SATA Controller"

# ── Directories ───────────────────────────────────────────────────────
DISK_DIR     = File.join(__dir__, ".vagrant", "disks")
ORACLE_SW_DIR = File.join(__dir__, "oracle")   # Oracle 설치 미디어 (host)

FileUtils.mkdir_p(DISK_DIR)

# Oracle SW 디렉토리 존재 및 파일 확인
if File.directory?(ORACLE_SW_DIR)
  oracle_files = Dir.glob(File.join(ORACLE_SW_DIR, "*.zip")).map { |f| File.basename(f) }
  if oracle_files.empty?
    puts "  [WARN] oracle/ 디렉토리는 있으나 zip 파일이 없습니다."
  else
    puts "  [INFO] Oracle SW 감지됨:"
    oracle_files.each { |f| puts "         - #{f}" }
  end
  ORACLE_SW_AVAILABLE = true
else
  puts "  [WARN] oracle/ 디렉토리가 없습니다. 설치 미디어 없이 기동합니다."
  ORACLE_SW_AVAILABLE = false
end

# ── Ansible SSH Key ────────────────────────────────────────────────────
# Generated once at vagrant up, stored under .vagrant/ (gitignored).
# This key is distributed to all nodes so storage1 can drive Ansible.
ANSIBLE_KEY     = File.join(__dir__, ".vagrant", "ansible_key")
ANSIBLE_PUB_KEY = "#{ANSIBLE_KEY}.pub"

unless File.exist?(ANSIBLE_KEY)
  puts "==> Generating Ansible SSH key pair …"
  system("ssh-keygen -t rsa -b 4096 -N \"\" -f \"#{ANSIBLE_KEY}\" " \
         "-C \"ansible@storage1\" -q")
end

ANSIBLE_PUB = File.exist?(ANSIBLE_PUB_KEY) \
              ? File.read(ANSIBLE_PUB_KEY).strip \
              : ""

# ── /etc/hosts block injected into every VM ───────────────────────────
ETC_HOSTS_BLOCK = <<~HOSTS
  # ── Oracle RAC Lab (managed by Vagrant) ──
  #{ISCSI_NET}.200  storage1
  #{ISCSI_NET}.101  racnode1 racnode1-pub
  #{ISCSI_NET}.102  racnode2 racnode2-pub
  #{PRIVATE_NET}.101 racnode1-priv
  #{PRIVATE_NET}.102 racnode2-priv
HOSTS

# ── VM Definitions ─────────────────────────────────────────────────────
# racnode1/2 are defined FIRST → Vagrant provisions them before storage1.
# storage1 is defined LAST    → Its Ansible installer runs after peers are up.
VMS = [
  {
    name:      "racnode1",
    ip_pub:    "#{ISCSI_NET}.101",
    ip_priv:   "#{PRIVATE_NET}.101",
    memory:    4096,
    cpus:      2,
    disks:     [],
    oracle_sw: true,   # Oracle Grid/DB 설치 미디어 마운트 (/oracle_sw)
  },
  {
    name:      "racnode2",
    ip_pub:    "#{ISCSI_NET}.102",
    ip_priv:   "#{PRIVATE_NET}.102",
    memory:    4096,
    cpus:      2,
    disks:     [],
    oracle_sw: true,
  },
  {
    name:      "storage1",
    ip_pub:    "#{ISCSI_NET}.200",
    ip_priv:   nil,
    memory:    2048,
    cpus:      2,
    oracle_sw: false,  # iSCSI Target 전용 – 설치 미디어 불필요
    disks: [
      { port: 1, dev: "sdb", size_mb: 20_480 },   # 20 GB → +DATA
      { port: 2, dev: "sdc", size_mb: 20_480 },   # 20 GB → +DATA
      { port: 3, dev: "sdd", size_mb: 10_240 },   # 10 GB → +FRA
    ],
  },
]

# ══════════════════════════════════════════════════════════════════════
Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  config.vm.box = "oraclelinux/9"
  config.vbguest.auto_update = false if Vagrant.has_plugin?("vagrant-vbguest")

  # ── Disable default /vagrant sync (use explicit below) ──────────────
  # config.vm.synced_folder ".", "/vagrant", disabled: true

  VMS.each do |vm|
    config.vm.define vm[:name] do |node|

      node.vm.hostname = vm[:name]

      # ── Network ──────────────────────────────────────────────────────
      # NIC1: NAT (default – internet / yum access)
      # NIC2: host-only – iSCSI + Public
      node.vm.network "private_network", ip: vm[:ip_pub]

      # NIC3: internal – RAC Interconnect (racnodes only)
      if vm[:ip_priv]
        node.vm.network "private_network",
          ip:                 vm[:ip_priv],
          virtualbox__intnet: "rac-interconnect"
      end

      # ── Oracle Software Synced Folder (racnodes only) ────────────────
      # Host: ./oracle/  →  Guest: /oracle_sw  (읽기 전용 마운트)
      # 포함 파일:
      #   LINUX.X64_193000_grid_home.zip  (Oracle 19c Grid Infrastructure)
      #   LINUX.X64_193000_db_home.zip    (Oracle 19c Database)
      if vm[:oracle_sw] && ORACLE_SW_AVAILABLE
        node.vm.synced_folder ORACLE_SW_DIR, "/oracle_sw",
          id:           "oracle-sw",
          owner:        "vagrant",
          group:        "vagrant",
          mount_options: ["dmode=755", "fmode=644"]
      end

      # ── VirtualBox Provider ──────────────────────────────────────────
      node.vm.provider "virtualbox" do |vb|
        vb.name   = vm[:name]
        vb.memory = vm[:memory]
        vb.cpus   = vm[:cpus]
        vb.gui    = false

        # Extra disks (storage1 only) ─────────────────────────────────
        vm[:disks].each do |disk|
          disk_file = File.join(DISK_DIR, "#{vm[:name]}_#{disk[:dev]}.vdi")

          # createmedium is idempotent via file-existence check
          unless File.exist?(disk_file)
            vb.customize [
              "createmedium", "disk",
              "--filename", disk_file,
              "--size",     disk[:size_mb],
              "--format",   "VDI",
            ]
          end

          vb.customize [
            "storageattach", vm[:name],
            "--storagectl",  SATA_CTRL,
            "--port",        disk[:port],
            "--device",      0,
            "--type",        "hdd",
            "--medium",      disk_file,
          ]
        end
      end # provider

      # ── Provisioner 1: Common Bootstrap (all nodes) ──────────────────
      node.vm.provision "shell", name: "bootstrap", inline: <<~SHELL
        set -e

        echo "==> [$(hostname)] Bootstrap start"

        # /etc/hosts – append once
        if ! grep -q "Oracle RAC Lab" /etc/hosts 2>/dev/null; then
          cat >> /etc/hosts << 'HOSTS_EOF'
#{ETC_HOSTS_BLOCK}
HOSTS_EOF
          echo "  --> /etc/hosts updated"
        fi

        # Python3 – required for Ansible managed node
        if ! command -v python3 &>/dev/null; then
          dnf install -y python3 --quiet
        fi

        # Accept Ansible Master's SSH public key
        ANSIBLE_PUB="#{ANSIBLE_PUB}"
        if [ -n "$ANSIBLE_PUB" ]; then
          mkdir -p /home/vagrant/.ssh
          chmod 700 /home/vagrant/.ssh
          touch /home/vagrant/.ssh/authorized_keys
          chmod 600 /home/vagrant/.ssh/authorized_keys
          chown -R vagrant:vagrant /home/vagrant/.ssh
          if ! grep -qF "$ANSIBLE_PUB" /home/vagrant/.ssh/authorized_keys; then
            echo "$ANSIBLE_PUB" >> /home/vagrant/.ssh/authorized_keys
            echo "  --> Ansible SSH public key registered"
          fi
        fi

        # Oracle SW 마운트 확인 (racnodes 전용)
        if [ -d /oracle_sw ]; then
          echo "  --> /oracle_sw 마운트 확인:"
          ls -lh /oracle_sw/*.zip 2>/dev/null | awk '{print "      "$NF, $5}' || \
            echo "      (zip 파일 없음)"
        fi

        echo "==> [$(hostname)] Bootstrap done"
      SHELL

      # ── Provisioner 2: Ansible Master Setup (storage1 only) ──────────
      if vm[:name] == "storage1"

        # Upload private key to VM (file provisioner copies from host)
        node.vm.provision "file",
          source:      ANSIBLE_KEY,
          destination: "/tmp/ansible_key"

        # Install Ansible + place key
        node.vm.provision "shell", name: "ansible-install", inline: <<~SHELL
          set -e

          echo "==> [storage1] Installing Ansible …"

          # Place Ansible private key
          install -o vagrant -g vagrant -m 600 \
            /tmp/ansible_key /home/vagrant/.ssh/id_rsa_ansible
          rm -f /tmp/ansible_key

          # EPEL + Ansible
          dnf install -y epel-release --quiet 2>/dev/null || true
          dnf install -y ansible --quiet 2>/dev/null
          echo "  --> $(ansible --version | head -1)"

          # Point ansible.cfg to project directory
          echo "  --> Project mounted at /vagrant"

          echo ""
          echo "╔══════════════════════════════════════════════════════╗"
          echo "║  Ansible Master ready on storage1                    ║"
          echo "║                                                      ║"
          echo "║  To run the full RAC provisioning:                   ║"
          echo "║                                                      ║"
          echo "║  vagrant ssh storage1                                ║"
          echo "║  cd /vagrant                                         ║"
          echo "║  ansible-playbook -i inventories/vagrant/hosts.ini  ║"
          echo "║                   playbooks/site.yml                 ║"
          echo "║                                                      ║"
          echo "║  Or step-by-step:                                    ║"
          echo "║  ansible-playbook ... playbooks/01_bootstrap.yml     ║"
          echo "║  ansible-playbook ... playbooks/02_storage_iscsi.yml ║"
          echo "║  ansible-playbook ... playbooks/03_rac_prereq.yml    ║"
          echo "║  ansible-playbook ... playbooks/04_iscsi_initiator.yml║"
          echo "║  ansible-playbook ... playbooks/05_asm_disk.yml      ║"
          echo "║                                                      ║"
          echo "║  Oracle 설치 미디어 (racnode1/2 에서 확인):          ║"
          echo "║    ls /oracle_sw/                                    ║"
          echo "╚══════════════════════════════════════════════════════╝"
        SHELL

        # Optional: run Ansible automatically (vagrant provision --provision-with run-ansible)
        node.vm.provision "shell", name: "run-ansible", run: "never",
          inline: <<~SHELL
          set -e
          cd /vagrant
          sudo -u vagrant ansible-playbook \
            -i inventories/vagrant/hosts.ini \
            playbooks/site.yml \
            --private-key /home/vagrant/.ssh/id_rsa_ansible \
            -v
        SHELL

      end # storage1

    end # define
  end # VMS.each

end # Vagrant.configure
