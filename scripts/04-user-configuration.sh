
#!/usr/bin/env bash

set -Eeuo pipefail

echo "Configuring users..."

USERNAME="isoadmin"

# Create the user if it does not exist.
if ! id "$USERNAME" >/dev/null 2>&1; then

    useradd \
        --create-home \
        --shell /bin/bash \
        --groups sudo \
        "$USERNAME"

else

    usermod -aG sudo "$USERNAME"

fi

# Create a custom directory.
install -d \
    -o "$USERNAME" \
    -g "$USERNAME" \
    /home/"$USERNAME"/custom

echo "User configuration completed."
