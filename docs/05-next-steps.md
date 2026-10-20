# Next Steps — in order

Last updated 2026-07-30. **All software/config work on both hosts is COMPLETE.** Everything below is physical, except a couple of small optional items.

## 🥇 Storage — the one real blocker

- [ ] **Order parts** (see [11-shopping-list.md](11-shopping-list.md)): 10-pin HP backplane cable (~$10), 2× Molex female pigtails (~$7), Wagos or solder kit (~$10)
- [ ] Order **2× SFF-8643→SFF-8087 cables** (~$24)
- [ ] **Multimeter-map the backplane 10-pin pinout** (procedure in [01](01-backplane-power-cable.md)) — do NOT trust the documented pinout blindly
- [ ] Build the power cable, connect both Molex drops
- [ ] First power-on **empty**; meter 12V/5V at a drive slot
- [ ] Connect SAS cables: P840 port **1I** → bays 1-4, port **2I** → bays 5-8
- [ ] One drive in → `echo 1 > /sys/class/scsi_host/host2/rescan` → check `lsscsi -g`
- [ ] Read the drive model off the label — if EMC/NetApp pulls, `sg_format --format --size=512` (520-byte sectors)
- [ ] All 8 drives in → rescan → expect 8 rows
- [ ] **Run the SSD wear report** — `ssa -ssd -txt -v -f /root/ssd-wear-$(date +%Y%m%d).txt` — tells you what you actually bought
- [ ] Take a pre-data baseline: `ssaducli -v -adu -f /root/array-baseline-$(date +%Y%m%d).zip`
- [ ] Choose RAID level (6 ≈ 4.8TB / 10 ≈ 3.2TB faster writes / 5 ≈ 5.6TB less safe) and create with `ssacli`
- [ ] Add to Proxmox as **LVM-thin** — ⚠️ **do NOT put ZFS on top of the hardware RAID logical drive** (pve2's root is already ZFS; ZFS wants raw disks)

## 🥈 40GbE link between hosts — best value item

- [ ] Order **1× QSFP+ DAC cable** (~$20)
- [ ] Connect pve2 `enp165s0d1` ↔ pve3 `enp213s0d1` (both free 40G ports)
- [ ] Configure a point-to-point subnet — no switch needed
- [ ] Consider MTU 9000 on both ends for storage traffic

## 🥉 GPUs — after storage works

- [x] ~~Confirm second CPU installed~~ ✅ **Both Xeon Platinum 8269CY confirmed** (52c/104t)
- [x] ~~Proxmox PCIe passthrough setup~~ ✅ **Done — 308 IOMMU groups live** (see [10](10-gpu-passthrough-setup.md))
- [ ] **Determine wall outlet voltage** (120V → power-cap with `nvidia-smi -pl 170`; 240V → full power for all 3)
- [ ] Order 3× **PCIe-8-pin→EPS Tesla adapters** (⚠️ P100 uses EPS, not PCIe 8-pin)
- [ ] Order 3× **P100 blower shrouds** (⚠️ mandatory — cards are passive)
- [ ] Install per slot map in [03](03-gpu-installation.md): P100s in slots 2/4/6, P840 in slot 1
- [ ] Bind to vfio: `options vfio-pci ids=10de:xxxx` → `update-initramfs -u -k all` → reboot
- [ ] Assign to VMs in the Proxmox GUI; install NVIDIA driver **inside the VM**
- [ ] Dell 7820: 2× P100 max (950W PSU, only 2 full x16 slots)

## Optional / small

- [ ] BIOS via `hp-repsetup`: raise `Increase PCIe Idle Fan Speed(%)` (currently 0) + enable `PCIe Idle Fan Tracking mode` before GPUs
- [ ] BIOS: consider `After Power Loss` → `Power On` for unattended restart
- [ ] Mac: trust the TLS cert / add hosts entry (see [12](12-tls-certificate.md)) — purely cosmetic, `https://10.10.0.132:8006` works today
- [ ] pve3: identify the machine (`dmidecode -s system-product-name` **on pve3**) to configure bifurcation for the Azure FPGA card
- [ ] FPGA project: install **Quartus Prime Standard** (~20GB) — see [07](07-azure-fpga-smartnic.md)

## Recurring maintenance

- **After any kernel upgrade on pve2:** rebuild the `hpuefi` module (command in [09](09-bios-settings-dump.md)) or `hp-repsetup` stops working
- **Before 2027-09-01:** regenerate the TLS cert (command in [12](12-tls-certificate.md))
- **Keep Secure Boot disabled** — the unsigned `hpuefi` module requires it

## Open questions

- Where did the Hitachi drives come from? (Determines whether `sg_format` is needed)
- Wall outlet voltage for the Z8? (Determines 2 vs 3 GPUs at full power)
- RAID level preference — capacity vs write speed vs safety?
- Workload split: pve2 as storage+GPU, pve3 as compute? Or something else?
- What machine is pve3, exactly?
