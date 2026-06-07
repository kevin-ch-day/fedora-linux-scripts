#!/bin/bash
# DEPRECATED — uses system-wide sudo pip3 (not recommended on Fedora).
# Prefer android/android_dev_core_setup.sh and user-scoped pip installs.
# Moved to legacy/ during repo cleanup (2026-06).

echo "[DEPRECATED] Disabled. Use: ../android/android_dev_core_setup.sh" >&2
exit 1

# Install Development Tools and Libraries
echo "Installing Development Tools and Libraries..."
sudo dnf groupinstall "Development Tools" "Development Libraries" -y

# Verify Python installation
echo "Verifying Python installation..."
python3 --version

# Install pip for Python 3
echo "Installing pip for Python 3..."
sudo dnf install python3-pip -y

# Install Python libraries for data mining
echo "Installing Python libraries for data mining..."
sudo pip3 install numpy pandas scipy scikit-learn matplotlib seaborn

echo "Development environment setup complete!"
