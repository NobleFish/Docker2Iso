#!/usr/bin/env bash
# 02-package-removal.sh - Script to remove unwanted packages from the Ubuntu filesystem.

set -Eeuo pipefail

echo "Removing unwanted packages..."

# Packages you want removed.
PACKAGES=(
    nano
    popularity-contest
)

for package in "${PACKAGES[@]}"; do

    # Only attempt removal if the package is installed.
    if dpkg-query -W \
        -f='${db:Status-Status}' "$package" 2>/dev/null |
        grep -qx installed; then

        echo "Removing: $package"

        apt-get purge -y "$package"

    else

        echo "Not installed: $package"

    fi

done

echo "Package removal completed."
