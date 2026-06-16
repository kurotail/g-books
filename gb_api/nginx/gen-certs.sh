#!/usr/bin/env sh
# Generate a self-signed certificate for local/dev HTTPS.
# Run from anywhere: ./nginx/gen-certs.sh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)/certs"
mkdir -p "$DIR"

# Stop Git Bash/MSYS from rewriting the "/C=US/..." subject into a Windows path.
export MSYS_NO_PATHCONV=1

openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$DIR/server.key" \
    -out "$DIR/server.crt" \
    -days 365 \
    -subj "/C=US/ST=Dev/L=Dev/O=gb-api/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

echo "Self-signed cert written to $DIR/server.crt (valid 365 days)"
