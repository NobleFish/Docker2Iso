#!/usr/bin/env bash

set -Eeuo pipefail

rootfs="${1:?Usage: rebuild-squashfs.sh ROOTFS COMPRESSION SIZE_FILE MANIFEST_FILE OUTPUT_FILE MANIFEST_GENERATOR}"
compression="${2:?Missing SquashFS compression}"
size_file="${3:?Missing filesystem.size output path}"
manifest_file="${4:?Missing filesystem.manifest output path}"
output_file="${5:?Missing SquashFS output path}"
manifest_generator="${6:?Missing package manifest generator path}"

case "$compression" in
    gzip|lzo|lz4|xz|zstd) ;;
    *)
        printf 'Unsupported SquashFS compression: %s\n' "$compression" >&2
        exit 1
        ;;
esac

compressor_help="$(mksquashfs -help 2>&1 || true)"
if ! grep -Eq "(^|[[:space:],])${compression}([[:space:],(]|$)" <<< "$compressor_help"; then
    printf 'SquashFS compressor is not available in this mksquashfs build: %s\n' \
        "$compression" >&2
    exit 1
fi

echo "Rebuilding Ubuntu SquashFS with $compression compression..."
filesystem_size="$(du -sx --block-size=1 "$rootfs" | cut -f1)"
printf '%s' "$filesystem_size" > "$size_file"
/bin/bash "$manifest_generator" "$rootfs" > "$manifest_file"
mksquashfs "$rootfs" "$output_file" -noappend -comp "$compression"
