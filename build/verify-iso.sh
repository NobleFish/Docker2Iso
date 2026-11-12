#!/usr/bin/env bash

set -Eeuo pipefail

custom_iso="${1:?Usage: verify-iso.sh ISO SQUASHFS_FILE SQUASHFS_PATH SIZE_FILE MANIFEST_FILE GRUB_PATH GRUB_FILE MD5_FILE OVERLAY_DIR VERIFY_DIR}"
squashfs_file="${2:?Missing expected SquashFS path}"
squashfs_iso_path="${3:?Missing SquashFS ISO path}"
size_file="${4:?Missing filesystem.size path}"
manifest_file="${5:?Missing filesystem.manifest path}"
grub_cfg_path="${6:?Missing GRUB configuration ISO path}"
grub_cfg_file="${7:?Missing patched GRUB configuration file}"
md5_file="${8:?Missing updated MD5 manifest path}"
overlay_dir="${9:?Missing GRUB overlay directory}"
verify_dir="${10:?Missing ISO verification directory}"
overlay_prefix="${overlay_dir%/}/"

echo "Verifying customized ISO contents..."
test -s "$custom_iso"
mkdir -p "$verify_dir/casper"

xorriso -osirrox on -indev "$custom_iso" \
    -extract "$squashfs_iso_path" "$verify_dir/filesystem.squashfs" \
    -extract /casper/filesystem.size "$verify_dir/casper/filesystem.size" \
    -extract /casper/filesystem.manifest "$verify_dir/casper/filesystem.manifest" \
    -extract "$grub_cfg_path" "$verify_dir/grub.cfg" \
    -extract /md5sum.txt "$verify_dir/md5sum.txt"

cmp "$squashfs_file" "$verify_dir/filesystem.squashfs"
cmp "$size_file" "$verify_dir/casper/filesystem.size"
cmp "$manifest_file" "$verify_dir/casper/filesystem.manifest"
cmp "$grub_cfg_file" "$verify_dir/grub.cfg"
cmp "$md5_file" "$verify_dir/md5sum.txt"

while IFS= read -r -d '' overlay_file; do
    overlay_rel_path="${overlay_file#"$overlay_prefix"}"
    verified_overlay="$verify_dir/overlays/$overlay_rel_path"
    mkdir -p "$(dirname "$verified_overlay")"
    xorriso -osirrox on -indev "$custom_iso" \
        -extract "/$overlay_rel_path" "$verified_overlay"
    cmp "$overlay_file" "$verified_overlay"
done < <(find "$overlay_dir" -type f ! -name '.keep' -print0)

echo "Customized ISO contents verified."
