#!/bin/bash
# Works around a Docker/Tailscale boot race: AdGuard's compose file binds
# ports to the literal Tailscale IP (100.108.109.63), not 0.0.0.0. If
# Docker starts (and auto-restarts, per `restart: unless-stopped`) the
# adguardhome container before tailscaled has actually finished
# connecting and assigned that IP to tailscale0, the specific-IP bind
# fails - and Docker abandons publishing *all* of that container's ports,
# not just the one that failed. `docker restart` alone doesn't fix this;
# it reuses the network state from the original (failed) start. Only a
# full recreate forces Docker to redo the publish step.
#
# This script waits for the Tailscale IP to actually be present on
# tailscale0, then force-recreates the container so its ports are
# guaranteed to be freshly (and correctly) published. Installed as a
# systemd oneshot service (see adguard-fixup.service) that runs on every
# boot, after docker.service has already done its best-effort start.

set -euo pipefail

TARGET_IP="100.108.109.63"
TIMEOUT_SECONDS=90
ELAPSED=0

while ! ip addr show tailscale0 2>/dev/null | grep -q "$TARGET_IP"; do
  if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
    echo "Timed out after ${TIMEOUT_SECONDS}s waiting for Tailscale IP $TARGET_IP on tailscale0" >&2
    exit 1
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

echo "Tailscale IP $TARGET_IP confirmed on tailscale0 after ${ELAPSED}s - recreating adguardhome"
cd /home/server/docker/adguard
/usr/bin/docker compose up -d --force-recreate
