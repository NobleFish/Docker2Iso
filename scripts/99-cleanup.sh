
#!/usr/bin/env bash

set -Eeuo pipefail

echo "Cleaning Ubuntu filesystem..."

apt-get clean

rm -rf /var/lib/apt/lists/*

echo "Cleanup completed."
