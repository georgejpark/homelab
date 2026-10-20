# pve2 — GPU Passthrough Setup (for 3× Tesla P100)

Configured 2026-07-30. **Decision: PCIe passthrough to VMs**, not a host NVIDIA driver. Keeps the Proxmox host clean and allows different CUDA versions per VM.

## ✅ Status: infrastructure LIVE — 308 IOMMU groups

Verified before the cards were even installed. High group count = PCIe ACS working, so devices can be assigned individually rather than in clumps.

## BIOS prerequisites (already satisfied)

| Setting | Value |
|---|---|
| Virtualization Technology (VTx) | Enable ✅ |
| Virtualization Technology for Directed I/O (VTd) | Enable ✅ |
| **PCIe ACS** | **Enable** ✅ ← the reason IOMMU groups are cleanly separated |

Read via `hp-repsetup` — see [09-bios-settings-dump.md](09-bios-settings-dump.md).

## ⚠️ pve2 boots via proxmox-boot-tool + ZFS — NOT GRUB

```
System currently booted with uefi
<redacted> is configured with: uefi (versions: 7.0.14-6-pve, 7.0.14-8-pve)
root=ZFS=rpool/ROOT/pve-1 boot=zfs
```

**`/etc/default/grub` exists but is COMPLETELY IGNORED.** Editing it does nothing. The real kernel cmdline is **`/etc/kernel/cmdline`**, applied with `proxmox-boot-tool refresh`.

## What was done

**1. Kernel cmdline** (`/etc/kernel/cmdline`, backup at `.bak`):

```
root=ZFS=rpool/ROOT/pve-1 boot=zfs  intel_iommu=on iommu=pt
```

```bash
proxmox-boot-tool refresh
```

**2. VFIO modules** appended to `/etc/modules`:

```
vfio
vfio_iommu_type1
vfio_pci
```

**3. Blacklist** `/etc/modprobe.d/blacklist-nvidia.conf`:

```
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
blacklist rivafb
```

Then `update-initramfs -u -k all`.

## Verify

```bash
dmesg | grep -e DMAR -e IOMMU | head -5
find /sys/kernel/iommu_groups/ -type l | wc -l     # expect hundreds
lsmod | grep vfio
```

## Remaining steps once the P100s are physically installed

1. Identify them: `lspci -nn | grep -i nvidia` → note vendor:device IDs (P100 = `10de:15f8` or similar)
2. Bind to vfio-pci by ID in `/etc/modprobe.d/vfio.conf`:
   `options vfio-pci ids=10de:xxxx disable_vga=1`
3. `update-initramfs -u -k all` and reboot
4. Confirm `lspci -k` shows `Kernel driver in use: vfio-pci` on each card
5. In the Proxmox GUI: VM → Hardware → Add → PCI Device → select each GPU (check "All Functions", "PCI-Express")
6. Install the NVIDIA driver **inside the VM**, not on the host

**Display:** pve2 has an AMD Radeon (`amdgpu`, seen in `sensors` as `amdgpu-pci-7700`) which keeps the host console — convenient, since P100s have no display outputs.

## ⚠️ Kernel upgrade caveat

`proxmox-headers-7.0.14-8-pve` is installed alongside the running `7.0.14-6-pve`. **On booting the newer kernel, the `hpuefi` module must be rebuilt** (it's compiled per-kernel):

```bash
cd /root/hplinuxtools/non-rpms/hpuefi-mod-3.07 && make clean && make && cp hpuefi.ko /lib/modules/$(uname -r)/extra/ && depmod -a && systemctl restart hpuefi
```

DKMS would automate this if it becomes annoying.

## 🔥 Networking discovery: both hosts have 40GbE

`lspci -k` on pve2 shows a **Mellanox ConnectX-3 Pro** (`a5:00.0`, `mlx4_core`) — the same card pve3 has. Plus an **Intel X710 quad-port 10GbE SFP+** (`8d:00.0-.3`, `i40e`).

```
pve2 (P840 + 8 SAS SSDs)  ←── QSFP+ DAC cable (~$20) ──→  pve3
        40 GbE                                            40 GbE
```

**A direct 40Gb link between the storage host and compute host needs no switch** — just one QSFP+ DAC cable. Both cards have a free port. This is the right backbone for pulling datasets off the SAS array into GPU workloads.

### Full pve2 NIC inventory (all drivers in-kernel, nothing to install)

| Device | Card | Driver |
|---|---|---|
| `00:1f.6` | Intel I219-LM 1GbE (onboard) | `e1000e` |
| `04:00.0/.2` | Intel X722 (onboard) | `i40e` |
| `8d:00.0–.3` | Intel X710 quad-port 10GbE SFP+ | `i40e` |
| `a5:00.0` | Mellanox ConnectX-3 Pro dual 40GbE | `mlx4_core` |

## ⚠️ Storage note (ZFS root)

pve2's root is on **ZFS** (`rpool/ROOT/pve-1`). **Do not layer ZFS on top of the P840's hardware RAID logical drive** — ZFS wants raw disks. Either:
- LVM(-thin) on the hardware RAID logical drive, or
- put the P840 in HBA mode and let ZFS manage the 8 SSDs directly

Decide when the backplane cable arrives — see [01-backplane-power-cable.md](01-backplane-power-cable.md).
