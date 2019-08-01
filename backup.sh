#!/bin/bash
#backup.sh v2
#this time with functions, and configs!
#
#CHANGELOG
#
#	v2.1.1	(Aug 19)	Bug fixes, code tidied further, easter egg made more tricksy to stop cheaters
#	v2.1	(Jul 19)	Added daemon mode, as well as the ability to create and remove daemon mode startup scripts. Also more bug fixes and code tidying
#	v2.0	(Jul 19)	Added config files, changed order of operation, split code into functions, added update and reconfiguration options, generally tidied up and improved code, fixed some bugs
#	v1 to v1.8	(Mar to Jun 19)	Original backup.sh, improved over time
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
# 9 - Unrecognised argument in command line
#10 - Failed to unmount backup volume
#11 - Failed to mount backup volume by UUID or device URI
#12 - Failed to remove mount point
#13 - logrotate package not installed
#14 - Failed to create logrotate config
#15 - Failed to create backup directory
#16 - Backup volume not connected
#17 - Could not unmount other volume from BACKUPROOT
#18 - Failed to create config file
#19 - Failed to get sudo credentials when requested
#20 - Unrecognised command in command line
#21 - Failed to create init.d script
#22 - Failed to remove init.d script
#23 - Function not yet implemented

DEBUG=false

doExit()
{
	if ! $isDaemonMode; then
		exit $1
	fi
}

doSleep()
{
	isSleeping=true
	sleep $1
	isSleeping=false
}

#call me when backup fails :-)
errorExit() {
	if $DEBUG; then echo "errorExit \"$1\" \"$2\""; fi
	echo "Backup failed at $(date)" >&2
	doExit $1
}

#output time and text, for logging
echotd() {
	if $DEBUG; then echo "echotd \"$@\""; fi
	echo "[$(date +%T)]" "$@"
}

#trap shutdown and termination signals, contains a super secret easter egg. Are you quick enough?
killed() {
	if $DEBUG; then 
		sharpshooter=true
		for a in $isBackingUp $isSettingUp $isDaemonMode $isSleeping; do
			$a && sharpshooter=false
		done
		if ! $sharpshooter ; then
			echotd "Received SIGINT, SIGTERM or SIGHUP"
		else
			echo "Shot through the heart, and you're to blame. Darlin' you give love..."
			sleep 3s
			echo "...a bad name."
			echo
			echo "Seriously, that was some quick shootin', Tex. You've earned your \"CTRL-C Cowboy\" badge!"
			echo
		fi
	fi
	if $isBackingUp; then
		echo "Backup aborted at $(date)" >&2
	fi
	if $isDaemonMode; then
		echo "Stopping daemon at $(date)"
		exit 0
	elif $isSettingUp; then
		echo "Setup aborted."
		if [[ -e "$tmpname" ]]; then
			rm "$tmpname"
		fi
	else
		echo "Aborting"
	fi
	exit 1
}

#compare two version numbers using sort. Returns true if first value is greater than the second.
isGreater()
{
	if $DEBUG; then echo "isGreater \"$1\" \"$2\""; fi
	test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

#echo text redirected to the temporary config file
configEcho()
{
	if $DEBUG; then echo "configEcho \"$1\""; fi
	echo "$1" >> "$tmpname" 
}

sudoFail()
{
	if $DEBUG; then echo "sudoFail"; fi
	echo "Failed to get sudo credentials. Exiting."
	doExit 19
}

displayInfo()
{
	if $DEBUG; then echo "displayInfo"; fi
	echo "backup.sh v$VERSION"
	echo "Mounts backup volume, backs up data, schedules daily backups, optionally unmounts after backup."
	echo "Ideally suited for backing up laptops with external drives when at home and connected."
	echo
	echo "Format is: $THISSCRIPT {command} [options...]"
	echo
	echo "Commands:"
	echo "	[e]nable	Enable the daily automated backup. (Uses sudo)"
	echo "	[d]isable	Disable the daily automated backup. (Uses sudo)"
	echo "	[c]reate	Create init.d script to launch daemon mode at startup. (Uses sudo)"
	echo "	destro[y]	Remove init.d script which launches daemon mode at startup. (Uses sudo)"
	echo "		NOTE: Daemon mode is not intended for permanently connected backup devices."
	echo "	[r]un		Run a backup job. (Must be run as root)"
	echo "	[u]pdate	Checks github for new version and updates as necessary."
	echo "	[s]etup		Create a new config file (either in the default of $defCONFFILE or where specified with --config, may require sudo)."
	echo "	[h]elp		Display this information page."
	echo
	echo "Options:"
	echo "	-v				Give more details when running backups or displaying info"
	echo "	--config={path to config file}	Use specified config file instead of default."
	echo
	echo "Note, if you specify an alternate config which does not exist, you will automatically be taken"
	echo "through the setup process, just as you are when running this script for the first time."
	echo
	showextra=false
	$verbose && showextra=true
	$DEBUG && showextra=true
	if $showextra; then
		echo "CONFFILE=$CONFFILE"
		echo "UUID=$UUID"
		echo "DEVICEURI=$DEVICEURI"
		echo "BACKUPROOT=$BACKUPROOT"
		echo "BACKUPSRC=$BACKUPSRC"
		echo "EXCLUDES=$EXCLUDES"
		echo "SCRIPTNAME=$SCRIPTNAME"
		echo "BACKUPLOG=$BACKUPLOG"
		echo "SCRIPTFILE=$SCRIPTFILE"
		echo "LOGCONFIG=$LOGCONFIG"
		echo "UNMOUNTAFTER=$UNMOUNTAFTER"
	fi
}

setDefaults()
{
	if $DEBUG; then echo "setDefaults"; fi
	defUUID="null"
	defBACKUPROOT="/mnt/backup"
	defBACKUPDIR="backups"
	defBACKUPSRC="/home"
	defEXCLUDES=".cache"
	defSCRIPTNAME="backup"
	defRSYNCCMD="$(which rsync) -aAEXu --delete --ignore-errors"
	defUNMOUNTAFTER=true
}

doCreateConfig()
{
	if $DEBUG; then echo "doCreateConfig"; fi
	isSettingUp=true
	echo "Creating new config file at $CONFFILE."
	echo "We will need to use sudo to edit default config locations, please enter your password if prompted."
	if (sudo true); then
		#First create a temporary config file
		tmpname="$(tempfile)"
		touch "$tmpname"
		configEcho "# backup.sh $VERSION configuration file"
		configEcho "# Created $(date) by $USER"
		configEcho "# Do not edit manually, use $THISSCRIPT setup --config=\"$CONFFILE\" to configure."
		configEcho ""
		#Get the UUID of the backup volume
		echo "Please connect your backup device now and hit ENTER"
		echo "If it isn't formatted and ready for use, you'll need to take care of that before you continue."
		echo "If it's already connected, unmount and disconnect it, then reconnect"
		read dummy
		echo "Waiting ten seconds for file system shenanigans to sort themselves out..."
		doSleep 10s
		if [[ "$defUUID" = "null" ]]; then #if we don't already have a UUID to use as default, get the last mounted device's UUID
			a=($(blkid | tail -n 1)) #store the last line of blkid's output in an array
			a[2]="${a[2]#*=}" #get everything after the "=" from the third item in the array
			a[2]="${a[2]#\"}" #strip out the leading...
			defUUID="${a[2]%\"}" #...and trailing quotes
		fi
		UUID="null"
		while ! (blkid | grep -q "$UUID"); do
			if $DEBUG; then echo "UUID=$UUID defUUID=$defUUID"; fi
			clear
			blkid
			echo
			echo "This is a list of attached filesystems. Please enter the UUID of your backup device."
			echo "Leave blank for $defUUID, otherwise copy and paste the UUID you want and hit ENTER."
			read -r UUID
			if [[ -z "$UUID" ]]; then
				UUID="$defUUID"
			fi
			if ! (blkid | grep -q "$UUID"); then
				echo "Couldn't find UUID $UUID in the device list. Is the device connected? Please hit ENTER to try again."
				read dummy
			fi
		done
		configEcho "UUID=\"$UUID\""
		#Get the mount point BACKUPROOT
		echo "Please enter the mount point for the backup volume and press ENTER."
		echo "Default is $defBACKUPROOT"
		read -r BACKUPROOT
		if [[ -z "$BACKUPROOT" ]]; then
			BACKUPROOT="$defBACKUPROOT"
		fi
		configEcho "BACKUPROOT=\"$BACKUPROOT\""
		#Get the backup folder BACKUPDIR
		echo "Please enter the backup subdirectory name and press ENTER"
		echo "Default is $defBACKUPDIR"
		read -r BACKUPDIR
		if [[ -z "$BACKUPDIR" ]]; then
			BACKUPDIR="$defBACKUPDIR"
		fi
		configEcho "BACKUPDIR=\"$BACKUPDIR\""
		#Get the source folders BACKUPSRC
		echo "Please enter a space-separated list of folders to back up, and press ENTER."
		echo "Default is $defBACKUPSRC"
		read -r BACKUPSRC
		if [[ -z "$BACKUPSRC" ]]; then
			BACKUPSRC="$defBACKUPSRC"
		fi
		configEcho "BACKUPSRC=\"$BACKUPSRC\""
		#Get exclude list EXCLUDES
		echo "Please enter a space-separated list of keywords to exclude from the folder list, and press ENTER."
		echo "Default is $defEXCLUDES"
		read -r EXCLUDES
		if [[ -z "$EXCLUDES" ]]; then
			EXCLUDES="$defEXCLUDES"
		fi
		configEcho "EXCLUDES=\"$EXCLUDES\""
		#Get script name SCRIPTNAME
		echo "Please enter the default script name and press ENTER. This will be used to name the log and script files, and the logrotate config file."
		echo "Warning: Things won't work properly if you add an extension to the filename. So, no full stops, just the file name."
		echo "Default is $defSCRIPTNAME"
		read -r SCRIPTNAME
		if [[ -z "$SCRIPTNAME" ]]; then
			SCRIPTNAME="$defSCRIPTNAME"
		fi
		configEcho "SCRIPTNAME=\"$SCRIPTNAME\""
		#Get rsync command options RSYNCCMD
		echo "Please enter the command line used to execute rsync and press ENTER. It's highly recommended you stick to the default here."
		echo "Default is $defRSYNCCMD"
		read -r RSYNCCMD
		if [[ -z "$RSYNCCMD" ]]; then
			RSYNCCMD="$defRSYNCCMD"
		fi
		configEcho "RSYNCCMD=\"$RSYNCCMD\""
		#Get unmount flag UNMOUNTAFTER
		UNMOUNTAFTER=""
		while [[ -z "$UNMOUNTAFTER" ]]; do 
			echo "Do you want to unmount the backup volume after each backup? (Y/N)"
			if $defUNMOUNTAFTER; then
				echo "Default is \"Y\""
			else
				echo "Default is \"N\""
			fi
			read -r -n 1 inkey
			case $inkey in
				("y"|"Y")	UNMOUNTAFTER=true;;
				("n"|"N")	UNMOUNTAFTER=false;;
				("")		if $defUNMOUNTAFTER; then
								UNMOUNTAFTER=true
							else
								UNMOUNTAFTER=false
							fi;;
			esac
			echo
		done
		configEcho "UNMOUNTAFTER=\"$UNMOUNTAFTER\""
		if ! (touch "$CONFFILE.tmpxyz" > /dev/null 2>&1); then #can we edit files in the folder where CONFFILE is stored?
			mvcmd="sudo mv" #if not, we need sudo to do the move
			rmcmd="sudo rm"
		else
			rm "$CONFFILE.tmpxyz" #otherwise, remove the temp file we created
			mvcmd="mv" #no sudo needed
			rmcmd="rm"
		fi
		$rmcmd "$CONFFILE" #remove the old config file. We've already backed it up, so it's fine.
		$mvcmd "$tmpname" "$CONFFILE" #move the temp config file to CONFFILE
		if [[ -e "$CONFFILE" ]]; then
			echo "Config file $CONFFILE created successfully."
			justcreated=true
		else
			echo "Failed to create config file $CONFFILE."
			doExit 18
		fi
	else
		sudoFail
	fi
	isSettingUp=false
}

doReconfig()
{
	if $DEBUG; then echo "doReconfig"; fi

	if [[ ! -w "$(dirname \"$CONFFILE\")" ]]; then #test for write access to the directory where CONFFILE is stored
		echo "We may need to use sudo to manipulate the config file. Please enter your password if asked."
		if (sudo true); then
			rmcmd="sudo rm"
			cpcmd="sudo cp"
		else
			sudoFail
		fi
	else
		rmcmd="rm"
		cpcmd="cp"
	fi

	if [[ -e "$CONFFILE" ]]; then
		if [[ -e "$CONFFILE.bak" ]]; then
			$rmcmd "$CONFFILE.bak"
		fi
		$cpcmd "$CONFFILE" "$CONFFILE.bak"
		if [[ -e "$CONFFILE.bak" ]]; then
			echo "Old config file saved to $CONFFILE.bak"
		else
			isSettingUp=true
			echo "Could not create backup of config file. Hit ENTER to proceed anyway, CTRL-C to cancel"
			read dummy
			isSettingUp=false
		fi
	fi
	
	if ! $justcreated; then
		defUUID="$UUID"
		defBACKUPROOT="$BACKUPROOT"
		defBACKUPDIR="$BACKUPDIR"
		defBACKUPSRC="$BACKUPSRC"
		defEXCLUDES="$EXCLUDES"
		defSCRIPTNAME="$SCRIPTNAME"
		defRSYNCCMD="$RSYNCCMD"
		defUNMOUNTAFTER=$UNMOUNTAFTER

		doCreateConfig
	fi
}

getURIFromUUID()
{
	if $DEBUG; then echo "getURIFromUUID"; fi
	#Set device URI from UUID
	#a=($(blkid | grep \$UUID)) #search block ids for backup device UUID and place device info into an array
	#echo "${a[0]::-1}" #first item in the array, minus the trailing ":" is the uri of the device with the matching UUID
	#unset a
	blkid | grep $UUID | cut -d: -f1 # search output of blkid for UUID. First field, delimited by ":" is device URI
}

doLoadConfig()
{
	if $DEBUG; then echo "doLoadConfig"; fi
	if [[ ! -e "$CONFFILE" ]]; then #is the config file missing?
		echo "Config file not found at $CONFFILE"
		setDefaults
		doCreateConfig
	fi
	. "$CONFFILE" #execute config file to set config options	
	
	DEVICEURI="$(getURIFromUUID)"
	
	#Set BACKUPLOG, SCRIPTFILE, LOGCONFIG and INITSCRIPT from SCRIPTNAME
	BACKUPLOG="/var/log/$SCRIPTNAME.log"
	SCRIPTFILE="/etc/cron.daily/$SCRIPTNAME"
	LOGCONFIG="/etc/logrotate.d/$SCRIPTNAME"
	INITSCRIPT="/etc/init.d/$SCRIPTNAME"
	#INITSCRIPT="/etc/profile.d/$SCRIPTNAME"
	
	#Check config file version
	a=($(head -n 1 "$CONFFILE")) #Get the first line of the config file into an array. 
	#Versions newer than 2.0 have the version number as the third element. 
	#Version 2.0 has no version number, so if none is present, assume 2.0
	v="${a[2]}"
	if [[ -z "$v" ]]; then 
		v="2.0"
	fi
	if isGreater "2.1" "$v"; then #2.1 is the latest version with changes to the config file, 
								#so check configs against that version rather than the current one
		echo "Config file out of date. Reconfiguring."
		doReconfig
	fi
}

getArguments()
{
	if $DEBUG; then echo "getArguments \"$@\""; fi
	command="$1"
	if [[ -z "$command" ]]; then
		displayInfo
	elif [[ "${command:0:1}" = "-" ]]; then
		echo "Unrecognised command: $command. Type $THISSCRIPT help for help"
		doExit 20
	fi
	shift
	while [[ ! -z "$1" ]]; do
		i="$1"
		if [[ "${i:0:8}" != "--config" ]]; then #we've already processed --config, let's just process everything else
			case "$i" in
				("-v")			verbose=true;;
				("-h"|"--help")	displayInfo; doExit 0;;
				(*)				echo "Unknown option $i. Type $THISSCRIPT help for help"; doExit 9;;
			esac
		fi
		shift
	done
}

getSudoPassword()
{
	if $DEBUG; then echo "getSudoPassword"; fi
	echo "We need to use sudo to enable or disable automated backups. Please enter your password if asked."
	if ! (sudo true); then
		sudoFail
	fi
}

doCreateLogRotate()
{
	#setting up logrotate
	if [[ -a "$LOGCONFIG" ]]; then
		echo "Overwriting logrotate config at $LOGCONFIG..."
	else
		echo "Creating logrotate config at $LOGCONFIG..."
	fi
	cat <<- _EOF_ | sudo tee "$LOGCONFIG" > /dev/null #the following lines, ending with _EOF_ tell logrotate how to rotate the backup log file
		$BACKUPLOG {
		  rotate 6
		  monthly
		  compress
		  missingok
		  notifempty
		}
	_EOF_
	if [[ -a "$LOGCONFIG" ]]; then
		echo "Finished."
	else
		echo "Failed to create logrotate config at $LOGCONFIG." >&2
		doExit 14
	fi
}

doEnableBackups()
{
	if $DEBUG; then echo "doEnableBackups"; fi
	getSudoPassword
	if (which logrotate > /dev/null); then # First, check if logrotate package is installed
		#Creating the launcher script
		if [[ -a "$SCRIPTFILE" ]]; then
			echo "Overwriting launcher script at $SCRIPTFILE..."
		else
			echo "Creating launcher script at $SCRIPTFILE..."
		fi
		parm="run --config=\"$CONFFILE\""
		if $verbose; then 
			parm="$parm -v"
		fi
		nicebin=$(which nice)
		cat <<- _EOF_ | sudo tee "$SCRIPTFILE" > /dev/null #the following lines, ending with _EOF_ tell the launcher script to launch this script
			#!/bin/bash
			if [[ ! -a "$BACKUPLOG" ]]; then
			  echo "Log created: \$(date) by $THISSCRIPT" > "$BACKUPLOG"
			fi
			echo >> "$BACKUPLOG"
			$nicebin -n20 "$THISSCRIPT" $parm >> "$BACKUPLOG" 2>&1
		_EOF_
		if [[ -a "$SCRIPTFILE" ]]; then
			sudo chmod a+x "$SCRIPTFILE" #make the launcher script executable
			echo "Finished."
			doCreateLogRotate
		else
			echo "Failed to create launcher at $SCRIPTFILE." >&2
			doExit 3
		fi
	else
		echo "Package logrotate not installed. Please install it from the repository and run the install again."
		doExit 13
	fi
}

doDisableBackups()
{
	if $DEBUG; then echo "doDisableBackups"; fi
	getSudoPassword
	#Removing the launcher script
	exitval=0
	if [[ -a "$SCRIPTFILE" ]]; then # if so, does the script launcher exist?
		echo "Removing launcher script $SCRIPTFILE"
		if ! (sudo rm "$SCRIPTFILE"); then #if so, delete it/
			echo "Could not remove $SCRIPTFILE." >&2 # something went wrong, so display a message and exit
			exitval=6
		else
			echo "Script removed."
		fi
	else #if script launcher doesn't exist, display a message
		echo "Script launcher not found at $SCRIPTFILE." >&2
		exitval=7
	fi
	#Removing the logrotate config
	if [[ -a "$LOGCONFIG" ]]; then # does the logrotate config exist?
		echo "Removing logrotate config $LOGCONFIG"
		if ! (sudo rm "$LOGCONFIG" > /dev/null 2>&1); then #if so, delete it
			echo "Could not remove $LOGCONFIG." >&2 # something went wrong, so display a message and exit
			exitval=14
		else
			echo "Logrotate config removed."
		fi
	fi
	if [[ $exitval -gt 0 ]]; then
		echo "Exiting due to file removal errors." >&2
		doExit $exitval
		return $exitval
	fi

}

doMountVolume()
{
	if $DEBUG; then echo "doMountVolume"; fi
	if [[ -z "$DEVICEURI" ]]; then
		DEVICEURI="$(getURIFromUUID)"
	fi
	#a=($(lsblk | grep q "$BACKUPROOT" > /dev/null 2>&1)) #search output of lsblk for BACKUPROOT and save results in an array
	#Creating the mount point
	if [[ ! -d "$BACKUPROOT" ]]; then # Does the mount point already exist?
		echotd "Creating backup volume mount point..."  # if not, go ahead and create it
		if ! (mkdir -p "$BACKUPROOT" > /dev/null 2>&1); then #create mountpoint and check for success
			# If mount point creation fails, display a message then exit
			echotd "Could not create mount point: $BACKUPROOT. Exiting." >&2
			errorExit 4
			return 4
		fi
	elif [[ ! -z $(lsblk -lp | grep $DEVICEURI | awk '{print $NF}') ]]; then #if the mountpoint exists, and a search for the last 3 chars of DEVICEURI in lsblk is nonzero, something is mounted at the mount point
		a=$(lsblk -lp | grep $BACKUPROOT) # get info about whatever is mounted at BACKUPROOT
		a=${a/ */} #everything before the first space in that info is the URI of the device
		#b=${a[0]:-3} #last three chars of device URI for device mounted at BACKUPROOT. Device URI is in first element of array "a"
		#c=${DEVICEURI:-3} #last three chars of our backup device URI
		if [[ "$a" != "$DEVICEURI" ]]; then #  If BACKUPROOT's device URI and DEVICEURI do not match, something else is mounted at BACKUPROOT
			echotd "Something else mounted at $BACKUPROOT. Unmounting"
			doSleep 5s #wait for 5 seconds just in case linux is still assimilating this volume :-)
			if ! (umount "$BACKUPROOT" > /dev/null 2>&1); then #unmount it and check for success
				#failed to unmount, so display a message and exit
				echotd "Could not unmount $BACKUPROOT. Exiting."
				errorExit 17
				return 17
			fi
		fi
	fi 

	#Mounting the backup volume
	if ! (lsblk | grep -q "$BACKUPROOT" > /dev/null); then #If nothing is mounted to BACKUPROOT
		#a=($(lsblk -lp | grep $DEVICEURI)) #search all block devices, for last 3 chars of uri $DEVICEURI, and put info into an array
		backupmounted=$(lsblk -p | grep $DEVICEURI | awk '{print $NF}') #search block devices for DEVICEURI and store mount point in a string
		#backupmounted=${a[6]} # get the 7th item from the array, it's the mountpoint of the backup volume if there is one
		#unset a
		if [[ -n "$backupmounted" ]]; then #if the volume has a mount point, it is mounted, so...
			echotd "Backup volume $DEVICEURI mounted to $backupmounted. Unmounting"
			doSleep 5s #wait for 5 seconds just in case linux is still assimilating this volume :-)
			if ! (umount "$backupmounted" > /dev/null 2>&1); then #unmount it and check for success
				if ! $isDaemonMode; then #not in daemon mode, exit, in daemon mode, carry on
					# Failed to unmount, so display message and exit
					echotd "Could not unmount backup volume $DEVICEURI. Exiting" >&2
					echotd "$backupmounted" >&2
					errorExit 10
				else
					echotd "Could not unmount $DEVICEURI. Continuing anyway,"
				fi
			fi
		fi
		echotd "Mounting backup volume to $BACKUPROOT"
		if (mount --uuid="$UUID" "$BACKUPROOT" > /dev/null 2>&1); then #mount device with $UUID to $BACKUPROOT and check for success
			echotd "Backup volume mounted by UUID successfully"
			if [[ ! -d "$BACKUPROOT/$BACKUPDIR" ]]; then #Does the backup directory exist under the mount point?
				echotd "Backup directory $BACKUPDIR not found at $BACKUPROOT. Creating directory..."
				if ! (mkdir -p "$BACKUPROOT/$BACKUPDIR" > /dev/null 2>&1); then #It doesn't so make it and check for success
					#Creation failed, so display a message and exit
					echotd "Could not create backup directory $BACKUPROOT/$BACKUPDIR. Exiting."
					if doUnmount; then # Are we flagged to auto unmount?
						if (umount "$BACKUPROOT" > /dev/null 2>&1); then # unmount the backup volume and check for success
							echotd "Backup volume unmounted successfully"
						else #Unmount failed
							echotd "Could not unmount backup volume at $BACKUPROOT" >&2
						fi
					fi
					errorExit 14
					return 14
				fi
			fi
			return 0
		else #If mount fails, attempt to mount by device address
			echotd "Could not mount device with UUID $UUID to $BACKUPROOT. Attempting to mount by URI $DEVICEURI" 
			if (mount "$DEVICEURI" "$BACKUPROOT" > /dev/null 2>&1); then # Mount backup volume by device URI and check for success
				echotd "Backup volume mounted by device URI successfully." 
				return 0
			else #If mount by URI fails, add message to log and exit
				echotd "Could not mount device with URI $DEVICEURI. Exiting." >&2
				errorExit 11
				return 11
			fi
		fi
	fi
	return 0
}

doUnmountVolume()
{
	if $DEBUG; then echo "doUnmountVolume"; fi
	#Unmount the backup volume
	echotd "Unmounting backup volume" 
	doSleep 10 # wait 10 seconds before unmounting, just in case there's write caching involved
	if (umount "$BACKUPROOT" > /dev/null 2>&1); then # unmount the backup volume and check for success
		echotd "Backup volume unmounted successfully" 
	else #Unmount failed
		echotd "Could not unmount backup volume at $BACKUPROOT" >&2
		echo "Backup finished at $(date) with errors" 
		doExit 10
	fi

	#Removing the mount point
	if [[ -d "$BACKUPROOT" ]]; then #Does the mount point exist?
		if (rmdir "$BACKUPROOT" > /dev/null 2>&1); then  #If so, remove it and check for success
			echotd "Mount point removed successfully" 
		else 
			echotd "Could not remove mount point $BACKUPROOT" >&2 # It failed, so output fail message
			echo "Backup finished at $(date) with errors" 
			doExit 12 
		fi
	fi
}

doInitBackup()
{
	echo "Starting backup: $(date)"
	if $DEBUG;
		then echo "Debugging v$VERSION"
	fi
	echo "Backing up $BACKUPSRC to $BACKUPROOT/$BACKUPDIR ($DEVICEURI)"
}

doBackup()
{
	if $DEBUG; then echo "doBackup"; fi
	#Performing the backup
	errorflag=false
	for sourcedir in $BACKUPSRC; do #iterate through the named directories
		echotd "Backing up $sourcedir"
		if $verbose; then
			opt="-v"
		else
			opt=""
		fi
		for a in $EXCLUDES; do
			opt="$opt --exclude=$a" #format the excludes list for rsync use
		done

		if ! $RSYNCCMD $opt "$sourcedir" "$BACKUPROOT"/"$BACKUPDIR"/; then #perform the backup and check error status
			errorflag=true #Command completed with errors, so set flag
		fi
		resultstring="without"
		if $errorflag; then
			resultstring="with"
		fi
		echotd "Finished backing up $sourcedir $resultstring errors." 
	done
}

doUpdateScript()
{
	if $DEBUG; then echo "doUpdateScript"; fi
	pushd /tmp > /dev/null #put us in the /tmp folder
	if [[ -e "VERSION" ]]; then #if VERSION file already exists
		rm "VERSION" # then remove it
	fi
	if (wget -q "$VERSIONURL" > /dev/null 2>&1); then #get latest release version number from github 
		curVersion=$(cat "VERSION") #assign it to a variable
		if $DEBUG; then echo "VERSION=$VERSION, curVersion=$curVersion"; fi
		if isGreater "$curVersion" "$VERSION"; then # how to test $curVersion -gt $VERSION with decimals
			echo "New version $curVersion available. You are on $VERSION. Hit ENTER to update or CTRL-C to abort."
			read dummy
			if (wget -q "$SCRIPTURL" > /dev/null 2>&1); then #get the latest release of backup.sh from github
				if [[ -e "$THISSCRIPT.bak" ]]; then
					rm "$THISSCRIPT.bak" #remove old script backup
				fi
				mv "$THISSCRIPT" "$THISSCRIPT.bak" #back up current script
				chmod 755 "backup.sh" #make the new script executable
				mv "backup.sh" "$THISSCRIPT" #move the new script to the location and name of the current script
				echo "Updated backup script. Check what's changed by opening $THISSCRIPT for editing, or going to https://github.com/hp6000x/backup.sh"
				popd > /dev/null #return to previous directory
				doExit 0
			else #download failed
				echo "Could not get new script file from $SCRIPTURL. Is the repository still there?"
			fi
		elif [[ "$VERSION" = "$curVersion" ]]; then
			echo "You are already on the latest version: $VERSION"
		else #Your version has a higher number than the release version.
			echo "Your version: $VERSION. Current version: $curVersion. Can't wait for release, Mr. Developer."
		fi
	else
		echo "Online version information not found."
	fi
	popd > /dev/null #return to previous directory
}

daemonMode()
{
	if $DEBUG; then echo "daemonMode"; fi
	isDaemonMode=true
	echo "Starting daemon at $(date)"
	while true; do #loop forever
		while ! (blkid | grep -q "$UUID"); do #while UUID is not connected
			if $DEBUG; then echotd "Waiting for device."; fi
			doSleep 30s
		done
		doSleep 10s # it takes a few seconds for linux to set up the device after connecting.
		if (blkid | grep -q "$UUID"); then #if UUID is connected
			if $DEBUG; then echo "Device connected. Backing up."; fi
			doInitBackup
			if doMountVolume; then
				isBackingUp=true
				doBackup
				doDone
			fi
		fi
		while (blkid | grep -q "$UUID"); do #while UUID is connected
			if $DEBUG; then echotd "Waiting for device disconnect."; fi
			doSleep 30s
		done
	done
}

getProcess()
{
	a=($(ps aux | grep "$THISSCRIPT daemon" | grep -v grep))
	echo ${a[1]}
}

killDaemon()
{
	if $DEBUG; then echo "killDaemon"; fi
	process=$(getProcess)
	#a=($(getProcess))
	#process=${a[1]}
	if $DEBUG; then
		getProcess
		echotd "Killing $process"
	fi
	while [[ ! -z "$process" ]]; do
		kill $process
		doSleep 2s
		#a=($(getProcess))
		#process=${a[1]}
		process=$(getProcess)
	done
}

doCreateStartupScript()
{
	if $DEBUG; then echo "doCreateStartupScript"; fi
	if (which apt > /dev/null); then
		if [[ ! -e "$INITSCRIPT" ]]; then
			echo "We need to use sudo to create init.d scripts. Please enter your password if asked."
			if (sudo true); then
				echo "Creating startup script $INITSCRIPT."
				opt="daemon"
				if $verbose; then 
					opt="$opt -v"
				fi
				nicebin="$(which nice)"
				cat <<- _EOF_  | sudo tee "$INITSCRIPT" > /dev/null 2>&1
					#!/bin/bash
					
					### BEGIN INIT INFO
					# Provides:          $SCRIPTNAME
					# Required-Start:    \$local_fs \$syslog \$named \$time
					# Required-Stop:     \$local_fs \$syslog \$named \$time
					# Default-Start:     2 3 4 5
					# Default-Stop:      0 1 6
					# Short-Description: $SCRIPTNAME service
					# Description:       Sits and waits for $UUID to be connected, then backs up and repeats
					### END INIT INFO
					
					start() {
					  echo "Starting $SCRIPTNAME"
					  echo >> $BACKUPLOG
					  /bin/bash -c "$THISSCRIPT $opt --config=$CONFFILE" >> $BACKUPLOG 2>&1 &
					}

					stop() {
						echo "Stopping $SCRIPTNAME"
						/bin/bash -c "$THISSCRIPT stop --config=$CONFFILE"
					}
					
					# Carry out specific functions when asked to by the system
					if [[ ! -e "$BACKUPLOG" ]]; then
					  echo "Log created: \$(date) by \$0" > $BACKUPLOG
					fi

					case "\$1" in
					  start)  	start;;
					  stop)		stop;;
					  *)  		echo "Usage: \$0 {start|stop}"
					esac
				_EOF_
				sudo chmod 755 "$INITSCRIPT"
				if [[ -d "/etc/rc.d" ]]; then
					sudo ln -s "$INITSCRIPT" "/etc/rc.d/"
				fi
				doCreateLogRotate
				if [[ -e "$INITSCRIPT" ]]; then
					sudo update-rc.d "$SCRIPTNAME" defaults
					echo "Startup script created."
					echo "You can start and stop the service anytime with sudo service $SCRIPTNAME start|stop"
					echo "Do you want to start the $SCRIPTNAME service now? (Y/n)"
					read -r -s -n 1 inkey
					case $inkey in
						("Y"|"y"|"")	sudo service "$SCRIPTNAME" start;;
						(*)				echo "Reboot for changes to take effect.";;
					esac
				else
					echo "Could not create startup script."
					doExit 21
				fi
			else
				sudoFail
			fi
		else
			echo "Startup service $INITSCRIPT already exists. Cannot create startup service."
			echo "To avoid this, run $THISSCRIPT setup --config=\"$CONFFILE\" and change the default script name"
		fi
	else
		echo "Sorry. Debian based distros only. If you want to code init.d scripts for your distro, get in touch."
	fi
}

doDestroyStartupScript()
{
	if $DEBUG; then echo "doDestroyStartupScript"; fi
	echo "We need to use sudo to remove init.d scripts. Please enter your password if asked."
	if (sudo true); then
		#First stop the service
		sudo "$INITSCRIPT" stop
		#Okay, now we can remove it.
		sudo update-rc.d -f \"$SCRIPTNAME\" remove
		#Now remove the init.d script file.
		echo "Removing startup script $INITSCRIPT."
		sudo rm "$INITSCRIPT" > /dev/null 2>&1
		a="/etc/rc.d/$(basename $INITSCRIPT)"
		if [[ -e "$a" ]]; then
			sudo rm "$a" > /dev/null/2>&1
		fi
		if [[ ! -e "$INITSCRIPT" ]] && [[ ! -e "$a" ]]; then
			echo "Startup script removed."
		else
			echo "Could not remove startup script."
			doExit 22
		fi
	else
		sudoFail
	fi
}

doInit()
{
	if $DEBUG; then echo "doInit \"$@\""; fi
	trap killed SIGINT SIGTERM SIGHUP

	VERSION="2.1.2"
	THISSCRIPT=$(which "$0")
	VERSIONURL="https://github.com/hp6000x/backup.sh/raw/master/VERSION"
	SCRIPTURL="https://github.com/hp6000x/backup.sh/raw/master/backup.sh"
	verbose=false
	justcreated=false
	isBackingUp=false
	isSettingUp=false
	isDaemonMode=false
	isSleeping=false

	defCONFFILE="/etc/hp6000_backup.conf"
#	defCONFFILE="/etc/hp6000_backup_$VERSION.conf"

	#scan arguments for config file
	idx=0
	target=0
	CONFFILE=""
	for i in "$@"; do #search through all the arguments passed to doInit
		idx=$((idx+1))
		if [[ "${i:0:9}" = "--config=" ]]; then #and see if one starts with --config=
			CONFFILE=${i#*=} # if we find it, set CONFFILE to the rest of the argument
		elif [[ "$i" = "--config" ]]; then #how about if the whole argument is --config?
			target=$((idx+1)) # next argument is the value we want, so set the target to catch it next time through the loop
		elif [[ "$idx" = "$target" ]]; then #hit the target set by the previous argument
			CONFFILE="$i" # so set CONFFILE to the current argument
		fi
	done

	if [[ -z "$CONFFILE" ]]; then
		CONFFILE="$defCONFFILE"
	fi
	
	doLoadConfig
	getArguments $@

	#Check the backup sources list for invalid folder names
	tempstring=""
	if [[ -n "$BACKUPSRC" ]]; then #do we have folders to back up?
		for backupfolder in $BACKUPSRC; do #if so, iterate through the list.
			if [[ -d "$backupfolder" ]]; then #does the specified directory exist?
				if [[ -n "$tempstring" ]]; then #if so, does the temp string have anything in it?
					tempstring="$tempstring $backupfolder" #if so, add the directory to the string
				else #otherwise, initialise the string with the directory
					tempstring="$backupfolder"
				fi
			else # if the specified directory does not exist, display a message
				echo "Source folder $backupfolder does not exist. Please edit $CONFFILE" >&2
			fi
		done
		BACKUPSRC="$tempstring" # Change sources list to verified sources list
	fi
	if [[ -z "$BACKUPSRC" ]]; then #if no verified source directories, display a message and exit
		if [[ "$CONFFILE" != "$defCONFFILE" ]]; then
			x="setup --config=\"$CONFFILE\""
		else
			x="setup"
		fi
		echo "No backup folders specified in $CONFFILE. Exiting." >&2
		echo "Run " >&2
		echo "	$THISSCRIPT $x" >&2 
		echo "to reconfigure." >&2
		doExit 2
	fi
}

doMain()
{
	if $DEBUG; then echo "doMain. Command is: $command. Verbose mode: $verbose"; fi
	case $command in
		("e"|"enable")				doEnableBackups;;
		("d"|"disable")				doDisableBackups;;
		("daemon")					if [[ "$(/usr/bin/id -u)" = "0" ]]; then
										daemonMode
									else
										echo "Not running as root. Exiting"
										doExit 5
									fi;;
		("stop")					if [[ "$(/usr/bin/id -u)" = "0" ]]; then
										killDaemon
									else
										echo "Not running as root. Exiting"
										doExit 5
									fi;;
		("c"|"create")				doCreateStartupScript;;
		("y"|"destroy")				doDestroyStartupScript;;
		("r"|"run")					if [[ "$(/usr/bin/id -u)" = "0" ]]; then
										if [[ ! -z "$DEVICEURI" ]]; then #is the backup device connected?
											doInitBackup
											if doMountVolume; then
												isBackingUp=true
												doBackup
											fi
										else
											echo "Backup volume not connected at $(date)" >&2
											doExit 16
										fi
									else
										echo "Not running as root. Exiting." >&2
										doExit 5
									fi;;
		("u"|"update")				doUpdateScript;;
		("s"|"setup")				doReconfig;;
		("h"|"help"	)				displayInfo;;
		(*)							echo "Unrecognised command: $command. Type $THISSCRIPT help for help"
									doExit 20;;
	esac
}

doDone()
{
	if $DEBUG; then echo "doDone"; fi
	if $isBackingUp; then
		echo "Backup finished at $(date) $resultstring errors" 
		isBackingUp=false #Finished backing up
		if $UNMOUNTAFTER; then
			doUnmountVolume
		fi
	fi
}

#At last, we come to the beginning.
doInit $@
doMain
doDone
