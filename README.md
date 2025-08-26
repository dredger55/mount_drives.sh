# mount_drives

The `mount_drives` Bash script automates mounting and configuring block devices (e.g., external hard drives, USB drives) on Linux systems. It simplifies drive management by detecting devices with `blkid`, mounting them under a configurable directory (default: `/mnt`), and updating `/etc/fstab` for persistent mounts across reboots. Tailored for users managing multiple external drives, it ensures write access for a specified user and supports ext4, NTFS, and exFAT filesystems, making it a versatile tool for seamless storage integration.

Key features include:
- **Device Detection**: Identifies block devices with valid filesystems, skipping small partitions (<1GB) and loop devices to focus on relevant storage.
- **Persistent Mounts**: Adds `/etc/fstab` entries with optimized options, using `umask=000` for NTFS/exFAT to guarantee write permissions.
- **User Customization**: Configures the target user (`TARGET_USER`, defaulting to the current user) and mount base directory (`MOUNT_BASE`) via environment variables or script edits.
- **Automatic Dependencies**: Installs `ntfs-3g` and `exfatprogs` for NTFS/exFAT support if missing, ensuring compatibility.
- **Safety First**: Backs up `/etc/fstab` with a timestamp before modifications and restores it if mounting errors occur.
- **Clean Mount Points**: Creates mount point names from device labels or names, sanitizing special characters for reliability.
- **Permission Management**: Applies ownership and 775 permissions for ext4 mounts, verifies write access for all filesystems, and includes fallback handling for exFAT issues.

**Usage**:
```bash
sudo ./mount_drives.sh
Customize with:
TARGET_USER="youruser" MOUNT_BASE="/media" sudo ./mount_drives.sh
Prerequisites:
	•	Linux system with bash, blkid, lsblk, and mount.
	•	Root privileges (sudo).
Files:
	•	mount_drives.sh: Main script.
	•	README.md: This file.
	•	LICENSE: MIT License.
	•	.gitignore: Excludes backups and temporary files.
Notes:
	•	Back up data before altering filesystems or /etc/fstab.
	•	Verify /etc/fstab entries after running.
	•	Use sudo fsck.exfat or sudo ntfsfix for filesystem issues.
Contributions are welcome via GitHub issues or pull requests. Licensed under the MIT License.
Prerequisites
	•	Linux system with bash, blkid, lsblk, and mount (standard on most distributions).
	•	Root privileges (sudo).
	•	Optional: ntfs-3g and exfatprogs for NTFS/exFAT support (installed automatically if missing).
Installation
	1	Clone the repository: git clone https://github.com/yourusername/mount_drives.git
	2	cd mount_drives
	3	
	4	Make the script executable: chmod +x mount_drives.sh
	5	
Usage
Run the script with sudo:
sudo ./mount_drives.sh
To specify a different user or mount base directory, set environment variables:
TARGET_USER="youruser" MOUNT_BASE="/media" sudo ./mount_drives.sh
Example Output
Installing exfatprogs for exFAT support...
Using UID=1000 and GID=1000 for user youruser.
Backing up /etc/fstab to /etc/fstab.bak.2025-08-26_11-37-00...
Running blkid to detect drives...
Processing /dev/sdd2 (UUID=68A3-DD3E, TYPE=exfat, LABEL=Goonies001, SIZE=7451G)...
Using mount point /mnt/Goonies001...
All drives mounted successfully. Updated /etc/fstab.
Run 'df -h' to verify mounted drives.
Done! Reboot to confirm persistent mounts with 'sudo reboot'.
Configuration
Edit the script to customize:
	•	TARGET_USER: Set to the desired username (defaults to current user).
	•	MOUNT_BASE: Set to the base directory for mount points (default: /mnt).
Example:
TARGET_USER="myuser" MOUNT_BASE="/media" sudo ./mount_drives.sh
Files
	•	mount_drives.sh: Main script to mount drives and configure /etc/fstab.
	•	README.md: This documentation file.
	•	LICENSE: MIT License for open-source usage.
	•	.gitignore: Ignores backup files and temporary files.
Notes
	•	Always back up data before modifying filesystems or /etc/fstab.
	•	For exFAT/NTFS drives, umask=000 is used to ensure write access.
	•	Run sudo fsck.exfat /dev/sdXn or sudo ntfsfix /dev/sdXn if mount issues occur.
	•	Check /etc/fstab after running to ensure correct entries.
Contributing
Contributions are welcome! Please submit a pull request or open an issue on GitHub. Follow these steps:
	1	Fork the repository.
	2	Create a feature branch (git checkout -b feature-name).
	3	Commit changes (git commit -m 'Add feature').
	4	Push to the branch (git push origin feature-name).
	5	Open a pull request.
License
This project is licensed under the MIT License. See the LICENSE file for details.
Author
dredger55 https://github.com/dredger55
