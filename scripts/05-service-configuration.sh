#!/usr/bin/env bash
# 05-service-configuration.sh - Script to configure services in the Ubuntu filesystem.

set -Eeuo pipefail

echo "Configuring SSH service..."

# Create SSH configuration directory.
mkdir -p /etc/ssh/sshd_config.d

# Add custom SSH settings.
cat > /etc/ssh/sshd_config.d/99-custom.conf <<'EOF'
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Generate host keys on first boot so reusable ISO builds do not distribute
# a shared SSH server identity.
install -d -m 0755 /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/10-generate-host-keys.conf <<'EOF'
[Service]
ExecStartPre=
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStartPre=/usr/sbin/sshd -t
EOF

# Validate SSH configuration.
install -d -m 0755 /run/sshd
sshd -t
sshd -T | grep -Fx 'clientaliveinterval 300'
sshd -T | grep -Fx 'clientalivecountmax 2'

# Enable SSH for a system booted with systemd.
# --root=/ performs offline configuration.
systemctl --root=/ enable ssh.service

echo "SSH service configuration completed."
