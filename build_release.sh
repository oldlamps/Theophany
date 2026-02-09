#!/bin/bash
set -e

# Build the release binary
echo "Building release binary..."
cargo build --release

# Create dist directory
echo "Preparing dist directory..."
rm -rf dist
mkdir -p dist

# Copy binary to dist
BINARY="target/release/theophany"
if [ -f "$BINARY" ]; then
    cp "$BINARY" dist/
    
    # Strip binary to reduce size
    if command -v strip >/dev/null 2>&1; then
        echo "Stripping binary..."
        strip dist/theophany
    fi
    
    echo "Release build complete! The single binary is located in the dist/ folder."
else
    echo "Error: Binary not found at $BINARY"
    exit 1
fi
