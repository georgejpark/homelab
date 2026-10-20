# HP Z8 G4 — BIOS & Linux Tools (pve2)

Investigated 2026-07-30.

## ✅ BIOS IS ALREADY CURRENT — NOTHING TO DO

```bash
root@pve2:~# dmidecode -s bios-version && dmidecode -s bios-release-date
P60 v03.00
04/15/2026
```

**Version 03.00 is the newest release.** Do not flash — updating to the same version is pure risk with zero gain.

| SoftPaq | Version | Released | Notes |
|---|---|---|---|
| sp156535 | 02.95 | 2025-01-03 | Windows .exe. **Older — do not use, this is a downgrade** |
| **sp173131** | **03.00 Rev A** | 2026-05-22 | "HP Z6/8-G4 WKS System BIOS For Linux". Fixes critical security vulns + Thunderbolt power-cycling. **This is what's already installed.** |

Both packages yield a 16,777,216-byte (16MB) `.bin`: `P60_0295.bin` / `P60_0300.bin`.

## Reference: how to flash if ever needed in future

**Use the F10 method, NOT hp-flash.** The firmware does the write itself — no OS, no kernel module, no distro-compatibility risk.

1. USB must be **FAT32** (HP's F10 updater won't read exFAT/NTFS)
2. Place the `.bin` at exactly `EFI/HP/BIOS/New/` on the USB
3. Shut down VMs (`qm list` / `pct list`), power off
4. USB in a **rear motherboard** USB port, power on, press **F10** at the HP logo
5. **Main → Update System BIOS**
6. Never interrupt power; don't pull the USB; it may reboot several times
7. Verify after: `dmidecode -s bios-version`

**⚠️ BIOS updates typically reset settings to defaults** — recheck customizations afterward.

### Emergency BIOS recovery (if a flash ever fails)

Rename the `.bin` to `BIOS_IMG.rcv`, put it in the USB **root** (no subfolder), then hold **Windows key + B**, press and hold power 2–3s, release power while still holding Win+B until the recovery screen appears. Must use a directly-attached keyboard.

## What HP actually provides for Linux (and what to skip)

The Z8 G4 needs **no HP drivers** for normal Linux operation — mainline kernel handles the chipset, NICs, USB, and the P840 natively. HP's Linux offerings are narrow:

| Tool | Verdict |
|---|---|
| **fwupd / LVFS** | ✅ Standard, safe. `apt install fwupd && fwupdmgr refresh && fwupdmgr get-updates` |
| **hp-wmi-sensors** (mainline kernel driver) | ✅ **Worth doing** — temp/fan monitoring, matters once 3× P100 are installed. `apt install lm-sensors && modprobe hp-wmi-sensors && sensors-detect --auto && sensors` |
| **HP Flash / RSU** (sp171387, `hpuefi-mod-3.07`) | ⚠️ Built for Ubuntu 22.04 / RHEL / SLED, **not Debian trixie**. Needs a DKMS kernel module. `hp-repsetup` (read/write BIOS settings from Linux) is interesting for the PCIe bifurcation question, but `hp-flash` (firmware writes) on an untested kernel is a bad risk. |
| HP Performance Advisor, Sure Start, MIK | ❌ Windows-only |
| iLO / BMC tooling | ❌ Doesn't exist on workstations (ProLiant-only) |

Sources: [HP Linux Tools catalog](https://ftp.hp.com/pub/caps-softpaq/cmit/linuxtools/HP_LinuxTools.html) · [Z8 G4 downloads](https://support.hp.com/us-en/drivers/hp-z8-g4-workstation/16449803) · [HP BIOS update doc](https://support.hp.com/us-en/document/ish_4123786-2338478-16) · [HP BIOS recovery doc](https://support.hp.com/us-en/document/ish_3966820-3438449-16)

## Thermal note for the GPU build

A [Proxmox forum thread about this exact board](https://forum.proxmox.com/threads/fan-control-lm-sensors-hp-workstation-cpu-temp-too-high.140349/) found lm-sensors reports **Tj-Max thresholds (~93°C high / 103°C crit), not the Xeon's real ~85°C TCase limit** — readings look scarier than reality. Their fix was setting **minimum fan speed to 20% in BIOS**. Worth doing before the P100s go in. No PWM-capable module exists for software fan control on this board — BIOS is the control point.

## USB drives inventory (pve2, as of 2026-07-30)

| Device | What it is | Notes |
|---|---|---|
| `sda1` | **FAT32, 128GB, ~101GB free** — large firmware/driver archive | Contains HP driver-CD ISOs, `sp171387` (HP Linux Tools), `sp173131/P60_0300.bin`, Dell Precision drivers, Cisco NX-OS images, NVIDIA/Intel/storage firmware. **Valuable — don't reformat.** `EFI/HP/BIOS/New/P60_0300.bin` was staged here then left unused. |
| `sdb` | **Dell diagnostics + Proxmox VE installer** (iso9660, label PVE, 2026-05-21) | `sdb2` = Dell EFI diags; `sdb3` = pve-installer.squashfs. Likely the media that installed this host. **Leave alone.** |

## Firmware inventory — pve2, audited 2026-07-30

| Device | Version | Latest | Verdict |
|---|---|---|---|
| BIOS | **P60 v03.00** (04/15/2026) | 03.00 | ✅ Current |
| **P840 RAID** | **4.52** | **7.00** | ⏸️ Only real gap. Needs HPE support entitlement to download. Best done **before** data lands on the array; not urgent |
| Mellanox ConnectX-3 Pro (`enp165s0`) | 2.40.5032 | 2.42.5000 | ⛔ **NOT POSSIBLE on this kernel — see below.** Also marginal gain; skip. |
| Intel X710 ×4 (`ens3f0-3`) | 9.00 / NVM 21.5.9 (mgmt 9.80) | — | ✅ fwupd: no updates exist |
| Intel X722 (`nic0`) | 4.11 (mgmt 4.1) | — | ✅ fwupd: no updates exist |
| WD SN850X NVMe | 620311WD | — | ✅ fwupd: no updates exist |
| UEFI dbx | 20230301 | 20260402 | ⏭️ **Skip** — can't apply (no ESP configured for fwupd), and **inert because Secure Boot is disabled**. dbx updates are irreversible |

```bash
# re-run the audit anytime
dmidecode -s bios-version
ssacli ctrl all show detail | grep -i "firmware version"
for i in $(ls /sys/class/net | grep -v lo); do printf "%-16s " "$i"; ethtool -i $i 2>/dev/null | grep firmware-version; done
nvme list
fwupdmgr get-updates
```

**Conclusion: firmware is in good shape.** Everything fwupd manages is current. Keep Secure Boot **disabled** (required for the unsigned `hpuefi` module).

### ⛔ Mellanox CX3 firmware flashing is NOT possible on Proxmox kernel 7.0.14 — do not retry

Attempted 2026-07-30 on pve2. **Every path fails:**

| Attempt | Result |
|---|---|
| NVIDIA MFT 4.31 `./install.sh` (with `dkms`) | ❌ `Bad return status for module build on kernel: 7.0.14-6-pve` |
| `./install.sh --without-kernel` then `flint -d a5:00.0 query` | ❌ `Cannot open Device` |
| `flint -d 0000:a5:00.0 query` | ❌ same |
| `mst start` | ❌ `modprobe: FATAL: Module mst_pci not found` |
| Debian `mstflint` 4.31.0+1-4 | ❌ pulls the same broken DKMS package (and segfaults on CX3 Pro anyway — [upstream bug #1157](https://github.com/Mellanox/mstflint/issues/1157)) |

**Root cause:** Mellanox's kernel module predates kernel 7.0.x. No flag-level workaround exists.

⚠️ The failed install leaves `kernel-mft-dkms` half-configured, breaking every later `apt` command. Cleanup:

```bash
apt remove --purge -y kernel-mft-dkms mstflint; dkms remove kernel-mft-dkms/4.31.0 --all 2>/dev/null; apt --fix-broken install -y; apt autoremove -y; apt update
```

**Only viable route if ever truly needed:** boot an Ubuntu 22.04 live USB (old enough kernel for MFT to build), flash there, then **two full COLD boots** (power off, not reboot — skipping this is why people think CX3s are bricked).

**Recommendation: don't.** 2.40.5032 → 2.42.5000 only fixes RoCE/SR-IOV bugs, which this build doesn't use. The card links at 40G and carries VLAN 10 + 20 fine.

*(Note: pve3's Mellanox is already at 2.42.5000 — only pve2's is on 2.40.5032. Mixed versions are fine for plain Ethernet.)*

### Harmless output to ignore on this host

`grub-probe: error: unknown filesystem` appears during kernel package operations. **GRUB is not the bootloader** — `proxmox-boot-tool` handles UEFI boot from ZFS. GRUB simply can't read ZFS. Safe to ignore.

## Open items

- [ ] At next reboot, enter F10 and check **PCIe x8x8 bifurcation** (needed for the Azure FPGA cards — see [07-azure-fpga-smartnic.md](07-azure-fpga-smartnic.md))
- [ ] At same time, set **minimum fan speed to 20%** before the P100 install
- [ ] Optional: `lm-sensors` + `hp-wmi-sensors` for temp monitoring
- [ ] Optional cleanup: remove the unused staged BIOS from the USB
      `mount /dev/sda1 /mnt/sda1 && rm -rf /mnt/sda1/EFI/HP && umount /mnt/sda1`
