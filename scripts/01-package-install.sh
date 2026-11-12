
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

echo "Package installation completed."
