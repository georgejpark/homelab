# 15 — GitHub repos on Proxmox instead of a paid cloud (started 2026-10-20)

## Decision

- No AWS / Azure / GCP spend. Every one of the 78 repos on github.com/georgejpark gets a
  `proxmox/` folder with a **cloud-dependency verdict** and a **Proxmox deployment plan**.
  A repo only goes to a cloud later if its verdict is REQUIRED and George decides to pay.
- **GPU host = pve2** (HP Z8 G4, 10.10.0.132, `ssh pve2`) with **2× NVIDIA CMP 170HX**.
  pve5 (10.10.0.106) hosts ordinary LXC containers (it already runs CT 101 `rea`).
- CI stays on GitHub-hosted runners for lint/validate/test only (free tier). Deployment to
  Proxmox runs through self-hosted runners (secure-iac-pipeline's ci-dev / ci-stage / ci-prod).

## Verdict scale used in every `proxmox/README.md`

| Verdict | Meaning | Proxmox approach |
|---|---|---|
| NONE | Runs from source / containers with no cloud SDK or provider | LXC or VM, run as upstream documents |
| OPTIONAL | Cloud integrations exist but a local mode or drop-in exists | Substitute: MinIO for S3, LocalStack, local Postgres/Redis, Ollama/vLLM for hosted LLM APIs |
| REQUIRED | The product *is* cloud infrastructure (Terraform for AWS/Azure, AWS-only services) | Port the provider layer to `bpg/proxmox`, or park until a cloud is funded |

## Backups

- Bare git mirrors of all 78 repos: `/Volumes/NVME2/REPO-2026-backup/<name>.git`
  (12 GB, manifest `MANIFEST-2026-10-20.tsv`). Re-run `zsh ~/Desktop/GITHUB-2026/backup-all.sh`
  from the Mac terminal to refresh; it only fetches deltas.
- Working clones: 68 mirrors in `/Volumes/NVME2/REPO-2026-git/`, the 10 own repos in
  `~/Desktop/GITHUB-2026/`.
- Second copy on pve5 `nvmepool` is still to do (LAN was unreachable from the Mac on 2026-10-20).

## CMP 170HX facts to verify on pve2 before promising performance

- GA100 die, 8 GB HBM2e, compute capability 8.0 (Ampere), no display outputs.
- Mining SKU: FP32 throughput is deliberately reduced and the PCIe link is narrow; check
  `nvidia-smi -q | grep -A2 'Link Width'` and run a short FP16 matmul benchmark before
  assigning LLM-inference repos to it.
- Driver: the standard NVIDIA Linux driver recognises it; passthrough needs the usual vfio
  binding on pve2 (already configured per 05/06).

## Per-repo status

Filled from each repo's `proxmox/README.md`; master table in
`~/Desktop/GITHUB-2026/proxmox-assessment.md` (generated 2026-10-20).

## Related

- `~/Desktop/GITHUB-2026/cicd-status-2026-10-20.md` — Actions disabled on all 78 repos.
- `~/Desktop/GITHUB-2026/stop-cicd.sh`, `backup-all.sh`, `verify-push.sh`, `push-all.sh`.
