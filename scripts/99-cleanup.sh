#!/usr/bin/env bash
# 99-cleanup.sh - Script to clean up the Ubuntu filesystem after customization.

set -Eeuo pipefail

echo "Cleaning Ubuntu filesystem..."

apt-get clean

rm -rf /var/lib/apt/lists/*

# This directory is created only to validate sshd during offline customization.
rmdir /run/sshd 2>/dev/null || true

echo "Cleanup completed."
