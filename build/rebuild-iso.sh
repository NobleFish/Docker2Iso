#!/usr/bin/env bash

set -Eeuo pipefail

original_iso="${1:?Usage: rebuild-iso.sh ORIGINAL_ISO SQUASHFS SIZE_FILE MANIFEST_FILE SQUASHFS_PATH GRUB_CFG_PATH OVERLAY_DIR OUTPUT_ISO}"
squashfs_file="${2:?Missing rebuilt SquashFS path}"
size_file="${3:?Missing filesystem.size path}"
manifest_file="${4:?Missing filesystem.manifest path}"
squashfs_iso_path="${5:?Missing SquashFS ISO destination}"
grub_cfg_path="${6:?Missing GRUB configuration ISO path}"
overlay_dir="${7:?Missing GRUB overlay directory}"
output_iso="${8:?Missing output ISO path}"

work_dir="$(dirname "$output_iso")"
overlay_prefix="${overlay_dir%/}/"
grub_cfg_file="$work_dir/grub.cfg"
original_md5_file="$work_dir/md5sum.original"
updated_md5_file="$work_dir/md5sum.updated"
changed_paths_file="$work_dir/changed-iso-paths.txt"

managed_iso_paths=(
    "$squashfs_iso_path"
    "$grub_cfg_path"
    /casper/filesystem.size
    /casper/filesystem.manifest
    /md5sum.txt
)

path_collides_with_managed() {
    local candidate="$1" managed
    for managed in "${managed_iso_paths[@]}"; do
        if [[ "$candidate" == "$managed" ||
              "$candidate" == "$managed/"* ||
              "$managed" == "$candidate/"* ]]; then
            return 0
        fi
    done
    return 1
}

validate_overlay_path() {
    local relative_path="$1" component
    local -a components

    if [[ ! "$relative_path" =~ ^[A-Za-z0-9._+/-]+$ ]]; then
        printf 'Invalid overlay destination: /%s\n' "$relative_path" >&2
        exit 1
    fi

    IFS='/' read -r -a components <<< "$relative_path"
    for component in "${components[@]}"; do
        if [[ -z "$component" || "$component" == . || "$component" == .. ]]; then
            printf 'Invalid overlay path component in: /%s\n' "$relative_path" >&2
            exit 1
        fi
    done
}

if [[ ! -f "$overlay_dir/boot/grub/custom.cfg" ]]; then
    printf 'Required GRUB overlay file is missing: %s/boot/grub/custom.cfg\n' "$overlay_dir" >&2
    exit 1
fi

if find "$overlay_dir" -type l -print -quit | grep -q .; then
    echo "GRUB overlay must contain regular files only; symbolic links are not supported." >&2
    exit 1
fi

echo "Preparing GRUB customization..."
xorriso -osirrox on \
    -indev "$original_iso" \
    -extract "$grub_cfg_path" "$grub_cfg_file" \
    -extract /md5sum.txt "$original_md5_file"

if ! grep -Fq 'source "$prefix/custom.cfg"' "$grub_cfg_file"; then
    printf '\n%s\n' \
        '# Load additional custom GRUB entries.' \
        'if [ -f "$prefix/custom.cfg" ]; then' \
        '    source "$prefix/custom.cfg"' \
        'fi' \
        >> "$grub_cfg_file"
fi

xorriso_args=(xorriso -indev "$original_iso" -outdev "$output_iso")
xorriso_args+=( -boot_image any replay )
xorriso_args+=( -map "$squashfs_file" "$squashfs_iso_path" )
xorriso_args+=( -map "$size_file" /casper/filesystem.size )
xorriso_args+=( -map "$manifest_file" /casper/filesystem.manifest )
xorriso_args+=( -map "$grub_cfg_file" "$grub_cfg_path" )

mapfile -d '' overlay_files < <(
    find "$overlay_dir" -type f ! -name '.keep' -print0
)

changed_iso_paths=(
    "./${squashfs_iso_path#/}"
    ./casper/filesystem.size
    ./casper/filesystem.manifest
    "./${grub_cfg_path#/}"
)

for overlay_file in "${overlay_files[@]}"; do
    overlay_rel_path="${overlay_file#"$overlay_prefix"}"
    iso_path="/$overlay_rel_path"
    validate_overlay_path "$overlay_rel_path"

    if path_collides_with_managed "$iso_path"; then
        printf 'Overlay destination collides with a build-managed ISO path: %s\n' "$iso_path" >&2
        exit 1
    fi

    changed_iso_paths+=( ".${iso_path}" )
    xorriso_args+=( -map "$overlay_file" "$iso_path" )
done

printf '%s\n' "${changed_iso_paths[@]}" > "$changed_paths_file"
awk 'NR == FNR { skip[$0] = 1; next } !($2 in skip)' \
    "$changed_paths_file" "$original_md5_file" > "$updated_md5_file"

append_md5() {
    local source_file="$1" iso_path="$2" hash
    hash="$(md5sum -- "$source_file")"
    printf '%s  %s\n' "${hash%% *}" "$iso_path" >> "$updated_md5_file"
}

append_md5 "$squashfs_file" "./${squashfs_iso_path#/}"
append_md5 "$size_file" ./casper/filesystem.size
append_md5 "$manifest_file" ./casper/filesystem.manifest
append_md5 "$grub_cfg_file" "./${grub_cfg_path#/}"

for overlay_file in "${overlay_files[@]}"; do
    overlay_rel_path="${overlay_file#"$overlay_prefix"}"
    append_md5 "$overlay_file" "./$overlay_rel_path"
done

LC_ALL=C sort -k2,2 "$updated_md5_file" -o "$updated_md5_file"
xorriso_args+=( -map "$updated_md5_file" /md5sum.txt -commit -end )

echo "Building customized Ubuntu ISO..."
"${xorriso_args[@]}"
test -s "$output_iso"
