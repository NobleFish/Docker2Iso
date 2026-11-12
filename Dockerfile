
# syntax=docker/dockerfile:1

# ============================================================
# STAGE 1: BUILD ENVIRONMENT
# ============================================================

FROM ubuntu:24.04 AS iso-builder

# Use Bash and enable pipeline failure detection.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ------------------------------------------------------------
# BUILD ARGUMENTS
# ------------------------------------------------------------

# SquashFS location inside the original Ubuntu ISO.
ARG CASPER_SQUASHFS_PATH=/casper/ubuntu-server-minimal.squashfs

# Enable or disable customization scripts.
ARG RUN_CUSTOMIZATION=true

# Original Ubuntu ISO checksum.
ARG UBUNTU_ISO_SHA256=97f3d7ffb032c3eb3b23d2c8be9cc76e60c2c1f2c0146ba5ba9fe01cafae0fd8

# Compression used for the rebuilt live filesystem.
ARG SQUASHFS_COMPRESSION=xz

# Original GRUB configuration location inside the ISO.
ARG GRUB_CFG_PATH=/boot/grub/grub.cfg

# Enable shell tracing in customization scripts when diagnosing a build.
ARG DEBUG_CUSTOMIZATION=false

# ------------------------------------------------------------
# INSTALL BUILD DEPENDENCIES
# ------------------------------------------------------------

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        xorriso \
        squashfs-tools \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# WORKING DIRECTORY
# ------------------------------------------------------------

WORKDIR /work

# ------------------------------------------------------------
# COPY BUILD INPUTS
# ------------------------------------------------------------

# Original Ubuntu ISO.
COPY ubuntu-24.04.5-live-server-amd64.iso /work/original.iso

# Verify and extract the source ISO in a cached layer that does not depend on
# the customization scripts or GRUB overlay.
RUN set -euo pipefail; \
    validate_iso_path() { \
        local label="$1" path="$2" component path_components_text; \
        local -a path_components; \
        if [[ ! "$path" =~ ^/[A-Za-z0-9._+/-]+$ ]]; then \
            echo "$label must be an absolute ISO path using only letters, numbers, '.', '_', '+', '-', and '/': $path" >&2; \
            exit 1; \
        fi; \
        path_components_text="${path#/}"; \
        IFS='/' read -r -a path_components <<< "$path_components_text"; \
        for component in "${path_components[@]}"; do \
            if [[ -z "$component" || "$component" == . || "$component" == .. ]]; then \
                echo "$label contains an invalid path component: $path" >&2; \
                exit 1; \
            fi; \
        done; \
    }; \
    validate_iso_path CASPER_SQUASHFS_PATH "$CASPER_SQUASHFS_PATH"; \
    validate_iso_path GRUB_CFG_PATH "$GRUB_CFG_PATH"; \
    for configured_path in "$CASPER_SQUASHFS_PATH" "$GRUB_CFG_PATH"; do \
        for managed_path in /casper/filesystem.size /casper/filesystem.manifest /md5sum.txt; do \
            if [[ "$configured_path" == "$managed_path" || \
                  "$configured_path" == "$managed_path/"* || \
                  "$managed_path" == "$configured_path/"* ]]; then \
                echo "Configured ISO path overlaps build-managed path $managed_path: $configured_path" >&2; \
                exit 1; \
            fi; \
        done; \
    done; \
    if [[ "$CASPER_SQUASHFS_PATH" == "$GRUB_CFG_PATH" || \
          "$CASPER_SQUASHFS_PATH" == "$GRUB_CFG_PATH/"* || \
          "$GRUB_CFG_PATH" == "$CASPER_SQUASHFS_PATH/"* ]]; then \
        echo "Configured SquashFS and GRUB paths must not overlap." >&2; \
        exit 1; \
    fi; \
    echo "=================================="; \
    echo " VERIFYING ORIGINAL UBUNTU ISO"; \
    echo "=================================="; \
    # Verify original ISO integrity.
    echo "$UBUNTU_ISO_SHA256  /work/original.iso" \
        | sha256sum --check --status; \
    echo "ISO checksum verified."; \
    # --------------------------------------------------------
    # EXTRACT ORIGINAL SQUASHFS
    # --------------------------------------------------------
    echo "Extracting Ubuntu filesystem..."; \
    xorriso -osirrox on \
        -indev /work/original.iso \
        -extract "$CASPER_SQUASHFS_PATH" \
        /work/filesystem.squashfs; \
    unsquashfs -f \
        -d /work/rootfs \
        /work/filesystem.squashfs && \
    rm /work/filesystem.squashfs

# Copy customization inputs after extraction so edits reuse the cached rootfs.
COPY scripts/ /work/scripts/

# ============================================================
# MAIN BUILD PROCESS
# ============================================================

RUN set -euo pipefail; \
    # --------------------------------------------------------
    # COPY CUSTOMIZATION SCRIPTS INTO ROOTFS
    # --------------------------------------------------------
    mkdir -p /work/rootfs/opt/iso-customize; \
    cp -a /work/scripts/. \
        /work/rootfs/opt/iso-customize/; \
    # --------------------------------------------------------
    # EXECUTE CUSTOMIZATION SCRIPTS
    # --------------------------------------------------------
    if [[ "$RUN_CUSTOMIZATION" == "true" ]]; then \
        echo "Running Ubuntu customization..."; \
        echo "Builder DNS configuration:"; \
        cat /etc/resolv.conf; \
        echo "Checking rootfs resolver:"; \
        ls -l /work/rootfs/etc/resolv.conf || true; \
        resolver_kind=absent; \
        resolver_link=""; \
        resolver_file_backup=""; \
        if [[ -L /work/rootfs/etc/resolv.conf ]]; then \
            resolver_kind=symlink; \
            resolver_link="$(readlink /work/rootfs/etc/resolv.conf)"; \
        elif [[ -e /work/rootfs/etc/resolv.conf ]]; then \
            resolver_kind=file; \
            resolver_file_backup=/work/rootfs-resolv.conf.original; \
            cp -a /work/rootfs/etc/resolv.conf "$resolver_file_backup"; \
        fi; \
        restore_rootfs_resolver() { \
            rm -f /work/rootfs/etc/resolv.conf; \
            if [[ "$resolver_kind" == symlink ]]; then \
                ln -s "$resolver_link" /work/rootfs/etc/resolv.conf; \
            elif [[ "$resolver_kind" == file ]]; then \
                mv "$resolver_file_backup" /work/rootfs/etc/resolv.conf; \
            fi; \
        }; \
        trap restore_rootfs_resolver EXIT; \
        rm -f /work/rootfs/etc/resolv.conf; \
        cp /etc/resolv.conf /work/rootfs/etc/resolv.conf; \
        chroot /work/rootfs \
            /usr/bin/env DEBIAN_FRONTEND=noninteractive DEBUG_CUSTOMIZATION="$DEBUG_CUSTOMIZATION" \
            /bin/bash /opt/iso-customize/customize.sh; \
        restore_rootfs_resolver; \
        trap - EXIT; \
    elif [[ "$RUN_CUSTOMIZATION" != "false" ]]; then \
        echo "RUN_CUSTOMIZATION must be true or false." >&2; \
        exit 1; \
    fi; \
    # Remove build scripts from the final Ubuntu filesystem.
    rm -rf /work/rootfs/opt/iso-customize; \
    # --------------------------------------------------------
    # REBUILD SQUASHFS
    # --------------------------------------------------------
    echo "Rebuilding Ubuntu SquashFS..."; \
    case "$SQUASHFS_COMPRESSION" in gzip|lzo|lz4|xz|zstd) ;; *) \
        echo "Unsupported SquashFS compression: $SQUASHFS_COMPRESSION" >&2; exit 1;; \
    esac; \
    compressor_help="$(mksquashfs -help 2>&1 || true)"; \
    if ! grep -Eq "(^|[[:space:],])${SQUASHFS_COMPRESSION}([[:space:],(]|$)" \
        <<< "$compressor_help"; then \
        echo "SquashFS compressor is not available in this mksquashfs build: $SQUASHFS_COMPRESSION" >&2; \
        exit 1; \
    fi; \
    filesystem_size="$(du -sx --block-size=1 /work/rootfs | cut -f1)"; \
    printf '%s' "$filesystem_size" > /work/filesystem.size; \
    /bin/bash /work/scripts/generate-filesystem-manifest.sh /work/rootfs \
        > /work/filesystem.manifest; \
    mksquashfs /work/rootfs \
        /work/filesystem-custom.squashfs \
        -noappend \
        -comp "$SQUASHFS_COMPRESSION"

# Keep the large root filesystem build cached independently of GRUB edits.
COPY grub-overlay/ /work/grub-overlay/

RUN set -euo pipefail; \
    managed_iso_paths=( \
        "$CASPER_SQUASHFS_PATH" \
        "$GRUB_CFG_PATH" \
        /casper/filesystem.size \
        /casper/filesystem.manifest \
        /md5sum.txt \
    ); \
    path_collides_with_managed() { \
        local candidate="$1" managed; \
        for managed in "${managed_iso_paths[@]}"; do \
            if [[ "$candidate" == "$managed" || \
                  "$candidate" == "$managed/"* || \
                  "$managed" == "$candidate/"* ]]; then \
                return 0; \
            fi; \
        done; \
        return 1; \
    }; \
    # ========================================================
    # GRUB CUSTOMIZATION
    # ========================================================
    echo "Preparing GRUB customization..."; \
    test -f /work/grub-overlay/boot/grub/custom.cfg; \
    # Extract the original GRUB configuration.
    xorriso -osirrox on \
        -indev /work/original.iso \
        -extract "$GRUB_CFG_PATH" \
        /work/grub.cfg \
        -extract /md5sum.txt \
        /work/md5sum.original; \
    # Add custom.cfg loading without replacing original entries.
    if ! grep -Fq 'source "$prefix/custom.cfg"' /work/grub.cfg; then \
        printf '\n%s\n' \
            '# Load additional custom GRUB entries.' \
            'if [ -f "$prefix/custom.cfg" ]; then' \
            '    source "$prefix/custom.cfg"' \
            'fi' \
            >> /work/grub.cfg; \
    fi; \
    # --------------------------------------------------------
    # PREPARE XORRISO ARGUMENTS
    # --------------------------------------------------------
    xorriso_args=( \
        xorriso \
        -indev /work/original.iso \
        -outdev /work/custom.iso \
    ); \
    # Replay boot metadata before changing files in the ISO tree.
    xorriso_args+=( -boot_image any replay ); \
    # Replace original SquashFS with customized SquashFS.
    xorriso_args+=( \
        -map \
        /work/filesystem-custom.squashfs \
        "$CASPER_SQUASHFS_PATH" \
    ); \
    xorriso_args+=( -map /work/filesystem.size /casper/filesystem.size ); \
    xorriso_args+=( -map /work/filesystem.manifest /casper/filesystem.manifest ); \
    # Replace original GRUB configuration with patched version.
    xorriso_args+=( \
        -map \
        /work/grub.cfg \
        "$GRUB_CFG_PATH" \
    ); \
    # --------------------------------------------------------
    # APPLY GRUB OVERLAY FILES
    # --------------------------------------------------------
    if find /work/grub-overlay -type l -print -quit | grep -q .; then \
        echo "GRUB overlay must contain regular files only; symbolic links are not supported." >&2; \
        exit 1; \
    fi; \
    mapfile -d '' overlay_files < <( \
        find /work/grub-overlay \
            -type f \
            ! -name '.keep' \
            -print0 \
    ); \
    changed_iso_paths=( \
        "./${CASPER_SQUASHFS_PATH#/}" \
        "./casper/filesystem.size" \
        "./casper/filesystem.manifest" \
        "./${GRUB_CFG_PATH#/}" \
    ); \
    for overlay_file in "${overlay_files[@]}"; do \
        # Convert local path to ISO path.
        overlay_rel_path="${overlay_file#/work/grub-overlay/}"; \
        iso_path="/$overlay_rel_path"; \
        if [[ ! "$overlay_rel_path" =~ ^[A-Za-z0-9._+/-]+$ ]]; then \
            echo "Invalid overlay destination: $iso_path" >&2; \
            exit 1; \
        fi; \
        IFS='/' read -r -a overlay_components <<< "$overlay_rel_path"; \
        for overlay_component in "${overlay_components[@]}"; do \
            if [[ -z "$overlay_component" || "$overlay_component" == . || "$overlay_component" == .. ]]; then \
                echo "Invalid overlay path component in: $iso_path" >&2; \
                exit 1; \
            fi; \
        done; \
        # Do not overwrite the patched main GRUB configuration.
        if [[ "$iso_path" == "$GRUB_CFG_PATH" ]]; then \
            echo "Overlay must not replace main grub.cfg." >&2; \
            exit 1; \
        fi; \
        if path_collides_with_managed "$iso_path"; then \
            echo "Overlay destination collides with a build-managed ISO path: $iso_path" >&2; \
            exit 1; \
        fi; \
        changed_iso_paths+=( ".${iso_path}" ); \
        # Add file to ISO.
        xorriso_args+=( \
            -map \
            "$overlay_file" \
            "$iso_path" \
        ); \
    done; \
    printf '%s\n' "${changed_iso_paths[@]}" > /work/changed-iso-paths.txt; \
    awk 'NR == FNR { skip[$0] = 1; next } !($2 in skip)' \
        /work/changed-iso-paths.txt /work/md5sum.original \
        > /work/md5sum.updated; \
    append_md5() { \
        local source_file="$1" iso_path="$2" hash; \
        hash="$(md5sum -- "$source_file")"; \
        printf '%s  %s\n' "${hash%% *}" "$iso_path" >> /work/md5sum.updated; \
    }; \
    append_md5 /work/filesystem-custom.squashfs "./${CASPER_SQUASHFS_PATH#/}"; \
    append_md5 /work/filesystem.size ./casper/filesystem.size; \
    append_md5 /work/filesystem.manifest ./casper/filesystem.manifest; \
    append_md5 /work/grub.cfg "./${GRUB_CFG_PATH#/}"; \
    for overlay_file in "${overlay_files[@]}"; do \
        overlay_rel_path="${overlay_file#/work/grub-overlay/}"; \
        append_md5 "$overlay_file" "./$overlay_rel_path"; \
    done; \
    LC_ALL=C sort -k2,2 /work/md5sum.updated -o /work/md5sum.updated; \
    xorriso_args+=( -map /work/md5sum.updated /md5sum.txt ); \
    # --------------------------------------------------------
    # PRESERVE ORIGINAL BOOT CONFIGURATION
    # --------------------------------------------------------
    xorriso_args+=( \
        -commit \
        -end \
    ); \
    # --------------------------------------------------------
    # BUILD CUSTOM ISO
    # --------------------------------------------------------
    echo "Building customized Ubuntu ISO..."; \
    "${xorriso_args[@]}"; \
    # Verify the ISO contains the exact rebuilt files.
    test -s /work/custom.iso; \
    mkdir -p /work/iso-verify/casper /work/iso-verify/boot/grub; \
    xorriso -osirrox on -indev /work/custom.iso \
        -extract "$CASPER_SQUASHFS_PATH" /work/iso-verify/filesystem.squashfs \
        -extract /casper/filesystem.size /work/iso-verify/casper/filesystem.size \
        -extract /casper/filesystem.manifest /work/iso-verify/casper/filesystem.manifest \
        -extract "$GRUB_CFG_PATH" /work/iso-verify/grub.cfg \
        -extract /md5sum.txt /work/iso-verify/md5sum.txt; \
    cmp /work/filesystem-custom.squashfs /work/iso-verify/filesystem.squashfs; \
    cmp /work/filesystem.size /work/iso-verify/casper/filesystem.size; \
    cmp /work/filesystem.manifest /work/iso-verify/casper/filesystem.manifest; \
    cmp /work/grub.cfg /work/iso-verify/grub.cfg; \
    cmp /work/md5sum.updated /work/iso-verify/md5sum.txt; \
    for overlay_file in "${overlay_files[@]}"; do \
        overlay_rel_path="${overlay_file#/work/grub-overlay/}"; \
        mkdir -p "/work/iso-verify/overlays/$(dirname "$overlay_rel_path")"; \
        xorriso -osirrox on -indev /work/custom.iso \
            -extract "/$overlay_rel_path" "/work/iso-verify/overlays/$overlay_rel_path"; \
        cmp "$overlay_file" "/work/iso-verify/overlays/$overlay_rel_path"; \
    done; \
    # --------------------------------------------------------
    # EXPORT ISO TO OUTPUT DIRECTORY
    # --------------------------------------------------------
    mkdir -p /output; \
    cp /work/custom.iso /output/custom.iso; \
    echo "ISO build completed."
# Prepare a container-friendly root filesystem after creating the ISO.
RUN set -euo pipefail; \
    mkdir -p /work/docker-rootfs; \
    tar --numeric-owner \
        --exclude='./proc' \
        --exclude='./sys' \
        --exclude='./dev' \
        --exclude='./run' \
        --exclude='./tmp' \
        --exclude='./etc/hosts' \
        --exclude='./etc/resolv.conf' \
        --exclude='./etc/hostname' \
        -cpf - -C /work/rootfs . \
        | tar --numeric-owner -xpf - -C /work/docker-rootfs; \
    mkdir -p /work/docker-rootfs/dev /work/docker-rootfs/proc \
        /work/docker-rootfs/sys /work/docker-rootfs/run /work/docker-rootfs/tmp; \
    chmod 1777 /work/docker-rootfs/tmp

# ============================================================
# STAGE 2: ISO ARTIFACT
# ============================================================

# Empty stage containing only the finished ISO.
FROM scratch AS iso-artifact

# Export custom.iso.
COPY --from=iso-builder /output/custom.iso /custom.iso

# ============================================================
# STAGE 3: CUSTOMIZED UBUNTU DOCKER IMAGE
# ============================================================
FROM scratch AS ubuntu-image

COPY --from=iso-builder /work/docker-rootfs/ /

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /root

CMD ["/bin/bash"]
