# Create a new snapshot
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


