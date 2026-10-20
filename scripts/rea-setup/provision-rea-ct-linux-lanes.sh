#!/bin/bash
# External tools for REA's Linux lanes inside CT 101 "rea". Run as root inside the container. Idempotent.
# Versions follow REA's docs (rea/docs/*.md): pwntools 4.15.0 + pyelftools 0.33 + unicorn 2.1.2,
# TShark 4.x + capinfos + prlimit, sigrok-cli 0.7.2, Apktool >= 2.7.0, mitmdump 12.2.3,
# Binwalk 3.1.x + Unblob 26.6.x, WABT 1.0.42, jadx-headless-mcp 0.7.1 (JDK 17+).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
step() { printf '\n=== [%s] %s ===\n' "$(date +%T)" "$*"; }
T=/opt/rea-tools
install -d "$T" "$T/bin" "$T/dl"

fetch_verified() { # url dest expected-sha256
  if [ -f "$2" ] && echo "$3  $2" | sha256sum -c --status -; then echo "ok (cached) $2"; return; fi
  curl -fsSL --proto '=https' --retry 3 -o "$2.part" "$1"
  echo "$3  $2.part" | sha256sum -c -
  mv "$2.part" "$2"
}
gh_digest() { # repo tag asset -> sha256 from the GitHub release API
  curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$1/releases/tags/$2" |
    python3 -c "import json,sys; d=json.load(sys.stdin); print(next(a['digest'].split(':',1)[1] for a in d['assets'] if a['name']=='$3'))"
}

step "apt: tshark/capinfos, sigrok-cli, gdb, apktool, chromium, pipx, unblob extractors, binwalk build deps"
echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  tshark sigrok-cli gdb apktool chromium pipx python3-venv \
  7zip lz4 lzop lziprecover zstd xz-utils e2fsprogs android-sdk-libsparse-utils cpio \
  cargo rustc pkg-config libfontconfig1-dev liblzma-dev libbz2-dev zlib1g-dev >/dev/null
tshark --version | head -1; sigrok-cli --version | head -1; apktool --version 2>/dev/null | head -1; chromium --version; cargo --version

step "pwntools 4.15.0 venv (pyelftools 0.33, unicorn 2.1.2)"
[ -x "$T/pwntools-venv/bin/python" ] || python3 -m venv "$T/pwntools-venv"
"$T/pwntools-venv/bin/pip" install --quiet --disable-pip-version-check pwntools==4.15.0 pyelftools==0.33 unicorn==2.1.2
"$T/pwntools-venv/bin/python" -c "import pwnlib, elftools, unicorn; print('pwntools', pwnlib.version, '| pyelftools', elftools.__version__, '| unicorn', unicorn.__version__)"

step "pipx: mitmproxy 12.2.3, unblob 26.6.4"
export PIPX_HOME="$T/pipx" PIPX_BIN_DIR="$T/bin"
pipx list --short 2>/dev/null | grep -q '^mitmproxy 12.2.3' || pipx install --force mitmproxy==12.2.3 >/dev/null
pipx list --short 2>/dev/null | grep -q '^unblob 26.6.4' || pipx install --force unblob==26.6.4 >/dev/null
"$T/bin/mitmdump" --version | head -1; "$T/bin/unblob" --version

step "binwalk 3.1.0 (cargo, locked)"
if ! "$T/bin/binwalk" --version 2>/dev/null | grep -q '3\.1\.'; then
  CARGO_HOME="$T/cargo" cargo install --quiet --locked binwalk --version 3.1.0 --root "$T"
fi
"$T/bin/binwalk" --version 2>&1 | head -1

step "WABT 1.0.42 (GitHub release, digest-verified)"
if [ ! -x "$T/wabt-1.0.42/bin/wasm2wat" ]; then
  fetch_verified https://github.com/WebAssembly/wabt/releases/download/1.0.42/wabt-1.0.42-linux-x64.tar.gz \
    "$T/dl/wabt-1.0.42-linux-x64.tar.gz" "$(gh_digest WebAssembly/wabt 1.0.42 wabt-1.0.42-linux-x64.tar.gz)"
  tar -xzf "$T/dl/wabt-1.0.42-linux-x64.tar.gz" -C "$T" --no-same-owner
fi
"$T/wabt-1.0.42/bin/wasm2wat" --version

step "jadx-headless-mcp 0.7.1 (GitHub release, digest-verified)"
fetch_verified https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar \
  "$T/jadx-headless-mcp-0.7.1-all.jar" "$(gh_digest 1013503897/jadx-headless-mcp v0.7.1 jadx-headless-mcp-0.7.1-all.jar)"

step "/etc/environment (REA tool locations)"
add_env() { grep -q "^$1=" /etc/environment && sed -i "s#^$1=.*#$1=$2#" /etc/environment || echo "$1=$2" >> /etc/environment; }
add_env REA_PWNTOOLS_PYTHON "$T/pwntools-venv/bin/python"
add_env REA_TSHARK_COMMAND /usr/bin/tshark
add_env REA_CAPINFOS_COMMAND /usr/bin/capinfos
add_env REA_SIGROK_COMMAND /usr/bin/sigrok-cli
add_env REA_APKTOOL_COMMAND /usr/bin/apktool
add_env REA_MITMDUMP_COMMAND "$T/bin/mitmdump"
add_env REA_UNBLOB_COMMAND "$T/bin/unblob"
add_env REA_BINWALK_COMMAND "$T/bin/binwalk"
add_env REA_WABT_BIN_DIRECTORY "$T/wabt-1.0.42/bin"
add_env REA_JADX_MCP_JAR "$T/jadx-headless-mcp-0.7.1-all.jar"
add_env REA_BROWSER_EXECUTABLE /usr/bin/chromium
cat /etc/environment

step "unblob extractors: erofs, partclone, unar (apt), sasquatch (onekey-sec .deb), jefferson + ubi_reader (pipx)"
apt-get install -y -qq --no-install-recommends erofs-utils partclone unar >/dev/null
if ! command -v sasquatch >/dev/null; then
  fetch_verified https://github.com/onekey-sec/sasquatch/releases/download/sasquatch-v4.5.1-6/sasquatch_1.0_amd64.deb \
    "$T/dl/sasquatch_1.0_amd64.deb" efbc92bd27594e01211e1b582f105a463a0017360a0746a93de3f283906ade95
  apt-get install -y -qq "$T/dl/sasquatch_1.0_amd64.deb" >/dev/null
fi
pipx list --short 2>/dev/null | grep -q '^jefferson ' || pipx install jefferson >/dev/null
pipx list --short 2>/dev/null | grep -q '^ubi-reader ' || pipx install ubi_reader >/dev/null
# unblob finds extractors on PATH; /usr/local/bin is on every session's default PATH
for b in jefferson ubireader_extract_files ubireader_extract_images; do ln -sfn "$T/bin/$b" "/usr/local/bin/$b"; done
# debugfs and partclone.restore live in /sbin, which is not on a normal user's PATH (REA runs as george)
for b in debugfs partclone.restore; do ln -sfn "/sbin/$b" "/usr/local/bin/$b"; done

step "unblob external dependencies"
"$T/bin/unblob" --show-external-dependencies 2>&1 | tail -25 || true

step "DONE"
