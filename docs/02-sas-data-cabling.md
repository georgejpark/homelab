# SAS Data Cabling — P840 ↔ DL380p G8 Backplane

## Needed

**2× SFF-8643 (Mini-SAS HD) → SFF-8087 (Mini-SAS) cables** (~$12 each, Amazon/eBay).

- P840 side: two internal SFF-8643 ports, named **1I** and **2I** (confirmed in ssacli)
- Backplane side: two SFF-8087 ports, each serving 4 bays

## Connection map

```
P840 port 1I ──SFF-8643→8087──► backplane port A (bays 1–4)
P840 port 2I ──SFF-8643→8087──► backplane port B (bays 5–8)
```

Both cables required — one cable = only 4 of 8 bays work.

## Speed note

P840 is 12G SAS; the Gen8 backplane is 6G. SAS is backward compatible — links negotiate 6Gb/s per lane automatically. 8 lanes × 6G is far beyond what 8 SSDs behind PCIe 3.0 x8 will bottleneck on. Non-issue.

## Diagnostic table (after power + data connected)

| `lsscsi -g` result | Meaning |
|---|---|
| 8 drives | whole chain verified |
| 4 drives | one SAS cable loose / wrong port |
| 0 drives | backplane power problem |
| drives error / odd size | 520-byte sector format → `sg_format --format --size=512 /dev/sgX` (SAN-pull drives; takes a while per drive) |
