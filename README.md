# backup.sh
Uses rsync to back up your folders to a filesystem, optionally mounting and unmounting as it goes. Can also be used to configure a daily, unattended backup job.

If the volume is already mounted elsewhere, it will unmount it and then remount it to the configured location. If mount by UUID fails, it can optionally mount by device URI, which is detected automatically.

First edit the following settings:

Line 22: Change backupuuid to the uuid of the device where you want to store your backups. To find it, connect your backup device and type blkid. The device you want should be the last entry in the list.

Line 29: Change backuproot if you want to use a different mountpoint for your backup volume.

Line 30: Change backupdirectory if you want to keep your backups in a different folder on the backup volume.

Line 36: Change excludes to the names of folders you want to exclude from the backup. Full paths not required.

Line 38: Set doUnmount to true if you want to automatically unmount the drive after backup. This is just extra security so that your backups don't get accidentally written to, and so if you're using an external backup drive you can just unplug it when the backup is done

A good place to store my scripts is in the bin subfolder of your home folder ($HOME/bin) just make sure it's in your PATH

As with all my scripts, I'd recommend that you read and understand this script thoroughly before you run it. I take no responsibility for any loss of data! This one is very thoroughly commented, so go ahead and change it as necessary to suit your setup.
