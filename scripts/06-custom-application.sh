
#!/usr/bin/env bash

set -Eeuo pipefail

echo "Installing custom application..."

mkdir -p /usr/local/bin

cat > /usr/local/bin/hello-custom <<'EOF'
#!/usr/bin/env bash

echo "Hello from my customized Ubuntu system!"
echo "This application was installed during the ISO build."
EOF

chmod 0755 /usr/local/bin/hello-custom

echo "Custom application installed."
