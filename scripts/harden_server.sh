#!/usr/bin/env bash
# Baseline host setup for Rocky/RHEL 9 (sshd, firewalld, SELinux)
# Dry-run by default; pass --apply to make changes.

set -euo pipefail

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
    APPLY=1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONF_SRC="${REPO_DIR}/configs/99-airgap-hardening.conf"
SSH_CONF_DST="/etc/ssh/sshd_config.d/99-airgap-hardening.conf"

if [[ "${EUID}" -ne 0 ]]; then
    echo "error: run with sudo/root" >&2
    exit 1
fi

setup_ssh() {
    local target_user="${SUDO_USER:-$USER}"
    local auth_keys="/home/${target_user}/.ssh/authorized_keys"

    if [[ "${target_user}" == "root" ]]; then
        auth_keys="/root/.ssh/authorized_keys"
    fi

    # Make sure a key exists before turning off password auth
    if [[ ! -s "${auth_keys}" ]]; then
        echo "error: ${auth_keys} is missing or empty; copy your public key first" >&2
        return 1
    fi

    if (( APPLY )); then
        install -m 600 "${SSH_CONF_SRC}" "${SSH_CONF_DST}"
        sshd -t
        systemctl reload sshd
        echo "sshd: applied ${SSH_CONF_DST}"
    else
        echo "[dry-run] install ${SSH_CONF_SRC} -> ${SSH_CONF_DST} and reload sshd"
    fi
}

setup_firewall() {
    # PostgreSQL stays on 127.0.0.1:9999, so only ssh is needed externally
    if (( APPLY )); then
        systemctl enable --now firewalld
        firewall-cmd --set-default-zone=public >/dev/null
        firewall-cmd --permanent --add-service=ssh >/dev/null
        firewall-cmd --reload >/dev/null
        echo "firewalld: active (allowed: $(firewall-cmd --list-services))"
    else
        echo "[dry-run] enable firewalld and allow ssh on public zone"
    fi
}

setup_selinux() {
    local mode
    mode="$(getenforce)"

    if [[ "${mode}" == "Enforcing" ]]; then
        echo "selinux: already Enforcing"
        return 0
    fi

    if (( APPLY )); then
        setenforce 1
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        echo "selinux: set to Enforcing"
    else
        echo "[dry-run] selinux is ${mode}, would switch to Enforcing"
    fi
}

setup_ssh
setup_firewall
setup_selinux
