#!/usr/bin/env bash

set -Eeuo pipefail

squashfs_path="${1:?Usage: validate-iso-paths.sh SQUASHFS_PATH GRUB_CFG_PATH}"
grub_cfg_path="${2:?Usage: validate-iso-paths.sh SQUASHFS_PATH GRUB_CFG_PATH}"

validate_iso_path() {
    local label="$1" path="$2" component path_components_text
    local -a path_components

    if [[ ! "$path" =~ ^/[A-Za-z0-9._+/-]+$ ]]; then
        printf '%s must be an absolute ISO path using only letters, numbers, '.', '_', '+', '-', and '/': %s\n' \
            "$label" "$path" >&2
        exit 1
    fi

    path_components_text="${path#/}"
    IFS='/' read -r -a path_components <<< "$path_components_text"
    for component in "${path_components[@]}"; do
        if [[ -z "$component" || "$component" == . || "$component" == .. ]]; then
            printf '%s contains an invalid path component: %s\n' "$label" "$path" >&2
            exit 1
        fi
    done
}

validate_iso_path CASPER_SQUASHFS_PATH "$squashfs_path"
validate_iso_path GRUB_CFG_PATH "$grub_cfg_path"

managed_iso_paths=(
    /casper/filesystem.size
    /casper/filesystem.manifest
    /md5sum.txt
)

for configured_path in "$squashfs_path" "$grub_cfg_path"; do
    for managed_path in "${managed_iso_paths[@]}"; do
        if [[ "$configured_path" == "$managed_path" ||
              "$configured_path" == "$managed_path/"* ||
              "$managed_path" == "$configured_path/"* ]]; then
            printf 'Configured ISO path overlaps build-managed path %s: %s\n' \
                "$managed_path" "$configured_path" >&2
            exit 1
        fi
    done
done

if [[ "$squashfs_path" == "$grub_cfg_path" ||
      "$squashfs_path" == "$grub_cfg_path/"* ||
      "$grub_cfg_path" == "$squashfs_path/"* ]]; then
    echo "Configured SquashFS and GRUB paths must not overlap." >&2
    exit 1
fi
