#!/usr/bin/env bash
# confirmation.sh - Script to confirm the customization of the Ubuntu ISO based docker image.

set -uo pipefail

IMAGE="${IMAGE:-custom-ubuntu:latest}"
failed=0

stage() {
    local name="$1"
    shift

    printf '\n[%s] %s\n' "$IMAGE" "$name"
    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        printf 'FAIL: %s\n' "$name" >&2
        failed=1
    fi
}

check_installed_packages() {
    local package status
    for package in ca-certificates curl wget git vim-tiny htop sudo openssh-server tzdata; do
        status="$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null)" || {
            printf 'Package is missing: %s\n' "$package" >&2
            return 1
        }
        if [[ "$status" != installed ]]; then
            printf 'Package is not installed: %s (%s)\n' "$package" "$status" >&2
            return 1
        fi
    done
}

check_removed_packages() {
    local package status
    for package in nano popularity-contest; do
        if status="$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null)" \
            && [[ "$status" == installed ]]; then
            printf 'Package should have been removed: %s\n' "$package" >&2
            return 1
        fi
    done
}

check_system_configuration() {
    grep -Fxq 'Etc/UTC' /etc/timezone \
        && test "$(readlink -f /etc/localtime)" = /usr/share/zoneinfo/Etc/UTC \
        && grep -Fq 'CUSTOM UBUNTU SERVER' /etc/motd \
        && grep -Fxq 'net.ipv4.ip_forward = 0' /etc/sysctl.d/99-custom.conf \
        && grep -Fxq 'net.ipv6.conf.all.forwarding = 0' /etc/sysctl.d/99-custom.conf
}

check_user_configuration() {
    id isoadmin >/dev/null \
        && id -nG isoadmin | tr ' ' '\n' | grep -Fxq sudo \
        && test "$(getent passwd isoadmin | cut -d: -f6)" = /home/isoadmin \
        && test "$(passwd -S isoadmin | awk '{print $2}')" = L \
        && test -d /home/isoadmin/custom \
        && test "$(stat -c '%U:%G' /home/isoadmin/custom)" = isoadmin:isoadmin
}

check_ssh_configuration() {
    local effective_config
    grep -Fxq 'ClientAliveInterval 300' /etc/ssh/sshd_config.d/99-custom.conf \
        && grep -Fxq 'ClientAliveCountMax 2' /etc/ssh/sshd_config.d/99-custom.conf \
        && test -f /etc/systemd/system/ssh.service.d/10-generate-host-keys.conf \
        && grep -Fxq 'ExecStartPre=/usr/bin/ssh-keygen -A' /etc/systemd/system/ssh.service.d/10-generate-host-keys.conf \
        && ! compgen -G '/etc/ssh/ssh_host_*_key' >/dev/null \
        && install -d -m 0755 /run/sshd \
        && ssh-keygen -A \
        && test -s /etc/ssh/ssh_host_ed25519_key \
        && test -s /etc/ssh/ssh_host_rsa_key \
        && sshd -t \
        && effective_config="$(sshd -T)" \
        && grep -Fxq 'clientaliveinterval 300' <<< "$effective_config" \
        && grep -Fxq 'clientalivecountmax 2' <<< "$effective_config" \
        && test "$(systemctl --root=/ is-enabled ssh.service)" = enabled
}

check_custom_application() {
    local output
    test -x /usr/local/bin/hello-custom \
        && output="$(hello-custom)" \
        && grep -Fxq 'Hello from my customized Ubuntu system!' <<<"$output" \
        && grep -Fxq 'This application was installed during the ISO build.' <<<"$output"
}

check_cleanup() {
    local leftover temporary_policy_backup
    leftover="$(find /var/lib/apt/lists /var/cache/apt/archives \
        -type f ! -name lock -print -quit 2>/dev/null)"
    temporary_policy_backup="$(find /tmp -maxdepth 1 -name 'policy-rc.d.*' -print -quit 2>/dev/null)"
    [[ -z "$leftover" && -z "$temporary_policy_backup" ]]
}

check_runtime_directories() {
    local path
    for path in /dev /proc /sys /run /tmp; do
        test -d "$path" || return 1
    done
    test "$(stat -c '%a' /tmp)" = 1777
}

stage '01 package installation' check_installed_packages
stage '02 package removal' check_removed_packages
stage '03 system configuration' check_system_configuration
stage '04 user configuration' check_user_configuration
stage '05 service configuration' check_ssh_configuration
stage '06 custom application' check_custom_application
stage '98 runtime directories' check_runtime_directories
stage '99 filesystem cleanup' check_cleanup

if (( failed )); then
    printf '\nOne or more image checks failed.\n' >&2
    exit 1
fi

printf '\nAll image checks passed.\n'
