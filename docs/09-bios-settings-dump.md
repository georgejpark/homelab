# pve2 BIOS Settings — via hp-repsetup (2026-07-30)

**HP Linux Tools work on Proxmox/Debian trixie.** Full BIOS settings are now readable/writable from the shell — no reboot needed.

## Working setup (reproducible)

```bash
# 1. Get HP Linux Tools 3.26
cd /root && mkdir -p hplinuxtools && cd hplinuxtools
wget https://ftp.hp.com/pub/softpaq/sp171001-171500/sp171387.tgz && tar xzf sp171387.tgz
cd non-rpms && tar xzf hp-flash-3.26_x86_64.tgz && tar xzf hpuefi-mod-3.07.tgz

# 2. Kernel headers (Proxmox-specific package names)
apt install -y build-essential proxmox-default-headers proxmox-headers-$(uname -r)

# 3. Build + load the kernel module (BUILDS FINE on 7.0.14-6-pve)
cd /root/hplinuxtools/non-rpms/hpuefi-mod-3.07 && make
insmod hpuefi.ko && sh mkdevhpuefi     # creates /dev/hpuefi (char dev, major 508)

# 4. Read all BIOS settings
cd /root/hplinuxtools/non-rpms/hp-flash-3.26_x86_64
./builds/hp-repsetup.u2404 -g -a /root/HpSetup.txt
```

**Use the `u2404` build** — Debian trixie's glibc 2.41 runs it cleanly. (`u2510` is likely too new; HP's README lists U24 as newest supported and explicitly says "Ubuntu (Debian compat)".)

✅ **Made persistent** via `/etc/systemd/system/hpuefi.service` (modprobe + mknod at boot) with the module copied to `/lib/modules/$(uname -r)/extra/`. Verified `active` with `/dev/hpuefi` present.

⚠️ **Must be rebuilt after any kernel upgrade** — it's compiled per-kernel:
```bash
cd /root/hplinuxtools/non-rpms/hpuefi-mod-3.07 && make clean && make && cp hpuefi.ko /lib/modules/$(uname -r)/extra/ && depmod -a && systemctl restart hpuefi
```

⚠️ **Secure Boot must stay disabled.** The module is unsigned and taints the kernel (`module verification failed: signature and/or required key missing`). Harmless today since Secure Boot is off, but enabling it would break `hp-repsetup`.

⚠️ **`hp-flash` is deprecated by HP** as of 15-Jan-2026 — they recommend fwupd for firmware. Only `hp-repsetup` is worth using.

## ✅ RESOLVED: fans are fine (earlier alarm was a misread)

The BIOS Event Log contains historical `520-Memory fan(2) not detected` (last 07/27/2026) and `513-Front Chassis fan not detected` (last 07/06/2026) entries. **These are a historical log, not current state.**

Live sensor readings on 2026-07-30 show **all six fans present and spinning**:

```
CPU0 Fan:            2670 RPM      Memory Fan0:  2926 RPM
CPU1 Fan:            2686 RPM      Memory Fan1:  3146 RPM
Rear Chassis Fan0:   1982 RPM
Front Chassis Fan0:  1419 RPM
```

No fans need sourcing. Lesson: read `sensors`, not the event log, for current hardware state.

## ✅ Thermal baseline (idle, 2026-07-30, pre-GPU)

```
CPU0: 38°C   CPU1: 29°C   System Ambient: 23°C
All 52 cores: 22–35°C   (high 87°C, crit 93°C)
NVMe: 27.9°C   PCH (Lewisburg): 34°C   amdgpu edge: 29°C
```

Idling ~50°C below throttle. Healthy headroom for the GPU install.

## Sensor monitoring (working)

```bash
apt install -y lm-sensors && modprobe hp_wmi_sensors && sensors
```

`hp_wmi_sensors` is a **mainline kernel driver** — no HP download needed. Exposes HP's own fan RPM + temp + ambient sensors. Reported adapters: `hp_wmi_sensors-virtual-0`, `coretemp-isa-0000/0001`, `hp-isa-0000`, `nvme-pci-7e00`, `amdgpu-pci-7700`, `pch_lewisburg-virtual-0`.

## ✅ Confirmed hardware

| | |
|---|---|
| CPUs | **2× Intel Xeon Platinum 8269CY** @ 2.50GHz, 26c each → **52 cores / 104 threads** |
| Cache | 1664KB L1 / 26MB L2 / 36608KB L3 per CPU |
| Memory | **2× 32GB Micron** (CPU0-DIMM1, CPU1-DIMM1) — 64GB total, 22 of 24 slots empty |
| System Board ID | 81C7 |
| TPM | 2.0 |
| BIOS | P60 v03.00 (updated 02.91 → 03.00 on 07/09/2026, Successful) |
| Embedded LAN MACs | AMT xx:xx:xx:xx:xx:xx · X722 xx:xx:xx:xx:xx:xx |

**Second CPU is present** → the 3× P100 plan in [03-gpu-installation.md](03-gpu-installation.md) is viable (3rd GPU requires dual CPUs).

## ✅ PCIe bifurcation IS available — answers the FPGA question

| Slot | Type | Bifurcation options | Current |
|---|---|---|---|
| 1 | x8 | Auto / x8 / x4x4 | **Auto** |
| 2 | **x16** | Auto / **x8x8** / x4x4x4x4 | **Auto** |
| 3 | **x16** | Auto / **x8x8** / x4x4x4x4 | **Auto** |
| 4 | **x16** | Auto / **x8x8** / x4x4x4x4 | **Auto** |
| 5 | x4 | (none) | — |
| 6 | **x16** | Auto / **x8x8** / x4x4x4x4 | **Auto** |
| 7 | x4 | (none) | — |
| Personality Slot CPU 0/1 | — | Auto / x8 / x4x4 | Auto |

The Azure Storey Peak FPGA cards need **x8x8** (they present as two PCIe devices — see [07-azure-fpga-smartnic.md](07-azure-fpga-smartnic.md)). All four x16 slots support it. Try setting the target slot explicitly to `x8x8` rather than `Auto`.

All slots are **Enabled**, all speeds **Auto**, all Option ROM download **Enabled**.

## Virtualization / passthrough — all good for GPU passthrough

| Setting | Value |
|---|---|
| Virtualization Technology (VTx) | **Enable** ✅ |
| Virtualization Technology for Directed I/O (VTd) | **Enable** ✅ |
| PCIe ACS | **Enable** ✅ (clean IOMMU groups) |
| NUMA | Enable |
| Sub-NUMA Clustering | Enable |
| Intel Hyper-Threading | Enable |
| Turbo Mode | Enable |
| Active CPU Cores Per Processor | All |

## Thermal settings (change before the GPU install)

| Setting | Current | Recommendation |
|---|---|---|
| Increase Idle Fan Speed(%) | **50** | already good (forum suggested ≥20) |
| **Increase PCIe Idle Fan Speed(%)** | **0** | ⬆️ **raise before P100s** |
| **PCIe Idle Fan Tracking mode** | **Disable** | ⬆️ **enable before P100s** |
| Performance Control | High Performance Mode | fine |
| Workload Configuration | I/O-Focused | fine |

## ⚠️ Admin password is set

```
Admin Password Present    *Yes
Power-On Password Present  No
```

Reading settings (`-g`) works without it. **Writing settings (`-s`) requires `-p <admin_password>`.**

## Other notable settings

- Secure Boot **Disabled**, Legacy Support **Disabled** (fine for Proxmox)
- Fast Boot **Enabled**
- Option ROM Launch Policy: **All UEFI**
- SATA + sSATA controllers **Enabled**, both in **RAID Mode**
- After Power Loss: **Power Off** (consider "Power On" or "Previous State" for a server role)
- UEFI Boot Order: `HDD:SLOT2:1`, `HDD:USB:1`, `CDROM:SATA:1`, `HDD:NEW:1`
- Wake On LAN: Boot to Normal Boot Order
- BIOS Rollback Policy: Unrestricted
- PCIE Max Read Request Size: Auto · PCIE MMIO Assignment: Auto · 1TB Memory Cap: Auto

## Changing a setting (when needed)

Edit `/root/HpSetup.txt` — move the `*` to the desired option — then:

```bash
./builds/hp-repsetup.u2404 -s /root/HpSetup.txt -p <admin_password>
```

⚠️ Note the ASCII (`-a`) file **cannot be re-imported by other HP tools** per the help text. For set operations consider omitting `-a` (default is Unicode UCS-2). Test carefully; a full dump is already saved at `/root/HpSetup.txt` (19,342 bytes, 1098 lines).

## Other HP Linux packages evaluated — all rejected

| Package | Verdict |
|---|---|
| `sp146955.tgz` (414MB, on USB) | ❌ Just `nvidia-525.105.17-1.x86_64.rpm` — RHEL format, won't install on Debian, and 525 is 2023-era |
| `hpds-repo-config-11-09-21` (on USB) | ❌ Adds `deb https://repos.datascience.hp.com/ubuntu/focal /` — **HP Data Science Stack for Ubuntu 20.04, dated Nov 2021.** Adding a 5-year-old Ubuntu focal repo to Debian trixie invites dependency conflicts. Do not add. |
| `hp_drivercd_*.iso` (ubuntu16/rhel6.9/rhel7.4/sled11sp3) | ❌ 2017-era; mainline kernel covers this board natively |
| HP Performance Advisor / Image Assistant / MIK | ❌ Windows-only |
| HPE MCP server tools (`hp-health`, `hponcfg`, `amsd`) | ❌ ProLiant-only; no BMC on a workstation |

**Conclusion: `hp-repsetup` + `fwupd` + `hp_wmi_sensors` is the complete useful set for a Z8 G4 on Linux.**

## Also present: an AMD GPU

`sensors` reports `amdgpu-pci-7700` (edge 29°C, pwm1 38%, sclk/mclk 300MHz) — an AMD Radeon is installed, presumably driving display output. Account for the slot it occupies when planning the 3× P100 layout; it also conveniently solves the "P100s have no display outputs" problem.

## Open items

- [ ] Raise `Increase PCIe Idle Fan Speed(%)` (currently 0) and enable `PCIe Idle Fan Tracking mode` — before GPUs
- [ ] Set the FPGA card's slot to explicit **x8x8** bifurcation and retest enumeration
- [ ] Locate the BIOS admin password (needed for any write)
- [ ] Optional: make `hpuefi` module load persistently across reboots
- [ ] Consider `After Power Loss` → `Power On` for unattended server behavior
