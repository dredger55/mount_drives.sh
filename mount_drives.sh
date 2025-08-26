#!/bin/bash

# Exit on any error
set -e

# User-configurable variables
TARGET_USER="${TARGET_USER:-$USER}"  # Default to current user if not set
MOUNT_BASE="${MOUNT_BASE:-/mnt}"     # Default mount base directory

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# Check for required tools (ntfs-3g and exfatprogs for NTFS/exFAT support)
if ! command -v ntfs-3g >/dev/null 2>&1; then
    echo "Installing ntfs-3g for NTFS support..."
    apt-get update && apt-get install -y ntfs-3g
fi
if ! command -v mount.exfat >/dev/null 2>&1; then
    echo "Installing exfatprogs for exFAT support..."
    apt-get update && apt-get install -y exfatprogs
fi

# Get UID and GID for the target user
USER_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")
USER_GID=$(id -g "$TARGET_USER" 2>/dev/null || echo "1000")
if [ -z "$USER_UID" ] || [ -z "$USER_GID" ]; then
    echo "Warning: User '$TARGET_USER' not found, using default UID/GID 1000." >&2
fi
echo "Using UID=$USER_UID and GID=$USER_GID for user $TARGET_USER."

# Backup fstab
FSTAB="/etc/fstab"
FSTAB_BACKUP="/etc/fstab.bak.$(date +%F_%H-%M-%S)"
echo "Backing up $FSTAB to $FSTAB_BACKUP..."
cp "$FSTAB" "$FSTAB_BACKUP"

# Directory for mount points
mkdir -p "$MOUNT_BASE"

# Track if any drives were processed
PROCESSED=0

# Log blkid output for debugging
echo "Running blkid to detect drives..."
blkid_output=$(blkid)
echo "$blkid_output"

# Get list of all drives with valid filesystems
DRIVES=$(blkid | grep -E 'TYPE="[^"]+"' | awk '{print $1}' | sed 's/:$//')

if [ -z "$DRIVES" ]; then
    echo "No formatted drives found."
    echo "Possible reasons:"
    echo "- Drives may not be formatted. Run 'sudo mkfs.ext4 /dev/sdXn' to format (WARNING: erases data)."
    echo "- Drives may be part of RAID or LVM. Check with 'sudo mdadm --detail /dev/md*' or 'sudo lvs'."
    echo "Run 'sudo blkid' and 'sudo fdisk -l' for more details."
    exit 0
fi

# Process each drive
while read -r DEVICE; do
    # Skip loop devices
    if [[ "$DEVICE" == /dev/loop* ]]; then
        echo "Skipping $DEVICE (loop device)."
        continue
    fi

    # Check partition size to skip small reserved partitions (<1GB)
    SIZE=$(lsblk -b -n -o SIZE "$DEVICE" 2>/dev/null | head -1)
    if [ -z "$SIZE" ] || [ "$SIZE" -lt 1073741824 ]; then
        echo "Skipping $DEVICE (size $((SIZE / 1024 / 1024))M or not a block device)."
        continue
    fi

    # Extract UUID, TYPE, and LABEL from blkid for this device
    LINE=$(blkid "$DEVICE")
    UUID=$(echo "$LINE" | grep -oP 'UUID="\K[^"]+' | head -1 || true)
    FSTYPE=$(echo "$LINE" | grep -oP 'TYPE="\K[^"]+' || true)
    LABEL=$(echo "$LINE" | grep -oP 'LABEL="\K[^"]+' | head -1 || true)

    # Skip if no UUID or TYPE
    if [ -z "$UUID" ] || [ -z "$FSTYPE" ]; then
        echo "Skipping $DEVICE (no UUID or filesystem type). Run 'sudo mkfs.ext4 $DEVICE' to format (WARNING: erases data)."
        continue
    fi

    # Determine mount point name
    if [ -n "$LABEL" ]; then
        # Use label if available, sanitize to remove spaces and special chars
        MOUNT_NAME=$(echo "$LABEL" | tr ' ' '_' | tr -dc '[:alnum:]_-')
    else
        # Fallback to device name (e.g., sdb2)
        MOUNT_NAME=$(basename "$DEVICE" | tr -dc '[:alnum:]_-')
    fi

    MOUNT_POINT="$MOUNT_BASE/$MOUNT_NAME"
    echo "Processing $DEVICE (UUID=$UUID, TYPE=$FSTYPE, LABEL=`\(LABEL, SIZE=\)`((SIZE / 1024 / 1024 / 1024))G)..."

    # Remove existing empty mount point directory if it exists
    if [ -d "$MOUNT_POINT" ] && ! mountpoint -q "$MOUNT_POINT"; then
        rmdir "$MOUNT_POINT" 2>/dev/null || true
    fi

    # Ensure mount point is unique by appending a number if needed
    COUNTER=1
    ORIG_MOUNT_POINT="$MOUNT_POINT"
    while [ -d "$MOUNT_POINT" ] && ! mountpoint -q "$MOUNT_POINT"; do
        MOUNT_POINT="$ORIG_MOUNT_POINT-$COUNTER"
        COUNTER=$((COUNTER + 1))
    done
    echo "Using mount point $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"

    # Check if device is already in fstab
    if grep -q "$UUID" "$FSTAB"; then
        echo "$DEVICE (UUID=$UUID) already in $FSTAB, skipping."
        # Mark as processed if mounted at the correct point
        CURRENT_MOUNT=$(lsblk -n -o MOUNTPOINT "$DEVICE" 2>/dev/null)
        if [ "$CURRENT_MOUNT" = "$MOUNT_POINT" ]; then
            PROCESSED=1
        fi
        rmdir "$MOUNT_POINT" 2>/dev/null || true
        continue
    fi

    # Set mount options (NTFS/exFAT need specific options)
    MOUNT_OPTIONS="defaults,nofail"
    if [ "$FSTYPE" = "ntfs" ] || [ "$FSTYPE" = "exfat" ]; then
        MOUNT_OPTIONS="uid=$USER_UID,gid=$USER_GID,umask=000,nofail"
    fi

    # Check if already mounted
    CURRENT_MOUNT=$(lsblk -n -o MOUNTPOINT "$DEVICE" 2>/dev/null)
    if [ -n "$CURRENT_MOUNT" ]; then
        echo "$DEVICE is already mounted at $CURRENT_MOUNT."
        if [ "$CURRENT_MOUNT" != "$MOUNT_POINT" ]; then
            echo "Remounting $DEVICE to $MOUNT_POINT..."
            umount "$DEVICE" 2>/dev/null || true
            mkdir -p "$MOUNT_POINT"
            if mount -t "$FSTYPE" -o "$MOUNT_OPTIONS" "$DEVICE" "$MOUNT_POINT"; then
                echo "$DEVICE successfully remounted to $MOUNT_POINT."
                PROCESSED=1
            else
                echo "Failed to remount $DEVICE to $MOUNT_POINT. Check errors." >&2
                rmdir "$MOUNT_POINT" 2>/dev/null || true
                continue
            fi
        else
            echo "$DEVICE is already correctly mounted at $MOUNT_POINT."
            PROCESSED=1
        fi
    else
        # Mount the drive
        echo "Mounting $DEVICE to $MOUNT_POINT..."
        if mount -t "$FSTYPE" -o "$MOUNT_OPTIONS" "$DEVICE" "$MOUNT_POINT"; then
            echo "$DEVICE successfully mounted to $MOUNT_POINT."
            PROCESSED=1
        else
            echo "Failed to mount $DEVICE to $MOUNT_POINT. Check errors." >&2
            rmdir "$MOUNT_POINT" 2>/dev/null || true
            continue
        fi
    fi

    # Add to fstab
    echo "Adding $DEVICE to $FSTAB..."
    echo "UUID=$UUID $MOUNT_POINT $FSTYPE $MOUNT_OPTIONS 0 2" >> "$FSTAB"
done <<< "$DRIVES"

# Reload systemd to recognize fstab changes
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Test fstab
echo "Testing $FSTAB configuration..."
if mount -a; then
    echo "All drives mounted successfully. Updated $FSTAB."
    echo "Run 'df -h' to verify mounted drives."
else
    echo "Error in $FSTAB configuration. Restoring backup..." >&2
    cp "$FSTAB_BACKUP" "$FSTAB"
    echo "Restored $FSTAB from $FSTAB_BACKUP. Check for errors." >&2
    exit 1
fi

# Set permissions for all mounted drives in $MOUNT_BASE (skip chown/chmod for NTFS/exFAT)
echo "Setting permissions on mount points..."
PERMISSION_SET=0
for MP in "$MOUNT_BASE"/*; do
    if [ -d "$MP" ] && mountpoint -q "$MP"; then
        # Check if the mount is read-only
        if mount | grep "$MP" | grep -q "ro,"; then
            echo "Warning: $MP is mounted read-only. Attempting ntfsfix if NTFS..." >&2
            DEVICE=$(lsblk -n -o KNAME,MOUNTPOINT | grep "`\(MP\)`" | awk '{print "/dev/"$1}')
            FSTYPE=$(blkid -s TYPE -o value "$DEVICE")
            if [ "$FSTYPE" = "ntfs" ]; then
                umount "$MP" 2>/dev/null || true
                ntfsfix "$DEVICE" || echo "Failed to run ntfsfix on $DEVICE. Run 'sudo ntfsfix $DEVICE' manually." >&2
                mount -t "$FSTYPE" -o "uid=$USER_UID,gid=$USER_GID,umask=000,nofail" "$DEVICE" "$MP" || echo "Failed to remount $MP. Check errors." >&2
            fi
        fi
        # Get filesystem type for this mount point
        DEVICE=$(lsblk -n -o KNAME,MOUNTPOINT | grep "`\(MP\)`" | awk '{print "/dev/"$1}')
        FSTYPE=$(blkid -s TYPE -o value "$DEVICE")
        UUID=$(blkid -s UUID -o value "$DEVICE")
        # Only apply chown/chmod for ext4 (NTFS/exFAT use mount options)
        if [ "$FSTYPE" = "ext4" ]; then
            if chown "$TARGET_USER:$TARGET_USER" "$MP"; then
                echo "Set ownership on $MP"
            else
                echo "Failed to set ownership on $MP" >&2
            fi
            if chmod 775 "$MP"; then
                echo "Set permissions on $MP"
                PERMISSION_SET=1
            else
                echo "Failed to set permissions on $MP" >&2
            fi
        else
            echo "Skipping chown/chmod for $MP ($FSTYPE filesystem, access controlled by mount options)"
            PERMISSION_SET=1
        fi
        # Verify read-write access by attempting to create a test file
        if su - "$TARGET_USER" -c "touch '$MP/.testfile' 2>/dev/null"; then
            echo "$MP is writable by user $TARGET_USER"
            rm -f "$MP/.testfile"
        else
            echo "Warning: $MP is not writable by user $TARGET_USER. Attempting fallback mount options for exFAT..." >&2
            if [ "$FSTYPE" = "exfat" ]; then
                umount "$MP" 2>/dev/null || true
                mount -t exfat -o "uid=$USER_UID,gid=$USER_GID,umask=000,nofail" "$DEVICE" "$MP" || echo "Failed to remount $MP with umask=000. Check errors." >&2
                if su - "$TARGET_USER" -c "touch '$MP/.testfile' 2>/dev/null"; then
                    echo "$MP is now writable with umask=000. Updating $FSTAB with umask=000 for $DEVICE." >&2
                    rm -f "$MP/.testfile"
                    # Update fstab with umask=000 for this device
                    sed -i "/`\(UUID/s/[^[:space:]]*\)`/uid=$USER_UID,gid=$USER_GID,umask=000,nofail 0 2/" "$FSTAB"
                    echo "Current $FSTAB content:" >&2
                    cat "$FSTAB" >&2
                    if grep -q "UUID=$UUID.*umask=000" "$FSTAB"; then
                        echo "Successfully updated $FSTAB for $MP with umask=000."
                    else
                        echo "Failed to update $FSTAB for $MP. Please manually update $FSTAB to include umask=000 for UUID=$UUID." >&2
                    fi
                else
                    echo "Error: $MP is still not writable by user $TARGET_USER. Run 'sudo fsck.exfat $DEVICE' to check filesystem." >&2
                fi
            else
                echo "Error: $MP is not writable by user $TARGET_USER. Check mount options or filesystem state." >&2
            fi
        fi
    fi
done
if [ "$PERMISSION_SET" -eq 0 ]; then
    echo "No valid mount points found for permission changes."
fi

echo "Done! Reboot to confirm persistent mounts with 'sudo reboot'."
