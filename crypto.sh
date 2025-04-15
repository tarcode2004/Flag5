#!/bin/bash
set -euo pipefail
# This script attempts to fix the "ModuleNotFoundError: No module named 'Crypto'"
# for the custom Python 3.9 installation by cleaning up any previous traces
# of pycryptodome and performing a verbose reinstall.

# --- Configuration ---
PYTHON_INSTALL_DIR="/opt/python-custom"
PYTHON_VERSION_SHORT="3.9"
PIP_EXEC="$PYTHON_INSTALL_DIR/bin/pip$PYTHON_VERSION_SHORT"
SITE_PACKAGES="$PYTHON_INSTALL_DIR/lib/python$PYTHON_VERSION_SHORT/site-packages"
PACKAGE_NAME="pycryptodome"
MODULE_DIR_NAME="Crypto" # The directory created by the package
SERVICE_NAME="rc4-line-server"
# --- End Configuration ---

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root or using sudo." >&2
  exit 1
fi

echo "This script will attempt to fix the pycryptodome installation for Python at $PYTHON_INSTALL_DIR"
echo "Target site-packages: $SITE_PACKAGES"
read -p "Press Enter to continue, or Ctrl+C to cancel..."

# --- Step 1: Clean up previous installation traces ---
echo
echo "--- 1. Cleaning up previous installation traces ---"
echo "Removing $SITE_PACKAGES/$MODULE_DIR_NAME ..."
rm -rf "$SITE_PACKAGES/$MODULE_DIR_NAME"
echo "Removing $SITE_PACKAGES/${PACKAGE_NAME}*.dist-info ..."
rm -rf "$SITE_PACKAGES/${PACKAGE_NAME}"*.dist-info

echo "Verification of cleanup (should not list Crypto or pycryptodome):"
ls -l "$SITE_PACKAGES/" | grep -E "$MODULE_DIR_NAME|${PACKAGE_NAME}" || true # Use || true to prevent exit if grep finds nothing
echo "Cleanup attempt complete."

# --- Step 2: Attempt verbose reinstall ---
echo
echo "--- 2. Attempting verbose reinstall of $PACKAGE_NAME ---"
echo "Running: $PIP_EXEC install -vvv --no-cache-dir $PACKAGE_NAME"
echo "Please watch the following output carefully for any errors:"
echo "------------------------- PIP OUTPUT START -------------------------"
# Run pip install and capture its exit code
"$PIP_EXEC" install -vvv --no-cache-dir "$PACKAGE_NAME"
PIP_EXIT_CODE=$? # Capture exit code immediately
echo "-------------------------- PIP OUTPUT END --------------------------"


# --- Step 3: Verify installation ---
echo
echo "--- 3. Verifying installation ---"
# Check pip exit code first
if [ $PIP_EXIT_CODE -ne 0 ]; then
    echo "ERROR: pip install command failed with exit code $PIP_EXIT_CODE." >&2
    echo "Please review the verbose output above for specific errors (permissions, network, build errors etc.)." >&2
    exit 1
fi
echo "pip install command finished with exit code 0 (Success)."

# Now check if the directory actually exists
echo "Checking for existence of: $SITE_PACKAGES/$MODULE_DIR_NAME"
if ls -ld "$SITE_PACKAGES/$MODULE_DIR_NAME" > /dev/null 2>&1; then
    echo "SUCCESS: The $MODULE_DIR_NAME directory now exists in site-packages."
    echo "Checking contents of $MODULE_DIR_NAME/Cipher/:"
    ls -l "$SITE_PACKAGES/$MODULE_DIR_NAME/Cipher/"
else
    echo "ERROR: The $MODULE_DIR_NAME directory STILL does NOT exist in site-packages after install attempt." >&2
    echo "This indicates the pip install failed to actually place the files, despite exiting with code 0." >&2
    echo "Please review the verbose output from the pip install command VERY carefully for subtle errors or warnings." >&2
    exit 1
fi

# --- Step 4: Optional Checks (Informational) ---
echo
echo "--- 4. Optional Checks (Informational) ---"
echo "Recent dmesg output (last 10 lines):"
dmesg | tail -n 10 || echo "Could not run dmesg."
echo "Filesystem disk space for $SITE_PACKAGES:"
df -h "$SITE_PACKAGES" || echo "Could not run df."

# --- Step 5: Restarting and checking service ---
echo
echo "--- 5. Restarting and checking service $SERVICE_NAME ---"
echo "Restarting service..."
systemctl restart "$SERVICE_NAME"
sleep 2 # Give service time to potentially fail/start
echo "Checking service status:"
systemctl status "$SERVICE_NAME" --no-pager -l || echo "Service status check failed." # Use || true if status command might fail when service is bad

echo
echo "Script finished."
echo "Check the service status output above. If it's active (running), the issue is likely resolved."
echo "If it failed again, check the journal: sudo journalctl -u $SERVICE_NAME -n 50 --no-pager"

exit 0