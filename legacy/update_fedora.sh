#!/bin/bash
# DEPRECATED — use ../system/system_update.sh instead.
# Moved to legacy/ during repo cleanup (2026-06).

echo "[DEPRECATED] Disabled. Use: ../system/system_update.sh" >&2
exit 1

# Update the system
echo "Updating the system..."
sudo dnf update -y

# Upgrade the system
echo "Upgrading the system..."
sudo dnf upgrade -y

echo "Update and upgrade complete!"
