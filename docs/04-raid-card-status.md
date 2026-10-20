# P840 RAID Card — Verified Status (2026-07-24, host pve2)

## Everything confirmed working

| Check | Result |
|---|---|
| PCIe detection | `7b:00.0 Smart Array Gen9` — subsystem P840 |
| Driver | `hpsa` 3.4.20, bound and clean |
| Link | **PCIe 3.0 x8, 7880 MB/s** (full speed) |
| Firmware | 4.52, hardware rev B |
| Controller status | OK, RAID mode, RAID 6 licensed |
| Serial | <redacted> (cache: <redacted>) |
| Slot number | **255** — normal outside a ProLiant; use `slot=255` in all ssacli commands |
| Temps (idle, pre-GPU) | controller 36°C, cache 25°C |
| Ports | 1I and 2I, internal, 8 phys each — nothing attached yet (expected) |
| Cache board | Present, 4.0 GB (3.8 usable) |

## Known issue: no cache battery

`Battery Backed Cache Size: 0.0` — the P840 expects an **HP Smart Storage Battery** (ProLiant chassis part); absent in the Z8.

- Consequence: write-back cache disabled → write-through mode.
- **Decision: run as-is.** Drives are SAS SSDs; write-through + SSD Smart Path (enabled) is fine.
- Optional later, ONLY with a UPS: `ssacli ctrl slot=255 modify nobatterywritecache=enable` (power loss = up to 4GB lost writes; corruption risk).

## Proxmox software installed

- `lsscsi`, `sg3-utils` (drive visibility, `sg_format` for possible 520-byte SAN-pull drives)
- `ssacli` 6.15-11.0 from HPE MCP repo. Working repo line (component is `non-free`, NOT `non-os`; HTTPS required; key unsigned → trusted=yes):

```
deb https://downloads.linux.hpe.com/SDR/repo/mcp bookworm/current non-free
```

in `/etc/apt/sources.list.d/hpe-mcp.list`.

Repo is signed with HPE's **2024 key** (`hpePublicKey2048_key2.pub`, fingerprint ...74C3A4A2) — key1 alone gives a "Missing key" warning. Proper import:

```bash
curl -fsSL https://downloads.linux.hpe.com/SDR/hpePublicKey2048_key2.pub | gpg --dearmor -o /etc/apt/trusted.gpg.d/hpe2.gpg
```

(Component must be `non-free`, not `non-os`; HTTPS required — plain HTTP connection is refused.)

## HPE storage tools installed (all from the MCP repo)

| Package | Purpose |
|---|---|
| `ssacli` | Command-line array management |
| **`ssaducli`** | **Diagnostics** — full controller + drive report (power-on hours, wear, errors). Invaluable for used enterprise drives |
| **`ssa`** | **Web GUI** array manager — friendlier than ssacli for building arrays |

```bash
apt install -y ssacli ssaducli ssa
```

### 🎯 Run these the day the 8 Hitachi SSDs come online

```bash
# SSD WEAR REPORT — the important one for used enterprise SSDs.
# Shows write endurance consumed per drive.
ssa -ssd -txt -v -f /root/ssd-wear-$(date +%Y%m%d).txt

# Full diagnostic baseline BEFORE putting data on the array
ssaducli -v -adu -f /root/array-baseline-$(date +%Y%m%d).zip

# Controller serial + basecode logs
ssa -logs -f /root/ctrl-logs-$(date +%Y%m%d).zip
```

The wear report decides whether these drives were a bargain or someone else's worn-out cache tier. Take the baseline before writing any data so later comparisons mean something.

**Report contents** (`ADUReport.htm` is the readable one):
`ADUReport.htm` · `ADUReport.txt` · `ADUReport.xml` · `soulapiDump.txt` · `report.checksum`

⚠️ **No web GUI on headless hosts** — `ssa -local` is an X11 application only. `ssacli` remains the practical interface for building arrays over SSH.

## Command cheat-sheet

```bash
# rescan after connecting drives (no reboot needed)
echo 1 > /sys/class/scsi_host/host2/rescan && sleep 5 && lsscsi -g

# controller status / full detail
ssacli ctrl all show status
ssacli ctrl slot=255 show detail

# physical drives (once backplane is powered)
ssacli ctrl slot=255 pd all show

# full config
ssacli ctrl slot=255 show config

# fix a 520-byte-sector drive (if drives are EMC/NetApp pulls)
sg_format --format --size=512 /dev/sgX
```

## Not yet done

- Array creation (waiting for drives to appear). Example for later, RAID 6 across all 8:
  `ssacli ctrl slot=255 create type=ld drives=allunassigned raid=6`
  (Decide RAID level first — RAID 6 ≈ 4.8TB usable, RAID 10 ≈ 3.2TB faster writes, RAID 5 ≈ 5.6TB less safe.)
