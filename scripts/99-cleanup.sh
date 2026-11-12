
#!/usr/bin/env bash

set -Eeuo pipefail

echo "Cleaning Ubuntu filesystem..."

apt-get clean

rm -rf /var/lib/apt/lists/*

# This directory is created only to validate sshd during offline customization.
rmdir /run/sshd 2>/dev/null || true

echo "Cleanup completed."
