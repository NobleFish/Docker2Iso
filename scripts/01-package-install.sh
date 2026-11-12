
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

apt-get \
    -o APT::Color=0 \
    -o Acquire::http::Timeout=20 \
    -o Acquire::https::Timeout=20 \
    -o Acquire::Retries=0 \
    -o Debug::Acquire::http=true \
    -o Debug::Acquire::https=true \
    update

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
