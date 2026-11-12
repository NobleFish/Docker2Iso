
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
COPY build/validate-iso-paths.sh /work/build/validate-iso-paths.sh

# Verify and extract the source ISO in a cached layer that does not depend on
# the customization scripts or GRUB overlay.
RUN set -euo pipefail; \
    /bin/bash /work/build/validate-iso-paths.sh \
        "$CASPER_SQUASHFS_PATH" "$GRUB_CFG_PATH"; \
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
COPY build/ /work/build/

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
    /bin/bash /work/build/rebuild-squashfs.sh \
        /work/rootfs \
        "$SQUASHFS_COMPRESSION" \
        /work/filesystem.size \
        /work/filesystem.manifest \
        /work/filesystem-custom.squashfs \
        /work/scripts/generate-filesystem-manifest.sh

# Keep the large root filesystem build cached independently of GRUB edits.
COPY grub-overlay/ /work/grub-overlay/

RUN set -euo pipefail; \
    /bin/bash /work/build/rebuild-iso.sh \
        /work/original.iso \
        /work/filesystem-custom.squashfs \
        /work/filesystem.size \
        /work/filesystem.manifest \
        "$CASPER_SQUASHFS_PATH" \
        "$GRUB_CFG_PATH" \
        /work/grub-overlay \
        /work/custom.iso; \
    /bin/bash /work/build/verify-iso.sh \
        /work/custom.iso \
        /work/filesystem-custom.squashfs \
        "$CASPER_SQUASHFS_PATH" \
        /work/filesystem.size \
        /work/filesystem.manifest \
        "$GRUB_CFG_PATH" \
        /work/grub.cfg \
        /work/md5sum.updated \
        /work/grub-overlay \
        /work/iso-verify; \
    mkdir -p /output; \
    cp /work/custom.iso /output/custom.iso
# Prepare a container-friendly root filesystem after creating the ISO.
RUN /bin/bash /work/build/export-docker-rootfs.sh /work/rootfs /work/docker-rootfs

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
