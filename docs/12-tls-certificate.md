# pve2 — Proxmox Web UI TLS Certificate

Installed 2026-07-30. Self-signed cert for the local domain `pve2.lab.example`.

## Why self-signed, not Let's Encrypt

`lab.example` is used as a **local-only domain**. Let's Encrypt requires public DNS validation, so ACME is not possible. Self-signed is the correct choice here.

*(If the domain is ever publicly registered, the better option is a **wildcard `*.lab.example` cert via DNS-01** — real trusted cert, no public A records needed, and individual hostnames stay out of Certificate Transparency logs.)*

## Current certificate

```
subject = CN=pve2.lab.example
issuer  = CN=pve2.lab.example     (self-signed)
valid   = 2026-07-31 → 2027-09-01   (397 days)
SAN     = DNS:pve2.lab.example, DNS:pve2, DNS:localhost,
          IP:10.10.0.132, IP:127.0.0.1
```

📅 **RENEW BEFORE 2027-09-01** — 397 days is deliberate: macOS and Chrome reject certs valid longer than 398 days, even manually trusted ones.

## Files

| Path | What |
|---|---|
| `/etc/pve/local/pveproxy-ssl.pem` | Certificate (custom cert; takes precedence over PVE's default) |
| `/etc/pve/local/pveproxy-ssl.key` | Private key — `root:www-data`, mode `640` |
| `/root/cert-backup/` | Backup of whatever was there before |

Restore the old cert: `cp -a /root/cert-backup/* /etc/pve/local/ && systemctl restart pveproxy`

## Regenerate (for renewal)

```bash
IP=$(ip -4 -o addr show vmbr0 | awk '{print $4}' | cut -d/ -f1)
openssl req -x509 -newkey rsa:4096 -sha256 -days 397 -nodes \
  -keyout /etc/pve/local/pveproxy-ssl.key \
  -out /etc/pve/local/pveproxy-ssl.pem \
  -subj "/CN=pve2.lab.example" \
  -addext "subjectAltName=DNS:pve2.lab.example,DNS:pve2,DNS:localhost,IP:$IP,IP:127.0.0.1" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"
chown root:www-data /etc/pve/local/pveproxy-ssl.key && chmod 640 /etc/pve/local/pveproxy-ssl.key
systemctl restart pveproxy
```

## Client setup (per device)

**DNS** — the hostname must resolve. Either add to the router's DNS at `10.10.0.254` (best — covers all devices), or per-machine:

```bash
echo "10.10.0.132  pve2.lab.example pve2" | sudo tee -a /etc/hosts
```

**Trust the cert (macOS)** — fetch it without needing SSH credentials:

```bash
openssl s_client -connect 10.10.0.132:8006 -servername pve2.lab.example </dev/null 2>/dev/null \
  | openssl x509 -out ~/Downloads/pve2-lab-example.pem
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/pve2-lab-example.pem
```

⚠️ Safari generally accepts a trusted self-signed **leaf** cert; **Chrome may not**, because `basicConstraints=CA:FALSE` means it isn't a CA. If Chrome keeps warning, the robust fix is a **two-tier internal CA**: create a CA once, trust that on each device, then sign host certs with it (covers pve3 and future services too).

## Network facts

| | |
|---|---|
| pve2 | `10.10.0.132` (vmbr0) |
| Mac | `10.10.0.144` |
| Gateway | `10.10.0.254` |
| Web UI | `https://pve2.lab.example:8006` (or `https://10.10.0.132:8006`) |
| SSH | Port 22 open, `pve-firewall` **disabled**; key auth not set up from the Mac |
