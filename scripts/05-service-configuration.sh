
#!/usr/bin/env bash

set -Eeuo pipefail

echo "Configuring SSH service..."

# Create SSH configuration directory.
mkdir -p /etc/ssh/sshd_config.d

# Add custom SSH settings.
cat > /etc/ssh/sshd_config.d/99-custom.conf <<'EOF'
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Validate SSH configuration.
sshd -t

# Enable SSH for a system booted with systemd.
# --root=/ performs offline configuration.
systemctl --root=/ enable ssh.service

echo "SSH service configuration completed."
