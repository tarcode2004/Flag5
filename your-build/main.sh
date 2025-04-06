#!/bin/bash
set -euo pipefail

# Directories for step scripts and flag files.
STEP_DIR="./steps"
FLAG_DIR="./.steps_done"

# Show usage if requested.
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [--reset]"
  echo "  --reset  Reset build state and run all steps from scratch."
  exit 0
fi

# If reset requested, clear flag files.
if [[ "${1:-}" == "--reset" ]]; then
  echo "Resetting build state..."
  rm -rf "$FLAG_DIR"
fi

mkdir -p "$FLAG_DIR"

# Run each step in sorted order.
for script in $(ls -1 $STEP_DIR/*.sh | sort); do
    script_name=$(basename "$script")
    flag_file="$FLAG_DIR/${script_name}.done"
    if [[ -f "$flag_file" ]]; then
        echo "[SKIP] $script_name already completed."
    else
        echo "[RUN] $script_name..."
        bash "$script"
        touch "$flag_file"
    fi
done

echo "Build process complete!"
