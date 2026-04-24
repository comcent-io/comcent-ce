#!/bin/bash

# Script to install the correct platform-specific Rollup binary
# This ensures the right binary is available for the current platform

set -e

echo "Detecting platform for Rollup binary installation..."

# Detect platform and architecture
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

echo "Platform: $PLATFORM"
echo "Architecture: $ARCH"

# Determine the correct package name
case "$PLATFORM" in
    "darwin")
        case "$ARCH" in
            "arm64"|"aarch64")
                PACKAGE="@rollup/rollup-darwin-arm64"
                ;;
            "x86_64")
                PACKAGE="@rollup/rollup-darwin-x64"
                ;;
            *)
                echo "Unsupported architecture for Darwin: $ARCH"
                exit 1
                ;;
        esac
        ;;
    "linux")
        case "$ARCH" in
            "x86_64")
                PACKAGE="@rollup/rollup-linux-x64-gnu"
                ;;
            "aarch64"|"arm64")
                PACKAGE="@rollup/rollup-linux-arm64-gnu"
                ;;
            *)
                echo "Unsupported architecture for Linux: $ARCH"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

echo "Installing $PACKAGE..."

# Check if the package is already installed
if npm list "$PACKAGE" >/dev/null 2>&1; then
    echo "$PACKAGE is already installed"
else
    # Install the platform-specific package
    npm install "$PACKAGE"
    echo "Successfully installed $PACKAGE for $PLATFORM/$ARCH"
fi
