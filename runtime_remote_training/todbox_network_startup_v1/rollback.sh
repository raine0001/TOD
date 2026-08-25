#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="/var/backups/todbox-network-startup"
BACKUP_DIR="${1:-${BACKUP_ROOT}/latest}"
NETPLAN_TARGET="/etc/netplan/60-todbox-service-ip.yaml"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo $0 [backup-directory]" >&2
  exit 2
fi
if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "Backup directory not found: ${BACKUP_DIR}" >&2
  exit 3
fi

systemctl disable --now todbox-startup-connectivity-verify.timer todbox-startup-connectivity-verify.service 2>/dev/null || true
state="$(cat "${BACKUP_DIR}/netplan-target-state")"
if [[ "${state}" == "present" ]]; then
  install -o root -g root -m 600 "${BACKUP_DIR}/60-todbox-service-ip.yaml" "${NETPLAN_TARGET}"
elif [[ "${state}" == "absent" ]]; then
  rm -f "${NETPLAN_TARGET}"
else
  echo "Invalid rollback state: ${state}" >&2
  exit 4
fi

rm -f /etc/systemd/system/todbox-startup-connectivity-verify.service
rm -f /etc/systemd/system/todbox-startup-connectivity-verify.timer
rm -f /usr/local/sbin/todbox-startup-connectivity-verify
systemctl daemon-reload
netplan generate
netplan apply
echo "Rolled back TODBOX fixed service IP and startup verification using ${BACKUP_DIR}."
