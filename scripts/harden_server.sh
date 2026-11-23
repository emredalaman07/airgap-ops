#!/usr/bin/env bash
# Baseline hardening for RHEL/Rocky/AlmaLinux 9 (SSH, firewalld, SELinux)
# Usage: sudo ./scripts/harden_server.sh [--apply]  (dry-run by default)

set -euo pipefail

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONF_SRC="${REPO_DIR}/configs/99-bastion-hardening.conf"
SSH_CONF_DST="/etc/ssh/sshd_config.d/99-bastion-hardening.conf"

if [[ "${EUID}" -ne 0 ]]; then
    echo "run as root" >&2
    exit 1
fi

setup_ssh() {
    local user="${SUDO_USER:-$USER}"
    local keys="/home/${user}/.ssh/authorized_keys"

    # Guard against locking ourselves out when disabling password auth
    if [[ ! -s "${keys}" ]]; then
        echo "missing ${keys}; copy an ssh key before disabling password auth" >&2
        return 1
    fi

    if (( APPLY )); then
        install -m 600 "${SSH_CONF_SRC}" "${SSH_CONF_DST}"
        # Validate config before reloading sshd
        sshd -t
        systemctl reload sshd
        echo "sshd config applied"
    else
        echo "[dry-run] install ${SSH_CONF_SRC} -> ${SSH_CONF_DST} and reload sshd"
    fi
}

setup_firewall() {
    # Keep PostgreSQL (9999) local-only; expose only SSH on the public zone
    if (( APPLY )); then
        systemctl enable --now firewalld
        firewall-cmd --set-default-zone=public
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
        echo "firewalld services: $(firewall-cmd --list-services)"
    else
        echo "[dry-run] enable firewalld and allow ssh only"
    fi
}

check_selinux() {
    local mode
    mode="$(getenforce)"

    if [[ "${mode}" == "Enforcing" ]]; then
        echo "selinux: Enforcing"
        return 0
    fi

    # Update both runtime state and persistent config
    if (( APPLY )); then
        setenforce 1
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        echo "selinux switched to Enforcing"
    else
        echo "[dry-run] selinux is ${mode}, would set Enforcing"
    fi
}

setup_ssh
setup_firewall
check_selinux
