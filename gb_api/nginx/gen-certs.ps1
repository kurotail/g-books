# Generate a self-signed certificate for local/dev HTTPS.
# Run from anywhere: powershell -ExecutionPolicy Bypass -File .\nginx\gen-certs.ps1
$ErrorActionPreference = "Stop"

$dir = Join-Path $PSScriptRoot "certs"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

openssl req -x509 -nodes -newkey rsa:2048 `
    -keyout (Join-Path $dir "server.key") `
    -out (Join-Path $dir "server.crt") `
    -days 365 `
    -subj "/C=US/ST=Dev/L=Dev/O=gb-api/CN=localhost" `
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

Write-Host "Self-signed cert written to $dir\server.crt (valid 365 days)"
