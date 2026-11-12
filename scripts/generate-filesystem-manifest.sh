#!/usr/bin/env bash

set -Eeuo pipefail

rootfs="${1:?Usage: generate-filesystem-manifest.sh ROOTFS}"

dpkg-query --admindir="$rootfs/var/lib/dpkg" \
    -W \
    -f='${db:Status-Status}\t${Package}\t${Version}\n' \
    | awk -F '\t' '$1 == "installed" { print $2 "\t" $3 }' \
    | LC_ALL=C sort -u
