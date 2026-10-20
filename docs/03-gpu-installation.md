# GPU Installation — 3× Tesla P100 16GB (699-2H400-0201)

## HP Z8 G4 layout (dual CPU required!)

Slot map with both CPUs installed:

| Slot | Electrical | CPU | Assignment |
|---|---|---|---|
| 1 | x8 | CPU0 | **P840 RAID card** |
| 2 | **x16** | CPU0 | **P100 #1** |
| 3 | x16 | CPU1 | ⛔ covered by P100 #1 |
| 4 | **x16** | CPU0 | **P100 #2** |
| 5 | x4 | CPU0 | ⛔ covered by P100 #2 |
| 6 | **x16** | CPU1 | **P100 #3** |
| 7 | x4 | CPU0 | ⛔ covered by P100 #3 |
| 8 | x8 | CPU0 | free (alt. P840 spot) |
| 9 | x8 | CPU1 | free |

This is HP's own triple-GPU arrangement (slots 2/4/6). **Slot 6 is dead without the second CPU** — 3rd GPU requires dual CPUs per HP spec.

## Power budget — depends on wall outlet

- **120V outlet:** PSU delivers 1125W → HP-rated for only **2×** 250W GPUs. For 3, power-cap: `nvidia-smi -pl 170` (~510W total).
- **200–240V outlet:** same PSU delivers **1450W** → 3× 250W GPUs within spec.

## Power cables (per card)

P100 uses an **8-pin CPU/EPS connector — NOT PCIe 8-pin** (different keying, do not force).

```
G1/G2/G3 (6-pin, 216W each) ─► HP 6-pin→PCIe-8-pin cable ─► "PCIe 8-pin to EPS 8-pin Tesla adapter" (~$8) ─► P100
```

Search term: `PCIe 8-pin to EPS adapter NVIDIA Tesla`. Verify adapter orientation before plugging — reversed = 12V on ground pins.

## Cooling — MANDATORY

P100s are **passive** (no fans). In a tower they thermal-shutdown in under a minute of load without forced air. Buy one **blower shroud per card**: eBay `Tesla P100 cooling fan shroud` (~$25–35 each). Also point a fan at the P840 heatsink.

## Other notes

- No display outputs on P100s — run headless (SSH/Proxmox web) or add a cheap display GPU in a free x8 slot.
- Linux: standard NVIDIA datacenter driver + CUDA sees all three. For Proxmox: consider PCIe passthrough of each P100 to VMs (IOMMU/VT-d in BIOS).

---

# Dell Precision 7820 — second machine

Hard limits: only **2 full x16 slots**; PSU is 950W (chassis keyed, no upgrade); Dell GPU budget max **2× 300W double-width**; 2× PCIe 8-pin (6+2) GPU cables from PSU.

| Position | Card |
|---|---|
| Full x16 slot #1 | P100 #1 |
| Full x16 slot #2 | P100 #2 |
| x8-wired slot | free — P840/HBA or display GPU |

- **Two P100s max.** No third: no bandwidth slot, no power.
- Power: Dell's 8-pin PCIe cable + same PCIe→EPS Tesla adapter, one per card.
- Same blower-shroud cooling requirement.

## Fleet totals

- Z8 on 240V: 3 (Z8) + 2 (7820) = 5 GPUs full power
- Z8 on 120V: 2 + 2 full power, or 3 power-capped + 2
