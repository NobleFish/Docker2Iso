#!/usr/bin/env bash

set -Eeuo pipefail

rootfs="${1:?Usage: export-docker-rootfs.sh ROOTFS OUTPUT_DIR}"
output_dir="${2:?Missing Docker rootfs output directory}"

echo "Preparing Docker root filesystem..."
mkdir -p "$output_dir"

tar --numeric-owner \
    --exclude='./proc' \
    --exclude='./sys' \
    --exclude='./dev' \
    --exclude='./run' \
    --exclude='./tmp' \
    --exclude='./etc/hosts' \
    --exclude='./etc/resolv.conf' \
    --exclude='./etc/hostname' \
    -cpf - -C "$rootfs" . \
    | tar --numeric-owner -xpf - -C "$output_dir"

mkdir -p "$output_dir/dev" "$output_dir/proc" "$output_dir/sys" \
    "$output_dir/run" "$output_dir/tmp"
chmod 1777 "$output_dir/tmp"
echo "Docker root filesystem prepared."
