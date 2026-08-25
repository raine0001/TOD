#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOST="tod-ai-01"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="/var/backups/todbox-system-inventory/${STAMP}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 2
fi
if [[ "$(hostname)" != "${EXPECTED_HOST}" ]]; then
  echo "Refusing wrong host: expected ${EXPECTED_HOST}, got $(hostname)" >&2
  exit 3
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
if [[ -e /usr/local/sbin/todbox-startup-connectivity-verify ]]; then
  cp -a /usr/local/sbin/todbox-startup-connectivity-verify "${BACKUP_DIR}/verifier.before"
fi
if [[ -e /usr/local/bin/todbox-system-inventory-query ]]; then
  cp -a /usr/local/bin/todbox-system-inventory-query "${BACKUP_DIR}/query.before"
fi

rollback_on_error() {
  if [[ -e "${BACKUP_DIR}/verifier.before" ]]; then
    cp -a "${BACKUP_DIR}/verifier.before" /usr/local/sbin/todbox-startup-connectivity-verify
  fi
  if [[ -e "${BACKUP_DIR}/query.before" ]]; then
    cp -a "${BACKUP_DIR}/query.before" /usr/local/bin/todbox-system-inventory-query
  else
    rm -f /usr/local/bin/todbox-system-inventory-query
  fi
  echo "Inventory installation failed; prior tools restored from ${BACKUP_DIR}." >&2
}
trap rollback_on_error ERR

install -o root -g root -m 755 \
  "${SOURCE_DIR}/todbox-startup-connectivity-verify.py" \
  /usr/local/sbin/todbox-startup-connectivity-verify
install -o root -g root -m 755 \
  "${SOURCE_DIR}/todbox-system-inventory-query.py" \
  /usr/local/bin/todbox-system-inventory-query

systemctl restart todbox-startup-connectivity-verify.service
test -s /var/lib/todbox-connectivity/system-inventory.latest.json
/usr/local/bin/todbox-system-inventory-query forum_image_generation >/dev/null

trap - ERR

echo "TOD-owned system inventory installed and verified."
echo "Inventory: /var/lib/todbox-connectivity/system-inventory.latest.json"
echo "Query: todbox-system-inventory-query forum_image_generation"
echo "Rollback backup: ${BACKUP_DIR}"
