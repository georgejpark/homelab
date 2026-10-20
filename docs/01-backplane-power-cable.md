# Backplane Power Cable (THE BLOCKER)

The DL380p G8 cage gets power from the server's power distribution board — **not** from any motherboard connector. The Z8 G4 has no port for it. A custom cable must be made. No off-the-shelf cable exists for this.

## Power path

```
Z8 PSU ─► motherboard ─► Z8 power distribution cable
                              │
                    2× 4-pin Molex drops        ← the 12V + 5V source
                              │
                    custom spliced cable        ← YOU BUILD THIS
                              │
                    backplane 10-pin power input
```

⚠️ Do **not** use the 6-pin GPU outputs (G1–G4) for the backplane — they are 12V-only, no 5V. Those are reserved for the P100s anyway.

## Shopping list (~$25–30 total)

| Item | Where | Price |
|---|---|---|
| HP 10-pin backplane power cable (ML350p G8 type) | Amazon: <https://www.amazon.com/10Pin-Backplane-Supply-Proliant-ML350P/dp/B08RYMWSBC> or eBay search `HP ML350p G8 backplane power cable 10 pin` | ~$10–13 |
| 2× female 4-pin Molex pigtails | Amazon/eBay search `4 pin Molex female extension cable` (cut off male end) | ~$7 |
| Joining: solder + heat-shrink, OR Wago 221 lever connectors (no tools) | hardware store / Amazon | ~$10 |

Alternative, zero-DIY: shelf the HP cage and buy generic hot-swap cages (ICY DOCK style, 2× "4×2.5-in-1" units, ~$60–120) that take Molex/SATA power directly.

## Expected pinout — VERIFY BEFORE USE

Documented HP ProLiant SAS backplane 10-pin (Mini-Fit Jr.) pinout — from Gen6 docs; HP changed pinouts between generations, so **must be confirmed by multimeter on this exact board**:

| Pin | Signal | | Pin | Signal |
|---|---|---|---|---|
| 1 | +12V | | 6 | +5V |
| 2 | GND | | 7 | GND |
| 3 | i²c — leave empty | | 8 | i²c — leave empty |
| 4 | GND | | 9 | GND |
| 5 | +12V | | 10 | +5V |

### Verification procedure (multimeter, continuity mode, nothing powered)

Probe from a drive slot's SAS power pins back to the 10-pin input connector:

- SAS slot pins **P13–P15** (+12V) → whichever input pins beep = the 12V pins
- SAS slot pins **P7–P9** (+5V) → the 5V pins
- SAS slot pins **P4–P6 / P10–P12** (GND) → the ground pins
- The two silent pins = i²c → leave unconnected

**Join by pin position, not wire color** — HP cable colors don't follow ATX conventions. Label wires after mapping.

## Wiring (after verification)

| Molex wire | → Backplane pin |
|---|---|
| Yellow (12V) | pins 1 and 5 (one per Molex drop) |
| Red (5V) | pins 6 and 10 (one per Molex drop) |
| Black (GND) | pins 2, 4, 7, 9 |

Use **both** Molex drops to split the load. 8 SAS SSDs ≈ 20–30W total — comfortable.

## First power-on procedure

1. Cage **empty** (no drives). Power on.
2. Meter a drive slot: 12V and 5V present, nothing hot, no smell.
3. Power off, insert ONE drive, power on.
4. On pve2: `echo 1 > /sys/class/scsi_host/host2/rescan && sleep 5 && lsscsi -g`
5. Drive appears → insert remaining 7, rescan again → expect 8 HGST rows.

## Known limitations outside a ProLiant (harmless)

- Drive bay LEDs and i²c management don't work — drives function normally.
