#!/usr/bin/env bash
# Checks that the mergerfs union at /mnt/media-pool is actually mounted -
# it silently unmounted for two days (2026-08-26 to 2026-08-28) with
# nothing noticing, during which Komga/Kavita/CLU kept writing to a fresh
# empty directory on the root disk instead of the real pool. Run on a
# timer (see mergerfs-watchdog.timer) rather than only at boot, since this
# failure happened mid-session, not on startup.
#
# On its own this only mounts /mnt/media-pool - it does NOT force-recreate
# containers or touch branch drives, since those actions carry their own
# risk (see ROADMAP.md's mergerfs incident writeup) and should stay a
# manual, reviewed step even when this alerts.

set -u

MOUNT_POINT="/mnt/media-pool"
NTFY_URL="http://127.0.0.1:4005/homelab-alerts"

notify() {
  local title="$1" message="$2" priority="${3:-default}"
  curl -s \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -d "$message" \
    "$NTFY_URL" >/dev/null 2>&1 || true
}

if mountpoint -q "$MOUNT_POINT"; then
  exit 0
fi

echo "$(date -Iseconds): $MOUNT_POINT is not mounted - attempting to remount"

if mount "$MOUNT_POINT" 2>&1; then
  echo "$(date -Iseconds): remount succeeded"
  notify "mergerfs remounted" \
    "$MOUNT_POINT was found unmounted and has been remounted automatically. Worth checking why it dropped - restart a container if anything looks stale (Suwayomi, Komga, Kavita, Kapowarr, CLU, Komf all live on this pool)." \
    "high"
else
  echo "$(date -Iseconds): remount FAILED - needs manual attention"
  notify "mergerfs is down - remount failed" \
    "$MOUNT_POINT is unmounted and the automatic remount failed. Check that hdd1tb, hdd1tb2, and external are all still mounted (mount | grep -E 'hdd1tb|external'), then mount $MOUNT_POINT manually. Comics-manga containers may be writing to the wrong place until this is fixed." \
    "urgent"
fi
