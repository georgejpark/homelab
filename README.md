# Homelab: a Proxmox AI/storage build from used enterprise parts

This repository is the working documentation of a small Proxmox homelab assembled from second-hand enterprise hardware. The main host, **pve2**, is an HP Z8 G4 workstation board with two Xeon Platinum 8269CY (52 cores / 104 threads), an HP P840 12G SAS RAID controller feeding a DL380p G8 eight-bay SAS backplane with eight 800 GB SAS SSDs, Intel X710 10GbE and Mellanox ConnectX-3 Pro 40GbE networking, and PCIe passthrough configured for GPUs. A second host, **pve3**, carries a Mellanox 40GbE card in production, a QLogic quad 10GbE card, two Microsoft Azure Catapult v2 "Storey Peak" FPGA cards (Stratix V) with working JTAG, and an NVIDIA CMP 170HX. A third host, **pve5**, is a Lenovo ThinkStation P920 with two Xeon Platinum 8168 (48 cores / 96 threads) that runs an unprivileged LXC container dedicated to reverse engineering with [REA](https://github.com/morluto/rea) and Ghidra. The documents record what was tried, what failed, and why, so nothing has to be re-derived. The lab is operated day to day with an AI coding agent (Claude Code); the [`CLAUDE.md`](CLAUDE.md) at the root is the agent's standing brief and is published as it is used.

## Hardware

| Host | Machine | CPUs | Memory | Notable cards and storage | Role |
|---|---|---|---|---|---|
| pve2 | HP Z8 G4 (board + DPS-1125BB 1125 W PSU), Proxmox on ZFS root | 2× Xeon Platinum 8269CY, 52c/104t | 64 GB ECC RDDR4 (2 of 24 slots) | HP P840 12G SAS RAID (4 GB FBWC, fw 4.52); HP DL380p G8 8×SFF SAS backplane (643705-001) + 8× Hitachi 800 GB SAS SSD; Intel X710 quad 10GbE; Mellanox ConnectX-3 Pro 40GbE; Intel X722 / I219-LM; AMD Oland XT for the console | Storage host and GPU host (VFIO passthrough live, 308 IOMMU groups) |
| pve3 | Separate host; the docs do not pin down the exact model (doc 13 calls it "the Dell") | — | — | Mellanox ConnectX-3 Pro 40GbE (MCX314A-BCCT, fw 2.42.5000, carries VLAN 20); QLogic QL41164HFCU quad 10GbE; 2× Azure Catapult v2 "Storey Peak" FPGA (Stratix V GS, 4 GB ECC DDR3L, 2× QSFP+); NVIDIA CMP 170HX (GA100) | Compute, FPGA development, CMP 170HX experiments |
| pve5 | Lenovo ThinkStation P920, Proxmox VE 9.2 | 2× Xeon Platinum 8168, 48c/96t | 30 GiB | 1 TB WD SN850X NVMe as ZFS pool `nvmepool` | Runs CT 101 `rea`: unprivileged Debian 13 LXC with Ghidra 12.1.4, REA from source and pinned lane tools |
| Dell Precision 7820 | Owned, not yet deployed | — | — | 950 W PSU, two full x16 slots | Planned second GPU box (max two cards) |

GPU plan: the documents were written around three NVIDIA Tesla P100 16 GB cards; on 2026-10-20 that was superseded by two CMP 170HX on pve2. The P100 material (slot map, power, cooling) is kept because it still applies to any passive datacenter card in a Z8 G4.

## What is documented

| File | What it covers |
|---|---|
| [docs/01-backplane-power-cable.md](docs/01-backplane-power-cable.md) | Powering a DL380p G8 SAS backplane from a Z8 G4: power path, expected 10-pin pinout, multimeter verification, first power-on procedure |
| [docs/02-sas-data-cabling.md](docs/02-sas-data-cabling.md) | P840 to backplane SFF-8643/SFF-8087 cable map and the `lsscsi` diagnostic table |
| [docs/03-gpu-installation.md](docs/03-gpu-installation.md) | Z8 G4 slot map for three passive GPUs, power budget at 120 V vs 240 V, EPS vs PCIe 8-pin, cooling; Dell 7820 layout |
| [docs/04-raid-card-status.md](docs/04-raid-card-status.md) | P840 verified outside a ProLiant: slot 255, no cache battery, HPE MCP repo quirks, `ssacli`/`ssaducli`/`ssa` and the day-one wear report |
| [docs/05-next-steps.md](docs/05-next-steps.md) | The ordered to-do list, recurring maintenance and open questions |
| [docs/06-pve3-network-cards.md](docs/06-pve3-network-cards.md) | pve3 NIC inventory; proving the Mellanox card is healthy; the Debian `mstflint` segfault; live topology |
| [docs/07-azure-fpga-smartnic.md](docs/07-azure-fpga-smartnic.md) | Identifying the Azure Catapult v2 "Storey Peak" card, its onboard FT232H JTAG, OpenOCD IDCODE readback, Quartus and recovery notes |
| [docs/08-hp-tools-and-bios.md](docs/08-hp-tools-and-bios.md) | Z8 G4 BIOS state, flash and recovery reference, HP Linux tools worth using, full firmware audit, why Mellanox flashing fails on kernel 7.0.14 |
| [docs/09-bios-settings-dump.md](docs/09-bios-settings-dump.md) | Reading and writing Z8 G4 BIOS settings from Linux with `hp-repsetup` + `hpuefi`; bifurcation, VT-d/ACS, thermal baseline, fan "alarm" explained |
| [docs/10-gpu-passthrough-setup.md](docs/10-gpu-passthrough-setup.md) | VFIO passthrough on a ZFS-root Proxmox host that boots via `proxmox-boot-tool`; NIC inventory; the ZFS-on-hardware-RAID warning |
| [docs/11-shopping-list.md](docs/11-shopping-list.md) | Prioritized parts list with approximate costs |
| [docs/12-tls-certificate.md](docs/12-tls-certificate.md) | Self-signed certificate for the Proxmox web UI, the 397-day limit, renewal and client trust |
| [docs/13-cmp-170hx-gpu.md](docs/13-cmp-170hx-gpu.md) | NVIDIA CMP 170HX on Proxmox: `nvidia-open` install, thermals, and the 8 GB to 64 GB driver-patch unlock with its risks |
| [docs/14-pve5-rea-server.md](docs/14-pve5-rea-server.md) | pve5 host record, recreating the REA container, pinned tool versions, verification results, gotchas, maintenance |
| [docs/15-github-repos-on-proxmox.md](docs/15-github-repos-on-proxmox.md) | Decision (2026-10-20) to run the owner's GitHub projects on Proxmox rather than a paid cloud: verdict scale per repo, backup locations, CMP 170HX facts still to verify. In progress |
| [CLAUDE.md](CLAUDE.md) | The standing brief for the AI agent that helps run the lab: facts not to re-derive, conventions, pending decisions |

Scripts in [scripts/rea-setup/](scripts/rea-setup/):

| Script | Purpose |
|---|---|
| `build-ghidra-mac-natives.sh` | Builds the Apple Silicon decompiler, sleigh and GNU demangler binaries that the official Ghidra zip does not ship |
| `provision-rea-ct-base.sh` | Idempotent base provisioning of the REA LXC: packages, JDK 21, Node (checksum-verified), Ghidra (checksum-verified), REA from source, Claude Code |
| `provision-rea-ct-linux-lanes.sh` | Installs REA's Linux-only tools at pinned, digest-verified versions (pwntools, tshark, sigrok, binwalk, unblob, mitmproxy, WABT, JADX, apktool) |
| `verify-rea-ct-lanes.sh`, `verify-rea-mac-lanes.sh` | Functional self-tests of every analysis lane on the container and on the Mac, using only self-made inputs |

The REA checkout itself (`rea/`, a clone of [morluto/rea](https://github.com/morluto/rea)) is not part of this repository; `CLAUDE.md` and doc 14 refer to it as it exists on the lab machines.

## Lessons learned

1. **Never put ZFS on top of a hardware-RAID logical drive.** ZFS wants raw disks. Either use LVM-thin on the P840 array or put the controller in HBA mode (docs 05, 10).
2. **On a Proxmox host that boots from ZFS via `proxmox-boot-tool`, `/etc/default/grub` is ignored.** Kernel parameters go in `/etc/kernel/cmdline`, followed by `proxmox-boot-tool refresh`. The `grub-probe: unknown filesystem` message during kernel updates is harmless (docs 08, 10).
3. **Mellanox ConnectX-3 firmware cannot be flashed on kernel 7.0.14.** NVIDIA MFT's DKMS module does not build, `flint` cannot open the device, and Debian's `mstflint` 4.31 segfaults on ConnectX-3 Pro. A failed attempt leaves `kernel-mft-dkms` half-configured and breaks `apt` until purged. The only route is an older live USB, and then two cold boots (docs 06, 08).
4. **A DL380p G8 backplane in a Z8 G4 must be powered from the Molex drops on the Z8 power distribution cable, never the 6-pin GPU outputs** (12 V only, no 5 V). The published 10-pin pinout is Gen6-era, so map it with a multimeter on the actual board before wiring (doc 01).
5. **A P840 outside a ProLiant reports slot 255 and has no cache battery.** That is normal: use `slot=255`, accept write-through, and rely on SSD Smart Path (doc 04).
6. **HPE's MCP apt repo on Debian trixie needs HTTPS, the `non-free` component (not `non-os`), and HPE's 2024 signing key.** Proxmox kernel headers are `proxmox-headers-$(uname -r)`, not `linux-headers-generic` (docs 04, 06, 09).
7. **Z8 G4 BIOS settings can be read and written from Linux** with `hp-repsetup` and the `hpuefi` module. The module is per-kernel and unsigned: rebuild it after every kernel upgrade and keep Secure Boot disabled (doc 09).
8. **Read `sensors`, not the BIOS event log, for current hardware state.** Two "missing fan" entries turned out to be historical; all six fans were spinning (doc 09).
9. **Passive datacenter GPUs need forced air and the right power connector.** The Tesla P100 takes an EPS 8-pin, not a PCIe 8-pin; a passive card thermal-shuts within a minute without a blower shroud. On a Z8 G4 the third x16 slot is dead without the second CPU, and three 250 W cards need a 240 V outlet (docs 03, 13).
10. **An Azure Catapult v2 card that is absent from `lspci` is not bricked.** It needs x8x8 bifurcation and a valid bitstream to enumerate; the real health test is the JTAG IDCODE, which is reachable through the FT232H behind the bracket's USB-B port with nothing but a USB cable (doc 07).
11. **The CMP 170HX 8 GB to 64 GB unlock is a kernel-driver patch, not a VBIOS flash.** It needs a cold power cycle to apply, must be re-run after every kernel upgrade, and the resulting 64 GB has no ECC (doc 13).
12. **Self-signed TLS certificates must be valid for at most 397 days** or macOS and Chrome reject them even when trusted. Used SAN-pull SAS drives often have 520-byte sectors and need `sg_format --size=512` before use (docs 02, 12).

## Status

As of 2026-10-20: all software and configuration work on pve2 and pve3 is complete and verified; the SAS array is waiting on about $75 of cables; the REA container on pve5 passes 15 of 15 lane checks; the GPU plan has moved from three Tesla P100s to two CMP 170HX on pve2.

## About the published copy

LAN addresses, domain names, MAC addresses, serial numbers and the SSH host-key fingerprint were replaced with placeholders (`10.10.0.x`, `*.example`, `xx:xx:xx:xx:xx:xx`, `<redacted>`). Model and part numbers are real. The hardware procedures here were worked out for these exact boards and revisions; verify before applying them elsewhere.

Licensed under [CC BY 4.0](LICENSE).
