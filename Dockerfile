
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

# Original GRUB configuration location inside the ISO.
ARG GRUB_CFG_PATH=/boot/grub/grub.cfg

# ------------------------------------------------------------
# INSTALL BUILD DEPENDENCIES
# ------------------------------------------------------------

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        xorriso \
        squashfs-tools \
        proot \
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

# Customization scripts.
COPY scripts/ /work/scripts/

# Custom GRUB files.
COPY grub-overlay/ /work/grub-overlay/

# ============================================================
# MAIN BUILD PROCESS
# ============================================================

RUN set -euo pipefail; \

    echo "=================================="; \
    echo " VERIFYING ORIGINAL UBUNTU ISO"; \
    echo "=================================="; \
    \
    # Verify original ISO integrity.
    echo "$UBUNTU_ISO_SHA256  /work/original.iso" \
        | sha256sum --check --status; \
    \
    echo "ISO checksum verified."; \
    \
    # --------------------------------------------------------
    # EXTRACT ORIGINAL SQUASHFS
    # --------------------------------------------------------
    \
    echo "Extracting Ubuntu filesystem..."; \
    \
    xorriso -osirrox on \
        -indev /work/original.iso \
        -extract "$CASPER_SQUASHFS_PATH" \
        /work/filesystem.squashfs; \
    \
    unsquashfs -f \
        -d /work/rootfs \
        /work/filesystem.squashfs; \
    \
    # --------------------------------------------------------
    # COPY CUSTOMIZATION SCRIPTS INTO ROOTFS
    # --------------------------------------------------------
    \
    mkdir -p /work/rootfs/opt/iso-customize; \
    \
    cp -a /work/scripts/. \
        /work/rootfs/opt/iso-customize/; \
    \
    # --------------------------------------------------------
    # EXECUTE CUSTOMIZATION SCRIPTS
    # --------------------------------------------------------
    \
    if [[ "$RUN_CUSTOMIZATION" == "true" ]]; then \
        echo "Running Ubuntu customization..."; \
        echo "Builder DNS configuration:" \
        cat /etc/resolv.conf \
        echo "Checking rootfs resolver:" \
        ls -l /work/rootfs/etc/resolv.conf || true \
        proot -R /work/rootfs \
            -b /etc/resolv.conf:/etc/resolv.conf \
            /usr/bin/env DEBIAN_FRONTEND=noninteractive \
            /bin/bash /opt/iso-customize/customize.sh; \
    elif [[ "$RUN_CUSTOMIZATION" != "false" ]]; then \
        echo "RUN_CUSTOMIZATION must be true or false." >&2; \
        exit 1; \
    fi; \
    \
    # Remove build scripts from the final Ubuntu filesystem.
    rm -rf /work/rootfs/opt/iso-customize; \
    \
    # --------------------------------------------------------
    # REBUILD SQUASHFS
    # --------------------------------------------------------
    \
    echo "Rebuilding Ubuntu SquashFS..."; \
    \
    mksquashfs /work/rootfs \
        /work/filesystem-custom.squashfs \
        -noappend \
        -comp xz; \
    \
    # --------------------------------------------------------
    # CREATE DOCKER ROOTFS ARCHIVE
    # --------------------------------------------------------
    \
    echo "Creating Docker root filesystem archive..."; \
    \
    tar --numeric-owner \
        -cpf /work/rootfs.tar \
        -C /work/rootfs .; \
    \
    # ========================================================
    # GRUB CUSTOMIZATION
    # ========================================================
    \
    echo "Preparing GRUB customization..."; \
    \
    test -f /work/grub-overlay/boot/grub/custom.cfg; \
    \
    # Extract the original GRUB configuration.
    xorriso -osirrox on \
        -indev /work/original.iso \
        -extract "$GRUB_CFG_PATH" \
        /work/grub.cfg; \
    \
    # Add custom.cfg loading without replacing original entries.
    if ! grep -q 'custom\.cfg' /work/grub.cfg; then \
        printf '\n%s\n' \
            '# Load additional custom GRUB entries.' \
            'if [ -f "$prefix/custom.cfg" ]; then' \
            '    source "$prefix/custom.cfg"' \
            'fi' \
            >> /work/grub.cfg; \
    fi; \
    \
    # --------------------------------------------------------
    # PREPARE XORRISO ARGUMENTS
    # --------------------------------------------------------
    \
    xorriso_args=( \
        xorriso \
        -indev /work/original.iso \
        -outdev /work/custom.iso \
    ); \
    \
    # Replace original SquashFS with customized SquashFS.
    xorriso_args+=( \
        -map \
        /work/filesystem-custom.squashfs \
        "$CASPER_SQUASHFS_PATH" \
    ); \
    \
    # Replace original GRUB configuration with patched version.
    xorriso_args+=( \
        -map \
        /work/grub.cfg \
        "$GRUB_CFG_PATH" \
    ); \
    \
    # --------------------------------------------------------
    # APPLY GRUB OVERLAY FILES
    # --------------------------------------------------------
    \
    mapfile -d '' overlay_files < <( \
        find /work/grub-overlay \
            -type f \
            ! -name '.keep' \
            -print0 \
    ); \
    \
    for overlay_file in "${overlay_files[@]}"; do \
        \
        # Convert local path to ISO path.
        iso_path="/${overlay_file#/work/grub-overlay/}"; \
        \
        # Do not overwrite the patched main GRUB configuration.
        if [[ "$iso_path" == "$GRUB_CFG_PATH" ]]; then \
            echo "Overlay must not replace main grub.cfg." >&2; \
            exit 1; \
        fi; \
        \
        # Add file to ISO.
        xorriso_args+=( \
            -map \
            "$overlay_file" \
            "$iso_path" \
        ); \
    done; \
    \
    # --------------------------------------------------------
    # PRESERVE ORIGINAL BOOT CONFIGURATION
    # --------------------------------------------------------
    \
    xorriso_args+=( \
        -boot_image any replay \
        -commit \
        -end \
    ); \
    \
    # --------------------------------------------------------
    # BUILD CUSTOM ISO
    # --------------------------------------------------------
    \
    echo "Building customized Ubuntu ISO..."; \
    \
    "${xorriso_args[@]}"; \
    \
    # --------------------------------------------------------
    # EXPORT ISO TO OUTPUT DIRECTORY
    # --------------------------------------------------------
    \
    mkdir -p /output; \
    cp /work/custom.iso /output/custom.iso; \
    \
    echo "ISO build completed."


    # Prepare Docker root filesystem.
    RUN mkdir -p /work/docker-rootfs && \
        tar --numeric-owner \
            --exclude='./proc' \
            --exclude='./sys' \
            --exclude='./dev' \
            --exclude='./run' \
            --exclude='./tmp' \
            --exclude='./etc/hosts' \
            --exclude='./etc/resolv.conf' \
            --exclude='./etc/hostname' \
            --exclude='./etc/mtab' \
            -cpf - -C /work/rootfs . \
            | tar -xpf - -C /work/docker-rootfs

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

WORKDIR /root

CMD ["/bin/bash"]
