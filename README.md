# Docker2Iso

Docker2Iso customizes the supplied Ubuntu 24.04.5 Server AMD64 ISO and can also
export the resulting filesystem as a Docker image.

## Build commands

- `make iso` creates `iso-output/custom.iso`.
- `make ubuntu` builds `custom-ubuntu:latest` and uses Docker layer caching.
- `make ubuntu-clean` rebuilds the image without using the build cache.
- `make test-image` builds the image and runs the customization checks.
- `make clean` removes the ISO output directory.

Set `IMAGE_TAG` or `ISO_OUTPUT_DIR` to override the default image tag or ISO
output directory.

## Customization and overlays

Scripts in `scripts/` run in numeric filename order. Files placed under
`grub-overlay/` are copied to the ISO at the same relative paths. For example,
`grub-overlay/boot/grub/custom.cfg` becomes `/boot/grub/custom.cfg` on the ISO.
Overlays must contain regular files; symbolic links and build-managed ISO paths
are rejected.

Set the Docker build argument `DEBUG_CUSTOMIZATION=true` to enable shell tracing
in the customization scripts.

## SSH and account behavior

The `isoadmin` account is created with a locked password. Provision and unlock
the account through a trusted first-boot process before allowing SSH access;
the project does not bake in a password or public key. SSH host keys are
removed from the generated filesystem and created when `ssh.service` first
starts on a systemd boot, so multiple installations do not share one SSH
identity.

The Docker image is a root filesystem, not a virtual machine. It does not start
systemd or SSH automatically. If you run `sshd` in a container, provision a
unique host key and an authentication method for that container first.

`make test-image` verifies filesystem contents and SSH configuration. ISO file
integrity is checked during the build, but BIOS and UEFI boot testing requires
an external VM test environment.
