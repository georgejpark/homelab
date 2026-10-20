# Consolidated Parts List

Everything blocking the AI-Server build as of 2026-07-30. **All software on both hosts is complete and verified** — only these physical parts remain.

## 🥇 Priority 1 — Storage (unblocks 8× 800GB SAS SSDs)

| Part | Search / link | Qty | ~Cost |
|---|---|---|---|
| HP 10-pin backplane power cable (ML350p G8 type) | [Amazon B08RYMWSBC](https://www.amazon.com/10Pin-Backplane-Supply-Proliant-ML350P/dp/B08RYMWSBC) · eBay `HP ML350p G8 backplane power cable 10 pin` | 1 | $10–13 |
| 4-pin Molex female pigtails | search `4 pin Molex female extension cable` | 2 | $7 |
| Wago 221 lever connectors (or solder + heat-shrink) | hardware store | 1 pack | $10 |
| **SFF-8643 → SFF-8087 cable** | search `SFF-8643 to SFF-8087 cable` | **2** | $24 |

**Subtotal ≈ $55.** This is the single biggest unblock — a verified P840 and eight SSDs are idle waiting on it. Procedure in [01-backplane-power-cable.md](01-backplane-power-cable.md).

⚠️ **Multimeter-verify the 10-pin pinout before wiring.** Documented pinout is Gen6-era.

## 🥈 Priority 2 — 40GbE link between hosts (high value, tiny cost)

| Part | Search | Qty | ~Cost |
|---|---|---|---|
| QSFP+ 40G DAC cable (1–3m) | search `QSFP+ DAC cable 40G 1m` | 1 | $20 |

**Both pve2 and pve3 already have Mellanox ConnectX-3 Pro cards with a free 40G port.** One cable = direct 40Gb storage link, no switch. Best value-per-dollar in this whole list.

```
pve2 (P840 + SAS array)  ←── QSFP+ DAC ──→  pve3 (GPU compute)
```

## 🥉 Priority 3 — GPU install (3× Tesla P100)

| Part | Search | Qty | ~Cost |
|---|---|---|---|
| **P100 blower fan shroud** ⚠️ mandatory | eBay `Tesla P100 cooling fan shroud` | 3 | $75–105 |
| PCIe 8-pin → **EPS 8-pin** Tesla adapter | search `PCIe 8-pin to EPS adapter NVIDIA Tesla` | 3 | $24 |
| HP 6-pin → PCIe 8-pin GPU cable (if not already present) | HP Z8 GPU power cable | 3 | varies |

⚠️ **The shrouds are not optional.** P100s are passive and thermal-shutdown in under a minute of load without forced air.
⚠️ P100 uses **EPS 8-pin, not PCIe 8-pin** — different keying, never force it.
⚠️ **240V outlet** needed to run all three at full power (PSU: 1125W@120V / 1450W@240V). On 120V, cap with `nvidia-smi -pl 170`.

Details in [03-gpu-installation.md](03-gpu-installation.md) · passthrough already configured, see [10-gpu-passthrough-setup.md](10-gpu-passthrough-setup.md).

## Optional / later

| Part | Why | ~Cost |
|---|---|---|
| HP Smart Storage Battery + cable | Enables P840 write-back cache. **Low value** — drives are SSDs, write-through + SSD Smart Path is fine | $25 |
| More DDR4 RDIMMs | Only 2 of 24 slots populated (64GB). Sparse population also limits memory bandwidth | varies |
| UPS | Would make `nobatterywritecache=enable` safe, protects against mid-write power loss | varies |

## Total to unblock everything

```
Storage cable kit + SAS cables   ~$55
QSFP+ DAC (40GbE link)           ~$20
GPU shrouds + power adapters     ~$100-130
                                 --------
                                 ~$175-205
```

**Order priority 1 + 2 first (~$75)** — that brings storage and the fast network online, which is the foundation everything else sits on.
