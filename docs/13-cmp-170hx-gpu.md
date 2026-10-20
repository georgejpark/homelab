# NVIDIA CMP 170HX on pve3 — Driver + Unlock Research

Investigated 2026-08-05. GPU installed in **pve3** (the Dell, `10.10.0.89`).

## ✅ Driver install — DONE and working

| | |
|---|---|
| Card | NVIDIA **CMP 170HX** (GA100), PCI `02:00.0`, ID **`10de:20c2`** |
| VBIOS | `92.00.67.00.01` |
| Driver | **nvidia-open 610.57.04**, CUDA UMD 13.3 |
| Kernel | `7.0.14-8-pve` — DKMS built cleanly ✅ |
| Status | `Kernel driver in use: nvidia`, nouveau blacklisted, `nvidia_uvm` loaded |
| Memory (stock) | 8192 MiB · BAR1 only 64 MiB |

### Reproducible install (worked first time)

```bash
# 1. blacklist nouveau (it grabs the card and fails: "unknown chipset 170000a1")
cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
apt install -y proxmox-default-headers proxmox-headers-$(uname -r) build-essential
update-initramfs -u -k all

# 2. NVIDIA's own repo — Debian's nvidia-driver has NO candidate on Proxmox
#    (Debian ships 550/CUDA12.4; NVIDIA's debian13 repo has 590/595/610)
cd /root && wget https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb && apt update

# 3. open kernel modules — GA100 is Ampere datacenter, fully supported
apt install -y nvidia-open      # → 610.57.04
reboot
```

⚠️ Run long installs inside `tmux` — an SSH disconnect mid-`apt` leaves a dpkg lock held.

## ✅ RESOLVED: thermals fixed by changing PCIe slot

**The fix was moving the card to a different slot.** The original slot had essentially zero airflow.

| Config | GPU | Memory | Draw |
|---|---|---|---|
| Original slot, 100W cap | **98°C** 🔴 | 95°C | 91.5W |
| **New slot** (`17:00.0`), 100W | **68°C** ✅ | 75°C | 52.7W |
| New slot + small fan, 250W cap | 72°C | 78°C | 56.4W |
| New slot + fan, 150W cap (current) | 76°C | — | — |

⚠️ **All readings above are IDLE.** The card draws ~56W doing nothing regardless of the power limit; under real compute it pulls toward 150W and will run considerably hotter. **Cooling is not validated until a load test is run.**

⚠️ Idle temp drifted 68 → 72 → 76°C across readings — possible heat accumulation in the chassis (3 of 4 chassis fans read 0 RPM). Monitor; if idle settles above 85°C the cooling is marginal.

**PCI address changed to `17:00.0`** after the slot move (was `02:00.0`).

**PCIe link is now readable** (was blank in the old slot):
```
PCIe Generation:  Max 2   Current 1     ← Gen2 available via unlock patch
Link Width:       Max 16x  Current 4x
```

### Load-test procedure (still to do)

Run a real workload, and watch in a second terminal:

```bash
watch -n 2 nvidia-smi --query-gpu=temperature.gpu,temperature.memory,power.draw,clocks.sm,clocks_throttle_reasons.active --format=csv
```

Watch `clocks_throttle_reasons.active` for `SwThermalSlowdown` / `HwSlowdown` — definitive proof of overheating, far better than idle readings.

## Historical: the original overheating problem (for reference)

**The CMP 170HX is passive by design.** Bare heatsink, no fan, no fan header. `nvidia-smi` shows `Fan: N/A` because none exists — not a fault.

Measured on 2026-08-05, **idle, zero processes**:

```
86°C → 93°C → 98°C     (climbing)
Memory temp: 95°C
GPU Shutdown Temp:  98°C   ← reached
GPU Slowdown Temp:  95°C   ← passed
Memory Max Operating: 95°C ← reached
```

Even capped at the **100W minimum** (`nvidia-smi -pl 100`) it still hit 98°C. Host was powered off.

**Chassis airflow is the cause** — pve3's fans:
```
fan1: 0 RPM   fan2: 989 RPM (of 4000 max)   fan3: 0 RPM   fan4: 0 RPM
```
Three of four chassis fans not spinning. A passive card has no chance.

### Required fix
- **Blower shroud** (~$25–35) — search `CMP 170HX cooling shroud` / generic 3D-printed GPU duct
- Or crude: 80–120mm fan zip-tied blowing across the heatsink (~$10, drops 20–30°C)
- Realistic target: **50–70°C under load**. Below 80°C sustained = safe to lift power limit

### Power limit persistence (settings reset without this)

```bash
cat > /etc/systemd/system/nvidia-powerlimit.service <<'EOF'
[Unit]
Description=NVIDIA persistence mode and power limit
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 150
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now nvidia-powerlimit
```
⚠️ **Persistence mode (`-pm 1`) must be enabled first** or the power limit reverts to 250W when the driver unloads.

## The 8GB → 64GB unlock — REAL, and this card/driver are supported

**Earlier assessment that this required a risky VBIOS flash was WRONG.** It's a **kernel driver patch** — no firmware is ever written to the card.

- Tool: **<https://github.com/amoghmunikote/cmpunlocker>**
- Guide: **<https://github.com/abobasixseven/unlock-cmp-170hx>**
- Wiki (55 pages): **<https://github.com/Consensus-Protocol/cmp170hx>**
- Community: **<https://github.com/amoghmunikote/170th-Street>** · [gitbook](https://170th-street.gitbook.io/hx)

### How it works

9 patches (1,340 lines) against NVIDIA's **open** GPU kernel modules. Registers are written **before GSP-RM firmware boots**, while Privilege Level Masks are still open; GSP then boots with the new memory geometry already set. This is why a **cold power cycle (60s off)** is mandatory — WPR2 reset + capacitor discharge.

| Patch | Lines | Purpose |
|---|---|---|
| `sec2-postbl-plm-ss-cfg.patch` | 470 | **Core** — opens PLM-protected registers, sets compute throttle SS0/SS1 |
| `pcie-gen2.patch` | 310 | Gen1 → Gen2 |
| `late-pma.patch` | 263 | Memory geometry |
| `booter-verify.patch` | 87 | Booter verification bypass |
| + 5 more | 210 | Scrub workarounds, BAR0 clamp, persistence |

### This card is explicitly supported ✅

```yaml
device_ids: ["20c2", "2082"]     # ours = 20c2 ✅
profiles."8gb":
  stock_mib:    8192
  unlocked_mib: 65536            # 64GB
  cfg1: "0x02779000"  lmr: "0x0000020B"  fb_bytes: "0x0000001000000000"
driver/VERSION: 610.57.04        # EXACTLY our installed driver ✅
compute: ss0 "0x88888888", ss1 "0x00000008"
```
(10GB variant `2082` → 40GB.)

### Claimed working vs. unsolved

**Working:** full SM compute (SS0/SS1) · memory geometry 64GB · PCIe Gen2 · JTAG · persistence across reboots

**Unsolved frontier problems:** **ECC** · PCIe Gen3/Gen4 · NVLink · 80GB · P2P
→ Gen3/Gen4 is blocked by an **OTP silicon fuse** (`FUSE_PCIE_GEN23_DIS`) — permanently unfixable in software.

### Risk assessment

| Risk | Verdict |
|---|---|
| Bricking via firmware flash | ❌ **Not applicable** — no firmware written |
| Reversibility | ✅ `sudo ./uninstall.sh --yes` + cold reboot |
| **No ECC** | ⚠️ **Real** — silent corruption possible across 64GB |
| Long-term stability | ⚠️ No large-sample, long-duration testing across batches |
| Secure Boot | ⚠️ Must be **disabled** (unsigned modules) |
| **Heat** | 🔴 64GB active HBM runs **hotter** than 8GB |

## 🔴 STATUS 2026-08-05: unlock INSTALLED but NOT APPLIED — host powered off for cooling

**`cmpunlocker install.sh --profile=8gb` completed successfully.** Verified staged:

```
==> Installed profile: 8gb / geometry: 64GB
✗ 0000:17:00.0: still stock 8192 MiB (expect ~65536)
✗ Cold reboot if modules were just installed.
```

The patches are correctly installed. **It only needs a COLD reboot** (full power off 60s → power on) to take effect. Nothing is wrong with the install.

**Host was powered off before that cold boot because of thermals** — see below.

### What install.sh also did (beyond the patches)

- Enabled **`gen2.service`** (early-boot PCIe Gen2 retrain) — recovery boot option if it hangs: `systemd.mask=gen2.service`
- **Modified GRUB**: `GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"` (backup at `/etc/default/grub.cmpunlocker.bak`)
  - ℹ️ pve3 **does** boot via GRUB (unlike pve2 — its initramfs reports *"No /etc/kernel/proxmox-boot-uuids found"*), so this takes effect
- ⚠️ **Removed the nvidia DKMS modules** → **`install.sh` must be re-run after EVERY kernel upgrade**
  - ⚠️ pve3 has **25 pending package upgrades** — do NOT `apt upgrade` without re-running install.sh afterward
- Persistence mode was reset by the module swap; the `nvidia-powerlimit.service` re-applies it at boot

### 🔴 BLOCKER: thermals never stabilized

Idle temperature climbed all evening and never reached equilibrium — at the **100W minimum** power limit, with **zero workload**:

```
68°C → 72°C → 76°C → 90°C → 94°C
                              ^^^^ 1°C from slowdown (95°C), 4°C from shutdown (98°C)
```

Root cause is chassis airflow — **3 of 4 pve3 chassis fans read 0 RPM**:
```
fan1: 0 RPM   fan2: 978 RPM   fan3: 0 RPM   fan4: 0 RPM
```
The small add-on fan can't compensate for a case with no through-flow.

**Do not power this host back on until cooling is fixed.** Coming up with 64GB of active HBM (more power, more heat) on a card that idles at 94°C with 8GB would be worse.

### Before powering on again

- [ ] Open the case: are fans 1/3/4 unplugged, failed, or just idle in Dell's BIOS fan profile?
- [ ] Get a high-static-pressure fan blowing **directly into the GPU heatsink fins** — not merely near the card. Blower shroud (~$30) is the proper part
- [ ] **Target: idle stable below 60°C**
- [ ] Then power on → unlock applies automatically on that cold boot → verify 65536 MiB

Also captured before shutdown: PCIe reported `gen.current=1, gen.max=2` (Gen2 available post-unlock).

### Procedure reference (ONLY after cooling is fixed)

```bash
git clone https://github.com/amoghmunikote/cmpunlocker.git && cd cmpunlocker
sudo ./install.sh --profile=8gb
# COLD reboot — full power off 60s, not `reboot`
nvidia-smi        # expect 65536 MiB
```
Rollback: `sudo ./uninstall.sh --yes` + cold reboot.

## Card characteristics (why it's worth bothering)

| Metric | Value | Note |
|---|---|---|
| FP32 with FMA | **0.39 TFLOPS** | ⛔ hardware-throttled, unusable for training |
| FP32 no-FMA | ~6.25 TFLOPS | needs `#pragma OPENCL FP_CONTRACT OFF` |
| **FP16** | **42 TFLOPS** | ✅ genuinely good |
| **Memory bandwidth** | **~1350–1493 GB/s** | ✅ A100-class |
| PCIe | Gen1 x4 (~0.85 GB/s) → Gen2 after unlock (~2 GB/s) | ⛔ slow model loading either way |
| CUDA cores | 4480 (54% of GA100) | |

**Best use: FP16 LLM inference on models that fit in VRAM.** Memory bandwidth is the inference bottleneck and this card has A100-tier bandwidth. Load slowly over Gen2, then it runs well. Not a training card.

Reference: [detailed teardown/review](https://niconiconi.neocities.org/tech-notes/nvidia-cmp-170hx-review/)

## Order of operations

1. 🔴 **Fan on the heatsink** — nothing else is possible first
2. Verify sustained temps < 80°C under load
3. Then apply the unlock, cold reboot, confirm 65536 MiB
4. **Stress-test memory hard** before trusting it — no ECC means corruption is silent
5. Benchmark FP16 inference vs. the 8GB baseline

## Open items

- [ ] 🔴 Cooling — blower shroud or zip-tied fan (host is powered off until then)
- [ ] Investigate why 3 of 4 pve3 chassis fans read 0 RPM
- [ ] Apply cmpunlocker once thermals are safe
- [ ] Memory stress test post-unlock (no ECC!)
- [ ] Benchmark: llama.cpp / PyTorch FP16
- [ ] 25 pending package upgrades on pve3 (do after GPU work settles — a kernel upgrade breaks the DKMS module)
