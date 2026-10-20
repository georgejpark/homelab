# Microsoft Azure FPGA SmartNIC — Catapult v2 "Storey Peak" (X930613-001)

User has **two** of these. Identified 2026-07-30. These are the actual "Azure 40G NIC" cards — distinct from the Mellanox CX3 Pro in pve3 (retail, see [06-pve3-network-cards.md](06-pve3-network-cards.md)).

## Hardware

| | |
|---|---|
| Product | Microsoft **Catapult v2 "Storey Peak"** FPGA accelerator/SmartNIC |
| Part numbers | X930613-001 (HP variant 861309-001), board P/N **DAT6MTHUEB0 Rev B** |
| FPGA | **Intel/Altera Stratix V GS** (DSP-optimized), p/n **5SGSKF40I3LNAC** |
| JTAG IDCODE | **0x029070dd** (5SGSMD5H/K family) |
| Memory | **9× SK hynix H5TC4G83BFR** 8-bit 4Gb DDR3L → 72-bit bus (64-bit + ECC) = **4GB usable ECC** |
| Ports | 2× QSFP+ **40GbE** |
| PCIe | Gen3 x16, **logically 2× bifurcated x8** (both x8 links go to the single x16 edge connector) |
| Config flash | **Micron N25Q256..3E / MT25QL256**, 32MB (32768 kB), **SOIC-16** |
| Debug | **Onboard FT232H → USB Type-B port on the bracket** |

Sister board: "Pikes Peak" — same silicon, OCS tray mezzanine (SAMTEC) connector instead of PCIe card edge.

## KEY FINDING: JTAG is built into the card

The **USB Type-B connector on the bracket** feeds an onboard FTDI **FT232H** bridging USB → JTAG. **No external dongle, no clips, no soldering** — a plain USB A-to-B cable to the host *is* the JTAG link.

Confirmed on pve3: `lsusb` shows `0403:6014 FT232H`. That device **is the card**. (Verify: unplug the cable, re-run `lsusb | grep 0403`, it should disappear.)

## Why the card does NOT appear in lspci

Both expected, neither is a fault:

1. **PCIe x8x8 bifurcation required** — the card presents as **two** PCIe devices. A slot without bifurcation enabled in BIOS may not enumerate it. Check pve3 BIOS.
2. **FPGA may have no valid bitstream** — an unconfigured FPGA doesn't enumerate on PCIe at all. Normal.

Absent-from-lspci ≠ bricked. **JTAG IDCODE readback is the real health test.**

## EXPECTATION SETTING

**This will never be a plug-and-play 40GbE NIC.** The factory bitstream is Microsoft-proprietary and needs Microsoft's own driver stack.

What it *is*: a **Stratix V FPGA development board with 2× 40G ports and 4GB ECC DDR3L** for ~$80. Excellent hobbyist platform, deep project.

- Need working 40GbE on pve3 → **use the Mellanox CX3 Pro** (already running)
- Want serious FPGA development → this card

## Setup — verified procedure

### 1. Dependencies (done on pve3)

```bash
apt install -y libtool pkg-config texinfo libusb-1.0-0-dev libftdi-dev autoconf libjim-dev git wget build-essential cmake openocd
```

### 2. udev rule (use ATTRS, plural — per upstream README)

```bash
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6014", OWNER="root", GROUP="plugdev", TAG+="uaccess"' > /etc/udev/rules.d/100-usb-ftdi.rules && udevadm control --reload-rules && udevadm trigger
```

### 3. Build the Quartus JTAG driver

`copy_openocd_files.sh` is a **maintainer tool only** — the `openocd/` dir is already vendored in the repo. Do NOT clone OpenOCD source; just build:

```bash
cd ~/storey-peak/jtag-quartus-ft232h && mkdir -p build && cd build && cmake .. && make -j$(nproc)
```

Produces **`libjtag_hw_otma.so`** → copy into Quartus's `linux64` dir (e.g. `$HOME/altera/15.0/quartus/linux64`).

### 4. ⚠️ MPSSE init — required before EVERY Quartus session / after every power cycle

The driver doesn't implement MPSSE init, so OpenOCD must do it once. This command **also reads the FPGA's IDCODE**, making it the definitive health test:

```bash
openocd -f interface/ftdi/um232h.cfg -c "adapter speed 2000; transport select jtag; jtag newtap auto0 tap -irlen 10 -expected-id 0x029070dd; init; exit;"
```

- Prints **`0x029070dd`** → FPGA alive and talking. Card confirmed healthy regardless of lspci.
- Different idcode → JTAG works, something else odd
- All 0s/1s → no JTAG response (unpowered, or cable on the other card)
- libusb/permission error → udev rule didn't take; re-plug USB

### 5. Quartus Prime **STANDARD** edition

- ⚠️ Quartus **Lite and Pro do NOT support Stratix V** — Standard specifically
- ~20GB download, free Intel/Altera account required
- Known snag: Quartus GUI rejects this custom Microsoft part → needs a `ddb_dev` library override / DLL shim to allow two PCIe hard IP cores (documented on the blog). **LiteX** is an alternative that bypasses Quartus GUI limits.
- Submodules `sv_second_pcie_hip` (+ `_windows`) exist specifically to enable the 2nd PCIe hard IP

### Bitstream download times (26MB / 213,798,880 bits)

| Clock | Time |
|---|---|
| 2 MHz (default) | 3:51 |
| 4 MHz | 2:50 |
| 10 MHz | 2:03 |
| **20 MHz** | **1:54** |

Bump `adapter speed` once things work.

## Factory firmware — the card is effectively UN-BRICKABLE

The repo ships extracted factory firmware in `~/storey-peak/firmware/`:

- **`factory_fw.jic`** — via Quartus Programmer (contains a header beyond raw ROM bytes)
- **`N25Q256A83E40.bin`** — raw ROM dump via flashrom

Two independent recovery paths:

| Method | Requires | Notes |
|---|---|---|
| **Quartus Programmer over JTAG** | just the USB cable | Quartus loads a flashloader IP; ROM shows as QSPI; can Examine → save as .jic |
| **Direct flashrom** | SOIC-16 clip + SOIC-16→SOIC-8 adapter + CH341a | `flashrom --programmer ch341a_spi -c N25Q256..3E -r dump.bin` |

⚠️ **Caveat from the author:** his `.jic` differs non-trivially from @wirebond's extraction and the cause isn't understood. **Take your own ROM dump before writing anything.**

## Submodules in ~/storey-peak

| Submodule | Purpose |
|---|---|
| `pp-sp-reference-design` | **main starting project** + board-support .qsf file |
| `jtag-quartus-ft232h` | Linux JTAG driver (built above) |
| `jtag-quartus-ft323h-windows` | Windows equivalent |
| `sv_second_pcie_hip` / `_windows` | enable 2nd PCIe hard IP in Quartus |
| `otma-pin-re` | pin configuration reverse-engineering from factory FW |
| `catapult_v2_pikes_peak` | @wirebond's sister-board docs + factory FW |
| `firmware/` | maintainer's own factory FW extraction |

## Resources

- **<https://github.com/ruurdk/storey-peak>** — main repo (cloned to `~/storey-peak` on pve3)
- **<https://www.devops.lol/azure-fpga/>** — companion getting-started blog, most detailed
- **<https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay.html>** — Jan Marjanovic's blog series (the origin of this whole effort; also wrote the JTAG driver)
- **<https://github.com/j-marjanovic/jtag-quartus-ft232h>** — upstream JTAG driver
- **<https://github.com/wirebond/catapult_v2_pikes_peak>** — sister board
- **<https://github.com/corundum/corundum/issues/213>** — porting Corundum (open-source high-perf NIC) to Catapult v2
- **<http://virtlab.occamlab.com/home/zapisnik/microsoft-catapult-v2>** — @occamlab overview
- Microsoft's FPGA journey (Catapult) PDF: <https://indico.fnal.gov/event/22303/contributions/246438/attachments/157852/206736/Catapult_Putnam_Snowmass_2022_FPGA_Cloud__for_HPC.pdf>

## ✅ MILESTONE ACHIEVED 2026-07-30 — JTAG working, FPGA confirmed alive

```
root@pve3:~/storey-peak/jtag-quartus-ft232h/build# openocd -f interface/ftdi/um232h.cfg \
  -c "adapter speed 2000; transport select jtag; jtag newtap auto0 tap -irlen 10 -expected-id 0x029070dd; init; exit;"
Open On-Chip Debugger 0.12.0
Info : clock speed 2000 kHz
Info : JTAG tap: auto0.tap tap/device found: 0x029070dd (mfg: 0x06e (Altera), part: 0x2907, ver: 0x0)
```

**Exact expected IDCODE.** The Stratix V is alive, powered, and responding over JTAG. Full access with just a USB cable — no SPI clips, no CH341a, no soldering ever needed.

Driver built successfully → **`/root/storey-peak/jtag-quartus-ft232h/build/libjtag_hw_otma.so`**
(Build warnings about `struct command_context` / `ERROR_JTAG_INIT_FAILED` are cosmetic — vendored OpenOCD headers vs newer GCC. It links fine.)

**Conclusion:** the card's absence from `lspci` is NOT a hardware fault. It's the missing x8x8 bifurcation and/or no valid bitstream.

## Status / open items

- [x] Card identified as Catapult v2 Storey Peak
- [x] Repo cloned to `~/storey-peak` on pve3, deps installed, udev rule set
- [x] JTAG driver built → `libjtag_hw_otma.so`
- [x] **OpenOCD confirms IDCODE 0x029070dd — FPGA ALIVE** ✅
- [x] **20MHz clock verified working** — same IDCODE, clean. Use `adapter speed 20000` (1:54 loads vs 3:51). Fallback if ever flaky: add `ftdi tdo_sample_edge falling`
- [ ] Install **Quartus Prime Standard** (~20GB, Intel account) ← the next real step
- [ ] Copy `libjtag_hw_otma.so` into Quartus `linux64/`
- [ ] Take own ROM dump BEFORE any write
- [ ] Check pve3 BIOS for PCIe **x8x8 bifurcation** on that slot
- [ ] Try programming `pp-sp-reference-design`
- [ ] Unplug-test to confirm `0403:6014` is the card (cosmetic now — JTAG proves it)
- [ ] Read devops.lol/azure-fpga + Marjanovic series end-to-end
- [ ] Note physical location of both cards

**Remember every session:** run the OpenOCD init command before using Quartus (MPSSE init isn't in the driver), and after every power cycle.
