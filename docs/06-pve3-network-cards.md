# pve3 — Network Cards (RESOLVED: Mellanox card is healthy)

Second Proxmox host: **pve3** (separate from pve2, which holds the P840/storage build).

## Installed NICs

| PCI addr | Card | ID |
|---|---|---|
| 00:1f.6 | Intel I219-LM 1GbE (onboard) | 8086:15b9 |
| 03:00.0 | Intel I210 1GbE | 8086:1533 |
| 45:00.0-.3 | QLogic FastLinQ QL41000 10/25/40/50GbE (quad function) | 1077:8070 |
| d5:00.0 | **Mellanox ConnectX-3 Pro, dual-port 40GbE** | 15b3:1007 |

## The Mellanox card — verified 2026-07-30

**It is NOT an Azure/OEM card.** VPD reads as genuine retail Mellanox:

- Part number: **MCX314A-BCCT** (ConnectX-3 Pro Stand-up dual-port 40GbE QSFP)
- Serial: <redacted>, Engineering changes: AC
- VPD checksum: **good**
- PCIe: **Gen3 x8, 63.008 Gb/s** available bandwidth
- NUMA node 1, IOMMU group 8 (relevant if passing through to a VM)

**Firmware is healthy and running.** dmesg shows `mlx4_core` init OK, `mlx4_en` activating both ports, `mlx4_ib` attaching, interfaces created:

- **enp213s0** (port 1) — Link Up
- **enp213s0d1** (port 2)

### Conclusion: NO JTAG / SPI recovery needed. NO cross-flash needed.

There is no OEM PSID to unlock — the card is already stock Mellanox. The FTDI JTAG cable is not required for this card and should not be used on it.

## Firmware: 2.42.5000 — ALREADY THE FINAL VERSION ✅

```bash
ethtool -i enp213s0
# driver: mlx4_en   version: 4.0-0   firmware-version: 2.42.5000
```

**2.42.5000 is the last firmware ever released for ConnectX-3 Pro.** Nothing to update. `ethtool -i` is the correct tool here — mstflint was never needed.

If a reflash is ever attempted anyway:
- Match PSID exactly
- **Requires two cold boots** (full power-off, not warm reboot) to apply — the #1 cause of "bricked" CX3 cards

## Known bug for reference: Debian mstflint segfaults on ConnectX-3 Pro

`mstflint -d d5:00.0 query` → **Segmentation fault** with Debian's mstflint 4.31.0+1-4. Known upstream regression (≥4.30), NOT a card fault: <https://github.com/Mellanox/mstflint/issues/1157>

Workaround if mstflint is ever genuinely needed — install NVIDIA's MFT (needs Proxmox headers, not `linux-headers-generic`):

```bash
apt install -y make dkms proxmox-default-headers proxmox-headers-$(uname -r)
cd /tmp/mft-4.31.0-149-x86_64-deb && ./install.sh && mst start && mst status
flint -d /dev/mst/mt4103_pciconf0 query
```

Or `./install.sh --without-kernel` then `mstflint -d d5:00.0 query`.

## About the FTDI JTAG cable (user has one on hand)

Mellanox ASICs have **no public OpenOCD/JTAG target definition**. An FTDI FT2232H's only role on such a card would be as a raw **SPI flash programmer** (`flashrom`, clipped to the flash IC) — a last-resort path for a card that no longer responds to software at all. Not applicable here.

## Live network topology on pve3 (2026-07-30)

The Mellanox card is **in active production use** — proof it is fully healthy:

| Interface | Card | State |
|---|---|---|
| `nic0` → `vmbr0` | Intel 1GbE onboard | UP — Proxmox mgmt bridge |
| `nic1` | Intel I210 1GbE | DOWN (no cable) |
| `ens1f0` + `vlan10@ens1f0` | QLogic QL41000 | UP — VLAN 10 |
| `ens1f1` | QLogic QL41000 | UP |
| `ens1f2`, `ens1f3` | QLogic QL41000 | DOWN |
| **`enp213s0` + `vlan20@enp213s0`** | **Mellanox CX3 Pro 40GbE port 1** | **UP — VLAN 20** |
| `enp213s0d1` | Mellanox CX3 Pro port 2 | DOWN — **idle spare 40GbE port** |

MACs: Mellanox xx:xx:xx:xx:xx:xx/:xx · QLogic xx:xx:xx:xx:xx:xx-xx · Intel mgmt xx:xx:xx:xx:xx:xx

**Do not reflash this card** — it is carrying live VLAN 20 traffic.

## Which card is the "Azure" one?

The Mellanox reads as **genuine retail MCX314A-BCCT** (not an OEM/Azure PSID). The **QLogic FastLinQ QL41000** (quad-function, 40/50GbE capable) is the more likely Azure/Microsoft OEM pull. If reflashing the QLogic is ever wanted, that's a separate toolchain (`qed`/`qede` driver + Marvell utility), not mstflint.

## Next / ideas

- [ ] Optional: `ethtool -i enp213s0` to note the firmware version
- [ ] **Idle asset:** `enp213s0d1` is a free 40GbE port. A direct QSFP DAC cable from there to a 40G port on pve2 = dedicated high-speed storage link to the P840 array, no switch needed
- [ ] Clarify which physical card was the "Azure 40G NIC" purchase (Mellanox appears retail; QLogic is the OEM candidate)
- [ ] Note: `vlan20@enp213s0` is on the physical interface, not a bridge — if VMs need VLAN 20, a bridge would be required
