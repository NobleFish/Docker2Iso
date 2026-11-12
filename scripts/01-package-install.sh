
#!/usr/bin/env bash

set -Eeuo pipefail

# Print every command before executing it.
export PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
set -x

echo "=================================="
echo " NETWORK DIAGNOSTICS"
echo "=================================="

echo "Container DNS configuration:"
cat /etc/resolv.conf

echo
echo "Checking Ubuntu repository DNS:"
if getent hosts archive.ubuntu.com; then
    echo "DNS resolution successful."
else
    echo "ERROR: DNS resolution failed."
fi

echo
echo "Checking HTTPS connectivity:"
if curl -Iv --connect-timeout 10 https://archive.ubuntu.com/ubuntu/; then
    echo "HTTPS connectivity successful."
else
    echo "ERROR: HTTPS connectivity failed."
fi

echo
echo "=================================="
echo " END NETWORK DIAGNOSTICS"
echo "=================================="


echo "Starting APT repository update..."

echo "Configured APT repositories:"
grep -RhsE '^[[:space:]]*(URIs:|deb[[:space:]])' \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true

if ! timeout --signal=TERM 300s apt-get \
    -o APT::Color=0 \
    -o Acquire::http::Timeout=20 \
    -o Acquire::https::Timeout=20 \
    -o Acquire::Retries=0 \
    -o Acquire::Languages=none \
    update; then
    echo "ERROR: APT repository update failed or exceeded its 5-minute limit." >&2
    exit 1
fi

echo "APT repository update finished."

echo "Installing packages..."

policy_rc_d=/usr/sbin/policy-rc.d
policy_rc_d_backup="$(mktemp /tmp/policy-rc.d.XXXXXX)"
policy_rc_d_existed=false

if [[ -e "$policy_rc_d" || -L "$policy_rc_d" ]]; then
    cp -a "$policy_rc_d" "$policy_rc_d_backup"
    policy_rc_d_existed=true
fi

restore_policy_rc_d() {
    rm -f "$policy_rc_d"
    if [[ "$policy_rc_d_existed" == true ]]; then
        mv "$policy_rc_d_backup" "$policy_rc_d"
    else
        rm -f "$policy_rc_d_backup"
    fi
}

trap restore_policy_rc_d EXIT
cat > "$policy_rc_d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 0755 "$policy_rc_d"

apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    vim-tiny \
    htop \
    sudo \
    openssh-server \
    tzdata

restore_policy_rc_d
trap - EXIT

echo "Package installation completed."
