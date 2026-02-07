#!/bin/bash

set -e

echo "Building ziggrep (ReleaseSafe)..."
zig build -Doptimize=ReleaseSafe

INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

echo "Installing to $INSTALL_DIR..."
cp zig-out/bin/ziggrep "$INSTALL_DIR/ziggrep"

echo "Success!"
echo "Ensure $INSTALL_DIR is in your PATH."
echo "Verified installation:"
"$INSTALL_DIR/ziggrep" --help | head -n 1
