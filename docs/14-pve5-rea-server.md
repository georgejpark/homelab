# pve5 + REA (Reverse Engineer Anything): host and container record

Set up **2026-10-13** by Claude Code. Covers the new Proxmox host **pve5**, the REA container **CT 101 `rea`** on it, and the matching REA setup on the Mac.

## pve5: the host

| | |
|---|---|
| Machine | **Lenovo ThinkStation P920** (`30BBS3JH00`) |
| CPUs | 2× **Xeon Platinum 8168** (24c each, **48c / 96t**) |
| RAM | 30 GiB |
| OS | Proxmox VE **9.2.21**, kernel `7.0.14-23-pve`, Debian 13 trixie |
| BIOS | **S04KT78A (2026-05-11)**. George updated it on 2026-10-13 from S04KT76A (2025-01-16). Afterwards VT-x and VT-d were still on (164 IOMMU groups), both CTs auto-started, and CT 101 kept 10.10.0.109. The flash took about an hour with two reboot cycles |
| IP | **`10.10.0.106`** on `vmbr0` (port `ens4f0`), gateway `10.10.0.254` |
| VLANs | `vlan10/20/30/40` on `ens4f0` → `10.{10,20,30,40}.0.106/24` |
| Storage | `local` (dir, ~110 GB), `local-zfs` (rpool, 117 GB), **`nvmepool`** (ZFS, 928 GB, WD_BLACK SN850X 1 TB) |
| GPU | AMD Oland (display only). No NVIDIA card |
| Other NICs | `enp94s0` / `enp94s0d1` (down), `nic0`/`nic1` (down) |
| Guests | CT 100 `pulse` (monitoring), **CT 101 `rea`** |
| SSH | `ssh pve5` → root, key `~/.ssh/id_ed25519` (the key whose comment is `george@pve3`) |

⚠️ pve5's apt sources enable `pve-enterprise`, `pve-no-subscription` **and** `pve-test` at the same time. Without a subscription, `apt update` on the host will show 401 errors for the enterprise repo. This was left unchanged.

## CT 101 `rea`: the REA workstation

| | |
|---|---|
| Template | `debian-13-standard_13.6-1_amd64`, **unprivileged**, `nesting=1`, `onboot=1` |
| Resources | 32 cores, 20 GiB RAM + 4 GiB swap, **100 GB rootfs on `nvmepool`** |
| IP | **`10.10.0.109/24` static** (set in Proxmox `net0` on 2026-10-13, gateway `10.10.0.254`), MAC `xx:xx:xx:xx:xx:xx`. .109 lies inside the AT&T DHCP range, so also reserve it there to stop the gateway handing it to another device |
| Users | `root` (key only, no password); **`george`** (same key, passwordless sudo). REA + Claude Code run as `george` |
| Passwords | `root` and `george` have a console/login password **set by George on 2026-10-13** (he knows it; deliberately not recorded in any file). Root over SSH stays **key-only** (`PermitRootLogin without-password`). george can SSH with key or password. Change with `ssh -t rea sudo passwd <user>` |
| SSH | `ssh rea` → `george@10.10.0.109`. Host key ED25519 `<redacted>` |
| Node | **24.18.0** official tarball in `/usr/local` (SHA-256 verified), npm 11.16.0. This is exactly `rea/.nvmrc` |
| Java | `openjdk-21-jdk-headless` 21.0.12.1 → `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64` |
| Ghidra | **12.1.4** at `/opt/ghidra_12.1.4_PUBLIC` (SHA-256 `ddac49f9…d4db` verified). Ships the `linux_x86_64` decompiler |
| Env | **`/etc/environment`**, seen by login shells, sudo and non-interactive SSH: `GHIDRA_INSTALL_DIR`, `JAVA_HOME`, all `REA_*` tool paths, plus tuning `GHIDRA_HEADLESS_MAXMEM=10G` (Ghidra heap; REA default is 2G), `REA_GHIDRA_STARTUP_TIMEOUT_MS=900000`, and `TMPDIR=/var/tmp` (container `/tmp` is a 16G RAM tmpfs). Verified: the Ghidra JVM runs with `-Xmx10G` and its project under `/var/tmp` |
| Snapshots | **`configured-20261013`** (15:46): **the final state to roll back to**, with Claude login, static IP and final CLAUDE.md/memory/skills: `ssh pve5 pct rollback 101 configured-20261013`. `baseline-20261013` (14:38) has the tools only |
| REA | source checkout **`/opt/rea`** (owned by george), `main` @ `69bd81f7f`; `/usr/local/bin/rea` → `/opt/rea/scripts/rea.mjs` |
| Claude Code | 2.1.296 at `~george/.local/bin/claude` (native installer). REA registered in `~george/.claude.json`; skill in `~george/.claude/skills/` |

Recreate from scratch (on pve5, as root):

```bash
pveam download local debian-13-standard_13.6-1_amd64.tar.zst
pct create 101 local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst \
  --hostname rea --tags rea --unprivileged 1 --features nesting=1 \
  --cores 32 --memory 20480 --swap 4096 --rootfs nvmepool:100 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp,firewall=1 \
  --ostype debian --onboot 1 --timezone host \
  --ssh-public-keys /root/rea-ct-authorized_keys.pub --start 1
```

Then run the base provisioning script from the Mac. It is idempotent: locale, base packages, JDK 21, user george, Node 24.18.0, Ghidra, `/etc/environment`, REA clone + `npm ci` + `npm run build:cached`, and Claude Code. A copy is kept at [`rea-setup/provision-rea-ct-base.sh`](../scripts/rea-setup/provision-rea-ct-base.sh):

```bash
ssh root@10.10.0.109 'bash -s' < ~/Desktop/AI-Server/rea-setup/provision-rea-ct-base.sh
```

Snapshot before risky work: `ssh pve5 pct snapshot 101 before-<what>`. Roll back with `pct rollback 101 before-<what>`.

### Lane tools in the container (versions pinned to REA's docs)

Installed by [`rea-setup/provision-rea-ct-linux-lanes.sh`](../scripts/rea-setup/provision-rea-ct-linux-lanes.sh) (idempotent; run as root in the CT). Every `REA_*` path is in `/etc/environment`.

| Lane | Tool | Where | REA variable |
|---|---|---|---|
| ELF layout, recorded crashes | pwntools **4.15.0** + pyelftools 0.33 + unicorn 2.1.2 | `/opt/rea-tools/pwntools-venv` | `REA_PWNTOOLS_PYTHON` |
| Packet captures / pcap summaries | TShark + capinfos **4.4.19** (apt), prlimit | `/usr/bin` | `REA_TSHARK_COMMAND`, `REA_CAPINFOS_COMMAND` |
| Logic/signal recordings | sigrok-cli **0.7.2** (apt) | `/usr/bin` | `REA_SIGROK_COMMAND` |
| Firmware | binwalk **3.1.0** (cargo `--locked`), unblob **26.6.4** (pipx) + all 15 extractors (sasquatch .deb, jefferson, ubi_reader, erofs, partclone, unar, …) | `/opt/rea-tools/bin` | `REA_BINWALK_COMMAND`, `REA_UNBLOB_COMMAND` |
| Native mitmproxy captures | mitmdump **12.2.3** (pipx) | `/opt/rea-tools/bin` | `REA_MITMDUMP_COMMAND` |
| WASM | WABT **1.0.42** (GitHub release, digest-verified) | `/opt/rea-tools/wabt-1.0.42` | `REA_WABT_BIN_DIRECTORY` |
| Android code | jadx-headless-mcp **0.7.1** (digest-verified) + JDK 21 | `/opt/rea-tools/` | `REA_JADX_MCP_JAR` |
| Android resources | apktool **2.7.0** (apt) | `/usr/bin` | `REA_APKTOOL_COMMAND` |
| Browser (isolated) | chromium 155 (apt). The sandbox works as george | `/usr/bin` | `REA_BROWSER_EXECUTABLE` |

Not installed (optional): **pwndbg** (adds debugger mapping context to recorded crashes; REA verified it with GDB 13.1 + pwndbg 2026.09.15), Frida server, ILSpy, wakaru.

✅ **15/15 checks pass**, re-verified after the BIOS update, with [`rea-setup/verify-rea-ct-lanes.sh`](../scripts/rea-setup/verify-rea-ct-lanes.sh) (copy at `/opt/rea-tools/verify-lanes.sh`). They cover: Ghidra decompile, ELF layout, recorded crash, EVM, firmware regions, unblob extractors as george, pcap summary, packet fields, signal decoders + decode, WASM, mitmproxy, Android package + resources, and sandboxed Chromium. `debugfs` and `partclone.restore` are symlinked into `/usr/local/bin`, because george's PATH has no `/sbin`. Run it with `ssh rea 'bash -s' < ~/Desktop/AI-Server/rea-setup/verify-rea-ct-lanes.sh`.

## The Mac side

| | |
|---|---|
| REA | source checkout `~/Desktop/AI-Server/rea` (same commit). `rea` on PATH via `npm link` → `/opt/homebrew/bin/rea` |
| Java | Homebrew `openjdk@21` (keg-only), `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home` |
| Ghidra | `~/tools/ghidra_12.1.4_PUBLIC` + **locally built `mac_arm_64` natives**: decompiler, sleigh, and the GNU C++ demanglers v2.41/v2.24. The official zip ships none for macOS. Rebuild with [`rea-setup/build-ghidra-mac-natives.sh`](../scripts/rea-setup/build-ghidra-mac-natives.sh) |
| Shell | `~/.zshrc` block marked `>>> REA … <<<` (backup: `~/.zshrc.bak-20261013`) |
| SSH | `~/.ssh/config` deduplicated (backup: `~/.ssh/config.bak-20261013`); aliases `pve5`, `rea` |
| Claude Code MCP | **`rea`** → `/opt/homebrew/bin/rea mcp` (local) · **`rea-linux`** → `ssh -T -o BatchMode=yes … rea /usr/local/bin/rea mcp` (container). Both user scope |
| Lane tools | WABT **1.0.42** (`~/tools/wabt-1.0.42`), jadx-headless-mcp **0.7.1** (`~/tools/jadx-headless-mcp/`), both digest-verified. Paths are in `~/.zshrc` and the `rea` MCP `env` |
| Claude instructions | Global `~/.claude/CLAUDE.md` (George's command conventions + Claude Code habits). `AI-Server/CLAUDE.md` (always-on REA rules). `rea/CLAUDE.md` (full REA manual). Memory: `MEMORY.md` + 9 entries. All verified loading via fresh headless sessions |
| Skills | `~/.claude/skills/`: `reverse-engineer-anything` (REA's own), `rea-status`, `rea-update`, `rea-investigate` |
| Verified | ✅ **9/9 lanes** with [`rea-setup/verify-rea-mac-lanes.sh`](../scripts/rea-setup/verify-rea-mac-lanes.sh): Ghidra decompile, Mach-O, plist, app artifact, SQLite, JS/Electron app, WASM, Android/JADX, Chrome over CDP |

## ✅ Verified 2026-10-13

- `rea doctor --provider ghidra --json` → **healthy** on both hosts
- End-to-end `rea decompile … --provider ghidra` of a test binary: Mac arm64 Mach-O **23 s** cold, container x86-64 ELF **12 s** cold. Pseudocode correct on both
- Raw MCP handshake (`initialize` + `tools/list`): **193 tools**, zero non-JSON stdout lines, locally and over SSH
- `claude mcp list` → `rea` ✔ Connected, `rea-linux` ✔ Connected

## Gotchas hit (so they aren't re-debugged)

| Symptom | Cause → fix |
|---|---|
| Mac says `Host is down` for a new LAN IP that the host can ping | Stale **incomplete ARP** entry on the Mac (from an earlier LAN sweep). Fix: ping the Mac *from* the target, or wait |
| Ghidra decompiler build fails: `'bfd.h' file not found` | Passing two goals (`make ghidra_opt sleigh_opt`) makes the Makefile fall back to the BFD-based dependency set. **Build each target in its own `make` call** |
| REA MCP registration on the Mac has a `…/Cellar/openjdk@21/<version>/…` `JAVA_HOME` | `rea setup` records the resolved path. It was re-pointed to the stable `/opt/homebrew/opt/openjdk@21/…` path. **Re-check after any re-run of `rea setup`** |
| `ssh -G` prints "Pseudo-terminal will not be allocated" | Harmless. The MCP bridge passes `-T` anyway |
| Unblob lists extractors as ✓ for root but REA (as george) can't find them | `/sbin` isn't on george's PATH. Symlink them into `/usr/local/bin`; the lane test now checks this *as george* |
| C++ names stay mangled in Ghidra on the Mac | The Ghidra zip has no arm64 GNU demangler. Built by `rea-setup/build-ghidra-mac-natives.sh` |
| `binary_session` says apktool/adb are `provider_missing` | Reporting quirk. `inspect_apktool_client` works; confirm by calling the tool |

## Maintenance

- **Update REA on both hosts together**, and keep them on the same commit. Procedure: `rea/CLAUDE.md`.
- **Upgrading Ghidra** means re-downloading, **rebuilding the Mac natives** (`bash rea-setup/build-ghidra-mac-natives.sh <new dir>`), and updating `GHIDRA_INSTALL_DIR` in `~/.zshrc`, `/etc/environment` and both MCP registrations (re-run `rea setup --client claude_code --yes`).
- The container IP is static (10.10.0.109). If you ever change it, update `HostName` under `Host rea` in `~/.ssh/config`. The `rea-linux` registration uses the alias, so it follows automatically.
