#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOST="tod-ai-01"
INTERFACE="enp7s0f0"
EXPECTED_MAC="08:60:6e:00:62:7d"
FIXED_IP="192.168.1.10"
FIXED_CIDR="${FIXED_IP}/24"
GATEWAY="192.168.1.1"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="/var/backups/todbox-network-startup"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
NETPLAN_TARGET="/etc/netplan/60-todbox-service-ip.yaml"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 2
fi
if [[ "$(hostname)" != "${EXPECTED_HOST}" ]]; then
  echo "Refusing wrong host: expected ${EXPECTED_HOST}, got $(hostname)" >&2
  exit 3
fi
if [[ ! -e "/sys/class/net/${INTERFACE}/address" ]]; then
  echo "Missing expected interface ${INTERFACE}" >&2
  exit 4
fi
if [[ "$(tr '[:upper:]' '[:lower:]' < "/sys/class/net/${INTERFACE}/address")" != "${EXPECTED_MAC}" ]]; then
  echo "Refusing unexpected MAC on ${INTERFACE}" >&2
  exit 5
fi
if ! ip route show default | grep -q "default via ${GATEWAY} dev ${INTERFACE}"; then
  echo "Expected default route via ${GATEWAY} on ${INTERFACE} is absent" >&2
  exit 6
fi
if ip -4 address show | grep -q "inet ${FIXED_CIDR}"; then
  echo "${FIXED_CIDR} is already configured; refusing ambiguous reinstall" >&2
  exit 7
fi
if ip neigh show "${FIXED_IP}" | grep -qE 'lladdr|REACHABLE|STALE|DELAY|PROBE|PERMANENT'; then
  echo "Candidate ${FIXED_IP} has a neighbor entry; investigate before installation" >&2
  exit 8
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_ROOT}" "${BACKUP_DIR}"
if [[ -e "${NETPLAN_TARGET}" ]]; then
  cp -a "${NETPLAN_TARGET}" "${BACKUP_DIR}/60-todbox-service-ip.yaml"
  printf 'present\n' > "${BACKUP_DIR}/netplan-target-state"
else
  printf 'absent\n' > "${BACKUP_DIR}/netplan-target-state"
fi
cp -a /etc/netplan "${BACKUP_DIR}/netplan-before"
ln -sfn "${BACKUP_DIR}" "${BACKUP_ROOT}/latest"

install -o root -g root -m 600 "${SOURCE_DIR}/60-todbox-service-ip.yaml" "${NETPLAN_TARGET}"
install -o root -g root -m 755 "${SOURCE_DIR}/todbox-startup-connectivity-verify.py" /usr/local/sbin/todbox-startup-connectivity-verify
install -o root -g root -m 755 "${SOURCE_DIR}/todbox-system-inventory-query.py" /usr/local/bin/todbox-system-inventory-query
install -o root -g root -m 755 "${SOURCE_DIR}/rollback.sh" /usr/local/sbin/todbox-network-startup-rollback
install -o root -g root -m 644 "${SOURCE_DIR}/todbox-startup-connectivity-verify.service" /etc/systemd/system/todbox-startup-connectivity-verify.service
install -o root -g root -m 644 "${SOURCE_DIR}/todbox-startup-connectivity-verify.timer" /etc/systemd/system/todbox-startup-connectivity-verify.timer

netplan generate
netplan apply
sleep 3
ip -4 address show dev "${INTERFACE}" | grep -q "inet ${FIXED_CIDR}"

systemctl daemon-reload
systemctl enable todbox-startup-connectivity-verify.service todbox-startup-connectivity-verify.timer
systemctl start todbox-startup-connectivity-verify.timer
systemctl start --no-block todbox-startup-connectivity-verify.service

echo "Installed fixed service IP ${FIXED_CIDR} on ${INTERFACE}."
echo "Backup and rollback state: ${BACKUP_DIR}"
echo "Evidence: /var/lib/todbox-connectivity/latest.json"
echo "System inventory: /var/lib/todbox-connectivity/system-inventory.latest.json"
