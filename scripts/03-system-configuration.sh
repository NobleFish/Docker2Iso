#!/usr/bin/env bash
# 03-system-configuration.sh - Script to configure system settings in the Ubuntu filesystem.

set -Eeuo pipefail

echo "Configuring system settings..."

# --------------------------------
# Hostname
# --------------------------------

echo "custom-ubuntu" > /etc/hostname

# --------------------------------
# Timezone
# --------------------------------

ln -snf /usr/share/zoneinfo/Etc/UTC /etc/localtime

echo "Etc/UTC" > /etc/timezone

# --------------------------------
# Custom MOTD
# --------------------------------

cat > /etc/motd <<'EOF'
==================================
       CUSTOM UBUNTU SERVER
==================================

This system was customized during
the ISO build process.

==================================
EOF

# --------------------------------
# Sysctl configuration
# --------------------------------

cat > /etc/sysctl.d/99-custom.conf <<'EOF'
# Disable IPv4 forwarding by default.
net.ipv4.ip_forward = 0

# Disable IPv6 forwarding by default.
net.ipv6.conf.all.forwarding = 0
EOF

echo "System configuration completed."
