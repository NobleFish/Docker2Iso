#!/usr/bin/env bash
# customize.sh - Script to customize the Ubuntu ISO image.

set -Eeuo pipefail

SCRIPT_DIR="/opt/iso-customize"

echo "=================================="
echo " Starting Ubuntu Customization"
echo "=================================="

# Find scripts in numerical order.
shopt -s nullglob
scripts=("$SCRIPT_DIR"/[0-9][0-9]-*.sh)

# Execute every discovered script.
for script in "${scripts[@]}"; do

    echo
    echo "----------------------------------"
    echo "Executing: $(basename "$script")"
    echo "----------------------------------"

    /bin/bash "$script"

    echo "Completed: $(basename "$script")"

done

echo
echo "=================================="
echo " Ubuntu Customization Completed"
echo "=================================="
