#!/bin/bash
#backup.sh - script to automate rsync backups
#
#error codes
# 1 - Abort signal SIGINT SIGTERM or SIGHUP received. 
# 2 - No backup folders specified
# 3 - Failed to create launcher script
# 4 - Failed to create mount point
# 5 - Not running as root when root is required
# 6 - Failed to remove launcher script
# 7 - Failed to locate launcher script
# 8 - Backup volume not mounted
# 9 - Unrecognized argument in command line
#10 - Failed to unmount backup volume
#11 - Failed to mount backup volume by UUID or device URI
#12 - Failed to remove mount point
#13 - logrotate package not installed
#14 - Failed to create logrotate config
#15 - Failed to create backup directory
#16 - Backup volume not connected

backupuuid="0096c06d-859e-449c-8fd5-afaab01c0ef2" #UUID of backup device. Make sure to change this to the UUID of your own backup drive. You can find it by typing blkid /dev/sdb1 (or whatever device you're using) and you can find the device by using lsusb and lsblk after connecting your backup device.

a=($(blkid | grep $backupuuid)) #search block ids for backup device UUID and place device info into an array
backupdevice=${a[0]::-1} #first item in the array, minus the trailing ":" is the uri of the device with the matching UUID
unset a

rsynccmd="$(which rsync) -aAXogu --delete --ignore-errors" # the command used to do the backing up
backuproot="/mnt/archive" #mount point for backup volume
backupdirectory="backups" #name of the backups folder within the backup volume
backupsrc="/home" #folders to back up. Spaces and special characters in directory names MUST be escaped with backslash. WARNING! USING WILDCARDS MAY CAUSE PROBLEMS!
scriptfilename="backup" #anachron launcher script filename - WARNING! IF YOU USE A FILE EXTENSION THE SCRIPT WILL NOT RUN!
backuplog="/var/log/$scriptfilename.log" #output log location
scriptfile="/etc/cron.daily/$scriptfilename" #anachron launcher script location
logconfig="/etc/logrotate.d/$scriptfilename" #logrotate config file location
excludes="GoogleDrive .cache" # folders to exclude from the backup. Spaces and special characters in directory names MUST be escaped with backslash. WARNING! USING WILDCARDS COULD RESULT IN A VERY LONG COMMAND STRING AND MAY CAUSE PROBLEMS!
thisscript="$0" # path to this script file, don't edit this
doUnmount=false #flag to signify whether to unmount after backup. set to true if you want to unmount your backup device for added security
doMountbyURI=true #flag to signify whether to fall back to mount by device name if mount by UUID fails. Used to be risky but its ok now the device URI is automatically discovered from the UUID
isBackingUp=false #flag to signify whether we're currently backing up or not

#call me when backup fails :-)
errorexit() {
  echo "Backup failed at $(date)" >&2
  exit $1
}

#output time and text, for logging
echotd() {
  echo "[$(date +%T)]" "$@"
}

#trap shutdown and termination signals
killed() {
  if $isBackingUp; then
    echo "Backup aborted at $(date)" >&2
  else
    echo "Aborting"
  fi
  exit 1
}
trap killed SIGINT SIGTERM SIGHUP

#Check backup sources
tempstring="" # set a temporary string for verified sources list
if [[ -n "$backupsrc" ]]; then #do we have folders to back up?
  for backupfolder in $backupsrc; do #if so, iterate through the list.
    if [[ -d "$backupfolder" ]]; then #does the specified directory exist?
      if [[ -n "$tempstring" ]]; then #if so, does the temp string have anything in it?
        tempstring="$tempstring $backupfolder" #if so, add the directory to the string
      else #otherwise, initialise the string with the directory
        tempstring="$backupfolder"
      fi
    else # if the specified directory does not exist, display a message
      echo "Source folder $backupfolder does not exist. Please edit $thisscript" >&2
    fi
  done
  backupsrc="$tempstring" # Change sources list to verified sources list
fi
if [[ -z "$backupsrc" ]]; then #if no verified source directories, display a message and exit
  echo "No backup folders specified in $thisscript, exiting." >&2
  exit 2
fi

#Check exclude list
if [[ -n "$excludes" ]]; then #do we have folders to exclude?
  for excludeopt in $excludes; do #if so, iterate through them
    rsynccmd="$rsynccmd --exclude=$excludeopt" # and add each one to the rsync command
  done
fi

#Check the command line
if [[ "$1" = "--help" ]] || [[ "$1" = "-h" ]]; then #Display help text if --help or -h are the first argument
  echo
  echo "Backup script with automation installer."
  echo
  echo "Mounts device with UUID $backupuuid"
  echo "to $backuproot"
  echo "If unsuccessful, can optionally attempt to mount"
  echo "$backupdevice to $backuproot"
  echo "Backs up contents of $backupsrc to $backuproot"
  echo "Excludes $excludes from backup"
  echo "Can be set in code to unmount the drive after backup"
  echo "or not. Default is not."
  echo
  echo "Syntax:"
  echo "	$0 -h,--help		Display this text"
  echo "	$0 -i,--install [-v]	Installs the backup script launcher to $scriptfile with optional verbose setting for the launcher (Requires root privilege)"
  echo "	$0 -r,--remove		Removes the backup script launcher so no automatic backups can be made. Use this if something has gone wrong with your system and you don't want the errors made permanent. (Requires root privilege)"
  echo "	$0 -n,--run [-v]		Runs the backup script with optional verbosity (Must be run as root)"
  echo
elif [[ "$1" = "--install" ]] || [[ "$1" = "-i" ]]; then #install backup launcher script if --install or -i are the first argument
  if (which logrotate > /dev/null); then # First, check if logrotate package is installed
    #Creating the launcher script
    if [[ -a "$scriptfile" ]]; then
      echo "Overwriting launcher script at $scriptfile..."
    else
      echo "Creating launcher script at $scriptfile..."
    fi
    parm="--run"
    if [[ "$2" = "-v" ]]; then # check for -v
      parm="$parm $2"
    fi
    nicebin=$(which nice)
    cat <<- _EOF_ | sudo tee "$scriptfile" > /dev/null #the following lines, ending with _EOF_ tell the launcher script to launch this script
		#!/bin/bash
		if [[ ! -a "$backuplog" ]]; then
		  echo "Log created: \$(date)" > "$backuplog"
		fi
		echo >> "$backuplog"
		$nicebin -n20 "$thisscript" $parm >> "$backuplog" 2>&1
	_EOF_
    if [[ -a "$scriptfile" ]]; then
      sudo chmod a+x "$scriptfile" #make the launcher script executable
      echo "Finished."
      #setting up logrotate
      if [[ -a "$logconfig" ]]; then
        echo "Overwriting logrotate config at $logconfig..."
      else
        echo "Creating logrotate config at $logconfig..."
      fi
      cat <<- _EOF_ | sudo tee "$logconfig" > /dev/null #the following lines, ending with _EOF_ tell logrotate how to rotate the backup log file
		$backuplog {
		  rotate 6
		  monthly
		  compress
		  missingok
		  notifempty
		}
		_EOF_
      if [[ -a "$logconfig" ]]; then
        echo "Finished."
      else
        echo "Failed to create logrotate config at $logconfig." >&2
        exit 14
      fi
    else
      echo "Failed to create launcher at $scriptfile." >&2
      exit 3
    fi
  else
    echo "Logrotate not installed. Please install it from the repository and run the install again."
    exit 13
  fi
elif [[ "$1" = "--remove" ]] || [[ "$1" = "-r" ]]; then # was --remove or -r option specified?
  #Removing the launcher script
  exitval=0
  if [[ -a "$scriptfile" ]]; then # if so, does the script launcher exist?
    echo "Removing launcher script $scriptfile"
    if ! (sudo rm "$scriptfile"); then #if so, delete it/
      echo "Could not remove $scriptfile." >&2 # something went wrong, so display a message and exit
      exitval=6
    else
      echo "Script removed."
    fi
  else #if script launcher doesn't exist, display a message and exit.
    echo "Script launcher not found at $scriptfile." >&2
    exitval=7
  fi
  #Removing the logrotate config
  if [[ -a "$logconfig" ]]; then # does the logrotate config exist?
    echo "Removing logrotate config $logconfig"
    if ! (sudo rm "$logconfig" > /dev/null 2>&1); then #if so, delete it
      echo "Could not remove $logconfig." >&2 # something went wrong, so display a message and exit
      exitval=14
    else
      echo "Logrotate config removed."
    fi
  fi
  if [[ $exitval -gt 0 ]]; then
    echo "Exiting due to file removal errors." >&2
    exit $exitval
  fi
elif [[ "$1" = "--run" ]] || [[ "$1" = "-n" ]]; then #--run or -n option speecified, do the backup
  isBackingUp=true # We are currently backing up
  if [[ ! -z "$backupdevice" ]]; then # Is the backup volume connected?
    #Checking for verbose option
    if [[ "$2" = "-v" ]]; then # was the verbosity option specified?
      rsynccmd="$rsynccmd -v" # if so, add "-v" option to rsync command
    fi
    #Checking for root user
    if [[ "$(/usr/bin/id -u)" = "0" ]]; then #are we running as root?

      echo "Starting backup: $(date)"
      echo "Backing up $backupsrc to $backuproot/$backupdirectory"

      #Creating the mount point
      if [[ ! -d "$backuproot" ]]; then # Does the mount point already exist?
        echotd "Creating backup volume mount point..."  # if not, go ahead and create it
        if ! (mkdir -p "$backuproot" > /dev/null 2>&1); then #create mountpoint and check for success
          # If mount point creation fails, display a message then exit
          echotd "Could not create mount point: $backuproot. Exiting." >&2
          errorexit 4
        fi
      fi

      #Mounting the backup volume
      if ! (lsblk | grep "$backuproot" > /dev/null); then #Is the backup volume mounted to backuproot
        # Backup volume not mounted to backuproot
        a=($(lsblk -l | grep ${backupdevice:(-4)})) #search all block devices, for last 4 chars of uri $backupdevice, and put info into an array
        backupmounted=${a[6]} # get the 7th item from the array, it's the mountpoint of the backup volume if there is one
        unset a
        if [[ -n "$backupmounted" ]]; then #if the volume has a mount point, it is mounted, so...
          echotd "Backup volume with UUID $backupuuid mounted elsewhere. Unmounting"
          if ! (umount "$backupdevice" > /dev/null 2>&1); then #unmount it and check for success
            # Failed to unmount, so display message and exit
            echotd "Could not unmount backup volume $backupdevice. Exiting" >&2
            echotd "$backupmounted" >&2
            errorexit 10
          fi
        fi
        echotd "Mounting backup volume to $backuproot"
        if (mount --uuid="$backupuuid" "$backuproot" > /dev/null 2>&1); then #mount device with $backupuuid to $backuproot and check for success
          echotd "Backup volume mounted by UUID successfully"
          if [[ ! -d "$backuproot/$backupdirectory" ]]; then #Does the backup directory exist under the mount point?
            echotd "Backup directory $backupdirectory not found at $backuproot. Creating directory..."
            if ! (mkdir -p "$backuproot/$backupdirectory" > /dev/null 2>&1); then #It doesn't so make it and check for success
              #Creation failed, so display a message and exit
              echotd "Could not create backup directory $backuproot/$backupdirectory. Exiting."
              if doUnmount; then # Are we flagged to auto unmount?
                if (umount "$backuproot" > /dev/null 2>&1); then # unmount the backup volume and check for success
                  echotd "Backup volume unmounted successfully"
                else #Unmount failed
                  echotd "Could not unmount backup volume at $backuproot" >&2
                  fi
              fi
              errorexit 14
            fi
          fi
        else	#If mount fails, and we have the flag set for mount by URI, attempt to mount by device address
          if doMountbyURI; then
            echotd "Could not mount device with UUID $backupuuid to $backuproot. Attempting to mount by URI $backupdevice" 
            if (mount "$backupdevice" "$backuproot" > /dev/null 2>&1); then # Mount backup volume by device URI and check for success
              echotd "Backup volume mounted by device URI successfully." 
            else #If mount by URI fails, add message to log and exit
              echotd "Could not mount device with URI $backupdevice. Exiting." >&2
              errorexit 11
            fi
          else
            echotd "Could not mount device with UUID $backupuuid. Exiting" >&2
            errorexit 11
          fi
        fi
      fi

      #Performing the backup
      errorflag=false
      for backupdir in $backupsrc; do #iterate through the named directories
        echotd "Backing up $backupdir"
        if ! $rsynccmd "$backupdir" "$backuproot"/"$backupdirectory"/; then #perform the backup and check error status
          errorflag=true #Command completed with errors, so set flag
        fi
        resultstring="without"
        if $errorflag; then
          resultstring="with"
        fi
        echotd "Finished backing up $backupdir $resultstring errors." 
      done

      #Unmount the backup volume
      if [[ $doUnmount = true ]]; then # Are we flagged to unmount after backup?
        echotd "Unmounting backup volume" 
        sleep 10 # wait 10 seconds before unmounting, just in case there's write caching involved
        if (umount "$backuproot" > /dev/null 2>&1); then # unmount the backup volume and check for success
          echotd "Backup volume unmounted successfully" 
        else #Unmount failed
          echotd "Could not unmount backup volume at $backuproot" >&2
          echo "Backup finished at $(date) with errors" 
          exit 10
        fi

        #Removing the mount point
        if [[ -d "$backuproot" ]]; then #Does the mount point exist?
          if (rmdir "$backuproot" > /dev/null 2>&1); then  #If so, remove it and check for success
            echotd "Mount point removed successfully" 
          else 
            echotd "Could not remove mount point $backuproot" >&2 # It failed, so output fail message
            echo "Backup finished at $(date) with errors" 
            exit 12 
          fi
        fi
      fi

      echo "Backup finished at $(date) $resultstring errors" 
      isBackingUp=false #Finished backing up

    else # Not running as root, can't update log. Output to screen and fail log in users home directory
      faillog="$HOME/backupfail.log"
      if [[ -a "$faillog" ]]; then # Check if root fail log exists
        echo >> "$faillog" # It exists, so add a blank line
      else
        touch "$faillog" # Otherwise, create it
      fi
      (
        echo "Not running as root ($USER). Exiting."
	    echo "Backup failed at $(date)"
      ) | tee -a "$faillog"
      exit 5
    fi
  else
    echo "Backup volume not connected at $(date)" >&2
    exit 16
  fi
else # All other arguments
  echo "Unrecognised option: $1" >&2
  echo "Use $0 --help for usage." >&2
  exit 9
fi
