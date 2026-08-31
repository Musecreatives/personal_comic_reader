#!/usr/bin/env bash
# Checks that the mergerfs union at /mnt/media-pool is actually mounted AND
# actually responding - it silently unmounted for two days (2026-08-26 to
# 2026-08-28) with nothing noticing, during which Komga/Kavita/CLU kept
# writing to a fresh empty directory on the root disk instead of the real
# pool. Run on a timer (see mergerfs-watchdog.timer) rather than only at
# boot, since this failure happened mid-session, not on startup.
#
# 2026-08-29 addendum: a *second*, different failure mode showed up - one
# branch drive (hdd1tb) went into ext4 emergency_ro, which left mergerfs
# still technically mounted (present in /proc/mounts) but every real I/O
# call through it hung for tens of minutes. A bare `mountpoint -q` check
# doesn't distinguish "mounted and healthy" from "mounted but wedged" - it
# just blocks until the wedge clears, so this watchdog silently took 21,
# then 42, then 51 minutes per run and never alerted, because from its
# point of view the mount was never actually "down". Every check below is
# now wrapped in `timeout` so a wedged mount is treated as its own
# distinct, alertable failure instead of making the watchdog hang too.
#
# On its own this only mounts /mnt/media-pool - it does NOT force-recreate
# containers, remount a wedged branch, or touch branch drives, since those
# actions carry their own risk (see ROADMAP.md's mergerfs incident
# writeup) and should stay a manual, reviewed step even when this alerts.

set -u

MOUNT_POINT="/mnt/media-pool"
NTFY_URL="http://127.0.0.1:4005/homelab-alerts"
CHECK_TIMEOUT=10

notify() {
  local title="$1" message="$2" priority="${3:-default}"
  curl -s \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -d "$message" \
    "$NTFY_URL" >/dev/null 2>&1 || true
}

timeout "$CHECK_TIMEOUT" mountpoint -q "$MOUNT_POINT"
status=$?

if [ "$status" -eq 0 ]; then
  exit 0
fi

if [ "$status" -eq 124 ]; then
  echo "$(date -Iseconds): $MOUNT_POINT check timed out after ${CHECK_TIMEOUT}s - mount is present but wedged"
  notify "mergerfs is wedged - not just unmounted" \
    "$MOUNT_POINT is still listed as mounted but a plain mountpoint check took over ${CHECK_TIMEOUT}s and was killed. This usually means one branch drive (hdd1tb, hdd1tb2, external, or flash16gb) went read-only or stopped responding at the hardware level - remounting the union won't fix that. Check 'grep media-pool /proc/mounts' and each branch's mount flags (look for emergency_ro), then the physical/USB connection. Comics-manga containers may hang on any write until this is fixed by hand." \
    "urgent"
  exit 0
fi

echo "$(date -Iseconds): $MOUNT_POINT is not mounted - attempting to remount"

if timeout "$CHECK_TIMEOUT" mount "$MOUNT_POINT" 2>&1; then
  echo "$(date -Iseconds): remount succeeded"
  notify "mergerfs remounted" \
    "$MOUNT_POINT was found unmounted and has been remounted automatically. Worth checking why it dropped - restart a container if anything looks stale (Suwayomi, Komga, Kavita, Kapowarr, CLU, Komf all live on this pool)." \
    "high"
else
  echo "$(date -Iseconds): remount FAILED or timed out - needs manual attention"
  notify "mergerfs is down - remount failed" \
    "$MOUNT_POINT is unmounted and the automatic remount failed or timed out. Check that hdd1tb, hdd1tb2, and external are all still mounted (mount | grep -E 'hdd1tb|external'), then mount $MOUNT_POINT manually. Comics-manga containers may be writing to the wrong place until this is fixed." \
    "urgent"
fi
