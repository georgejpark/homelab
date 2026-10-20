#!/bin/bash
# Base provisioning for the REA LXC (CT 101 "rea" on pve5). Run as root inside the container.
# Idempotent: every step checks before acting.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
step() { printf '\n=== [%s] %s ===\n' "$(date +%T)" "$*"; }

REA_COMMIT=69bd81f7f2768b22fb75caa753f4b21a8e5d249d   # same commit as the Mac checkout
NODE_V=24.18.0                                         # rea/.nvmrc
GHIDRA_DIR=/opt/ghidra_12.1.4_PUBLIC
GHIDRA_URL=https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip
GHIDRA_SHA256=ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db
JAVA_HOME_DIR=/usr/lib/jvm/java-21-openjdk-amd64

step "locale + apt full-upgrade"
echo 'LANG=C.UTF-8' > /etc/default/locale
apt-get update -qq
apt-get -y -qq full-upgrade
apt-get -y -qq install --no-install-recommends \
  ca-certificates curl wget git gnupg sudo unzip zip xz-utils zstd file jq less nano vim-tiny tmux htop rsync procps util-linux \
  build-essential python3 python3-venv python3-pip pipx openjdk-21-jdk-headless
java -version 2>&1 | head -1; javac -version

step "user george (sudo, same SSH key as root)"
id george >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo george
echo 'george ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-george
chmod 440 /etc/sudoers.d/90-george
visudo -cf /etc/sudoers.d/90-george
install -d -m 700 -o george -g george /home/george/.ssh
install -m 600 -o george -g george /root/.ssh/authorized_keys /home/george/.ssh/authorized_keys

step "Node.js ${NODE_V} (official tarball, SHA-256 verified) -> /usr/local"
if ! /usr/local/bin/node -v 2>/dev/null | grep -qx "v${NODE_V}"; then
  T=$(mktemp -d); cd "$T"
  curl -fsSLO "https://nodejs.org/dist/v${NODE_V}/node-v${NODE_V}-linux-x64.tar.xz"
  curl -fsSLO "https://nodejs.org/dist/v${NODE_V}/SHASUMS256.txt"
  grep " node-v${NODE_V}-linux-x64.tar.xz\$" SHASUMS256.txt | sha256sum -c -
  tar -xJf "node-v${NODE_V}-linux-x64.tar.xz" -C /usr/local --strip-components=1 --no-same-owner
  cd /; rm -rf "$T"
fi
echo "node $(node -v)  npm $(npm -v)"

step "Ghidra 12.1.4 (SHA-256 verified) -> /opt"
if [ ! -x "${GHIDRA_DIR}/support/analyzeHeadless" ]; then
  T=$(mktemp -d); cd "$T"
  curl -fsSL -o ghidra.zip "$GHIDRA_URL"
  echo "${GHIDRA_SHA256}  ghidra.zip" | sha256sum -c -
  unzip -q ghidra.zip -d /opt
  cd /; rm -rf "$T"
fi
grep -E "application.version" "${GHIDRA_DIR}/Ghidra/application.properties"
file "${GHIDRA_DIR}/Ghidra/Features/Decompiler/os/linux_x86_64/decompile" | cut -c1-120

step "/etc/environment (seen by login shells, sudo and non-interactive SSH via pam_env)"
grep -q '^GHIDRA_INSTALL_DIR=' /etc/environment || echo "GHIDRA_INSTALL_DIR=${GHIDRA_DIR}" >> /etc/environment
grep -q '^JAVA_HOME=' /etc/environment || echo "JAVA_HOME=${JAVA_HOME_DIR}" >> /etc/environment
cat /etc/environment

step "REA source checkout at ${REA_COMMIT:0:9} (owned by george)"
if [ ! -d /opt/rea/.git ]; then
  install -d -o george -g george /opt/rea
  sudo -u george git clone --quiet https://github.com/morluto/rea.git /opt/rea
fi
cd /opt/rea
sudo -u george git fetch --quiet origin
sudo -u george git checkout --quiet -B main "$REA_COMMIT"
sudo -u george git branch --quiet --set-upstream-to=origin/main main
sudo -u george git log --oneline -1

step "npm ci + build (as george)"
sudo -u george -H bash -c 'cd /opt/rea && npm ci --no-audit --no-fund 2>&1 | tail -4 && npm run build:cached 2>&1 | tail -6'

step "rea on PATH (/usr/local/bin -> source checkout)"
ln -sfn /opt/rea/scripts/rea.mjs /usr/local/bin/rea
ln -sfn /opt/rea/scripts/rea.mjs /usr/local/bin/rea-agents
echo "rea $(rea --version)"

step "Claude Code native installer (as george)"
sudo -u george -H bash -c 'test -x ~/.local/bin/claude || (curl -fsSL https://claude.ai/install.sh | bash) 2>&1 | tail -5'
sudo -u george -H bash -c '~/.local/bin/claude --version'

step "DONE"
