#!/usr/bin/env bash
# prep-vm.sh - zet een verse Ubuntu 24.04-VM klaar voor de DV3-usability tests.
# Gebruik:  sudo bash prep-vm.sh <hostname>      bijv. sudo bash prep-vm.sh dokploy-01
# Draai dit op elke test-VM, VOORDAT de tijd voor T1 start.

set -euo pipefail

# ---- Instellingen (voor alle VM's gelijk houden) ----
UFW_MODE="off"            # "off" = ufw uit | "on" = ufw aan met alleen SSH open
TIMEZONE="Europe/Amsterdam"
DOMAIN="lab.local"        # voor de FQDN die Dokku wil
SSH_PUBKEY=""             # optioneel: plak hier je public key tussen de quotes
# ------------------------------------------------------

if [[ $EUID -ne 0 ]]; then echo "Draai dit met sudo."; exit 1; fi
NEW_HOST="${1:-$(hostname)}"
REAL_USER="${SUDO_USER:-ubuntu}"
LOG="/home/${REAL_USER}/prep-vm.log"

wait_for_apt() {
  echo "--> Wachten tot automatische updates klaar zijn..."
  while pgrep -x unattended-upgr >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null; do
    sleep 5
  done
}

echo "--> Hostname instellen: ${NEW_HOST}"
hostnamectl set-hostname "${NEW_HOST}"
sed -i '/^127\.0\.1\.1/d' /etc/hosts
echo "127.0.1.1 ${NEW_HOST}.${DOMAIN} ${NEW_HOST}" >> /etc/hosts

wait_for_apt
echo "--> Updates en basistools"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q curl wget git jq htop

echo "--> Tijdzone: ${TIMEZONE}"
timedatectl set-timezone "${TIMEZONE}"

echo "--> SSH aan (blijft aan na reboot)"
systemctl enable --now ssh

if [[ -n "${SSH_PUBKEY}" ]]; then
  echo "--> SSH-key toevoegen"
  install -d -m 700 -o "${REAL_USER}" -g "${REAL_USER}" "/home/${REAL_USER}/.ssh"
  grep -qxF "${SSH_PUBKEY}" "/home/${REAL_USER}/.ssh/authorized_keys" 2>/dev/null \
    || echo "${SSH_PUBKEY}" >> "/home/${REAL_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${REAL_USER}/.ssh/authorized_keys"
  chown "${REAL_USER}:${REAL_USER}" "/home/${REAL_USER}/.ssh/authorized_keys"
fi

echo "--> ufw: ${UFW_MODE}"
if [[ "${UFW_MODE}" == "on" ]]; then
  ufw allow ssh
  ufw --force enable
else
  ufw --force disable || true
fi

echo "--> Controle en versies (ook in ${LOG})"
{
  echo "=== prep-vm $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "Hostname:   $(hostname) / FQDN: $(hostname -f)"
  echo "OS:         $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "Kernel:     $(uname -r)"
  echo "CPU / RAM:  $(nproc) vCPU / $(free -h | awk '/Mem:/{print $2}')"
  echo "Disk /:     $(df -h / | awk 'NR==2{print $2" totaal, "$4" vrij"}')"
  echo "Swap:       $(swapon --show --noheadings | wc -l) actief (moet 0 zijn)"
  echo "ufw:        $(ufw status | head -1)"
  echo "Machine-id: $(cat /etc/machine-id)"
  echo "Reboot nodig: $([[ -f /var/run/reboot-required ]] && echo ja || echo nee)"
} | tee -a "${LOG}"

echo
echo "Klaar. Staat 'Reboot nodig' op ja: sudo reboot, en daarna:"
echo "  while pgrep -x unattended-upgr >/dev/null || pgrep -x apt-get >/dev/null; do sleep 5; done; echo klaar"
echo "Pas daarna de tijd voor T1 starten."
