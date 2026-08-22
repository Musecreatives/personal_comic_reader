# Builds the release web bundle and copies it to the Caddy host over
# Tailscale. Run from anywhere; paths are resolved relative to this script.
#
# Usage: powershell -File deploy/build.ps1
#
# Requires: flutter on PATH, an SSH key already authorized for
# server@100.108.109.63 (passwordless - this script does not prompt).

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RemoteHost = 'server@100.108.109.63'
$RemotePath = '/home/server/docker/caddy/sites/reader/'

Write-Host "Building release web bundle..." -ForegroundColor Cyan
Push-Location $RepoRoot
try {
    flutter build web --release --base-href /
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$BuildDir = Join-Path $RepoRoot 'build\web'
if (-not (Test-Path $BuildDir)) {
    throw "Build output not found at $BuildDir"
}

Write-Host "Copying build\web -> ${RemoteHost}:${RemotePath}" -ForegroundColor Cyan
# scp -r copies the *contents* of build\web when the source ends in \*.
scp -r "$BuildDir\*" "${RemoteHost}:${RemotePath}"
if ($LASTEXITCODE -ne 0) { throw "scp failed with exit code $LASTEXITCODE" }

Write-Host "Deployed. Verify at https://reader.shaddai.home" -ForegroundColor Green
