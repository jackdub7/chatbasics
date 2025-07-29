�#!/bin/bash

LOGFILE="/var/log/snapshot.log"
SNAP_BASE="/srv/snapshots"
TIMESTAMP=$(date +%Y%m%d-%H%M)
SNAP_NAME="files-snap-${TIMESTAMP}"
SNAP_MOUNT="${SNAP_BASE}/${TIMESTAMP}"
USAGE_FILE="/var/log/last_snapshot_usage.txt"
MAX_SNAPS=6

echo "[$(date)] Starting snapshot process." | tee -a "$LOGFILE"

# Check memory (skip if below 400MB free)
FREE_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
if [ "$FREE_MB" -lt 400 ]; then
  echo "[$(date)] Not enough free memory (${FREE_MB}MB) — skipping snapshot." | tee -a "$LOGFILE"
  exit 1
fi

# Clean up old snapshots if more than MAX_SNAPS exist
SNAPS=$(lvs --noheadings -o lv_name | grep files-snap- | sort)
COUNT=$(echo "$SNAPS" | wc -l)
if [ "$COUNT" -gt "$MAX_SNAPS" ]; then
  DELETE=$(echo "$SNAPS" | head -n $(($COUNT - $MAX_SNAPS)))
  for snap in $DELETE; do
    MOUNT_PATH="${SNAP_BASE}/${snap#files-snap-}"
    echo "[$(date)] Deleting old snapshot: $snap" | tee -a "$LOGFILE"
    umount "$MOUNT_PATH" 2>/dev/null
    lvremove -f "/dev/ubuntu_jrcb--files/$snap" >> "$LOGFILE" 2>&1
    rm -rf "$MOUNT_PATH"
  done
fi

# Create new snapshot
if lvcreate -L 1G -s -n "$SNAP_NAME" /dev/ubuntu_jrcb-files/files >> "$LOGFILE" 2>&1; then
  mkdir -p "$SNAP_MOUNT"

  # Apply ACLs before mounting (for snapshot access)
  for group in \
    law-administrators law-library law-staff law-religion law-pr law-faculty \
    law-extrel law-cso law-admiss law-accounting law-lib-circ law-lib-circ-restricted \
    law-lib-tech-serv; do
    setfacl -m g:$group:r-x "$SNAP_MOUNT"
  done

  if mount -o ro,nouuid /dev/ubuntu_jrcb-files/"$SNAP_NAME" "$SNAP_MOUNT" >> "$LOGFILE" 2>&1; then
    echo "[$(date)] Mounted $SNAP_NAME at $SNAP_MOUNT" | tee -a "$LOGFILE"

    # Check usage delta
    CURRENT_USAGE=$(du -s /srv/files | awk '{print $1}')
    echo "[$(date)] Current usage: $CURRENT_USAGE KB" | tee -a "$LOGFILE"

    if [[ -f "$USAGE_FILE" ]]; then
      LAST_USAGE=$(cat "$USAGE_FILE")
      echo "[$(date)] Last usage: $LAST_USAGE KB" | tee -a "$LOGFILE"
    else
      LAST_USAGE=0
    fi

    echo "$CURRENT_USAGE" > "$USAGE_FILE"
    CHANGE=$((CURRENT_USAGE - LAST_USAGE))

    if [[ "$CHANGE" -eq 0 ]]; then
      echo "[$(date)] No change detected. Deleting snapshot." | tee -a "$LOGFILE"
      umount "$SNAP_MOUNT"
      lvremove -f /dev/ubuntu_jrcb-files/"$SNAP_NAME" >> "$LOGFILE" 2>&1
      rm -rf "$SNAP_MOUNT"
    else
      echo "[$(date)] Change detected ($CHANGE KB). Snapshot retained." | tee -a "$LOGFILE"
      systemctl restart smbd
    fi

  else
    echo "[$(date)] ERROR: Failed to mount snapshot $SNAP_NAME" | tee -a "$LOGFILE"
    lvremove -f /dev/ubuntu_jrcb-files/"$SNAP_NAME"
    rm -rf "$SNAP_MOUNT"
  fi
else
  echo "[$(date)] ERROR: Failed to create snapshot $SNAP_NAME" | tee -a "$LOGFILE"
fi


