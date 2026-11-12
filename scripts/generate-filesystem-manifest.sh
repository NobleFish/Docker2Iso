#!/usr/bin/env bash

set -Eeuo pipefail

rootfs="${1:?Usage: generate-filesystem-manifest.sh ROOTFS}"
dpkg_status_dir="$rootfs/var/lib/dpkg"

if [[ ! -d "$dpkg_status_dir" ]]; then
    printf 'Cannot generate package manifest: dpkg database directory is missing: %s\n' \
        "$dpkg_status_dir" >&2
    exit 1
fi

dpkg-query --admindir="$dpkg_status_dir" \
    -W \
    -f='${db:Status-Status}\t${Package}\t${Version}\n' \
    | awk -F '\t' '$1 == "installed" { print $2 "\t" $3 }' \
    | LC_ALL=C sort -u
