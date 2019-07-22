#!/bin/bash
#backup.sh v2
#this time with functions, and configs!
#
#CHANGELOG
#
#	v2.0		- Added config files, changed order of operation, split code into functions, added update and reconfiguration options, generally tidied up and improved code, fixed some bugs
#	v1 to v1.8	- Original backup.sh, improved over time
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

VERSION="2.0"
THISSCRIPT=$(which "$0")
VERSIONURL="https://github.com/hp6000x/backup.sh/raw/master/VERSION"
SCRIPTURL="https://github.com/hp6000x/backup.sh/raw/master/backup.sh"
defCONFFILE="/etc/hp6000_backup.conf"
isBackingUp=false
verbose=false
DEBUG=false

#call me when backup fails :-)
errorexit() {
	if $DEBUG; then echo "errorexit \"$1\" \"$2\""; fi
	echo "Backup failed at $(date)" >&2
	exit $1
}

#output time and text, for logging
echotd() {
	if $DEBUG; then echo "echotd \"$@\""; fi
	echo "[$(date +%T)]" "$@"
}

#trap shutdown and termination signals, contains a super secret easter egg. Are you quick enough?
killed() {
	if $DEBUG; then 
		if $isBackingUp; then
			echo "Received SIGINT, SIGTERM or SIGHUP at $(date)"
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
	else
		echo "Aborting"
	fi
	exit 1
}

#compare two version numbers using sort. Returns true if first value is greater than the second.
version_gt()
{
	if $DEBUG; then echo "version_gt \"$1\" \"$2\""; fi
	test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

#echo text redirected to the temporary config file
configEcho()
{
	if $DEBUG; then echo "configEcho \"$1\""; fi
	echo "$1" >> "$tmpname" 
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
#Coming in version 2.1
#	echo "	daemon		Sit in daemon mode, waiting for UUID to connect, then back up, wait for disconnect and repeat ad infinitum."
#	echo "				This command is meant to be used as a startup job in your Desktop environment. No logging occurs in daemon mode."
#	echo "	[c]reate	Create init.d script to launch daemon mode at startup."
#	echo "	destro[y]	Remove init.d script which launches daemon mode at startup
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
	defBACKUPROOT="/mnt/archive"
	defBACKUPDIR="backups"
	defBACKUPSRC="/home"
	defEXCLUDES=".cache"
	defSCRIPTNAME="backupv2"
	defRSYNCCMD="$(which rsync) -aAXogu --delete --ignore-errors"
	defUNMOUNTAFTER=true
}

doCreateConfig()
{
	if $DEBUG; then echo "doCreateConfig"; fi
	echo "Creating new config file at $CONFFILE."
	#First create a temporary config file
	tmpname="/tmp/$defSCRIPTNAME-config"
	if [[ -e "$tmpname" ]]; then
	  rm "$tmpname"
	fi
	touch "$tmpname" > /dev/null 2>&1
	#Get the UUID of the backup volume
	echo "Please connect your backup device now and hit ENTER"
	echo "If it isn't formatted and ready for use, you'll need to take care of that before you continue."
	echo "If it's already connected, unmount and disconnect it, then reconnect"
	read dummy
	UUID="null"
	while ! (blkid | grep -q "$UUID"); do
		clear
		blkid
		idstr=($(blkid | tail -n 1)) #store the last line of blkid's output in an array
		a="${idstr[2]#*=}" #get everything after the "=" from the third item in the array
		a="${a#\"}" #strip out the leading...
		defUUID="${a%\"}" #...and trailing quotes
		echo
		echo "This is a list of attached filesystems. Please enter the UUID of your backup device."
		echo "Hit ENTER for $defUUID, otherwise copy and paste the UUID you want and hit ENTER."
		read -r UUID
		if [[ -z "$UUID" ]]; then
			UUID="$defUUID"
		fi
		if (blkid | grep -q "$UUID"); then
			configEcho "UUID=\"$UUID\""
		else
			echo "Couldn't find UUID $UUID in the device list. Please hit ENTER to try again."
			read dummy
		fi
	done
	#Write the part which gets the device URI
	configEcho "a=(\$(blkid | grep \$UUID))" #search block ids for backup device UUID and place device info into an array
	configEcho "DEVICEURI=\${a[0]::-1}" #first item in the array, minus the trailing ":" is the uri of the device with the matching UUID
	configEcho "unset a"
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
	echo "Default is $defSCRIPTNAME"
	read -r SCRIPTNAME
	if [[ -z "$SCRIPTNAME" ]]; then
		SCRIPTNAME="$defSCRIPTNAME"
	fi
	configEcho "SCRIPTNAME=\"$SCRIPTNAME\""
	#Write the part which sets BACKUPLOG, SCRIPTFILE and LOGCONFIG
	configEcho "BACKUPLOG=\"/var/log/\$SCRIPTNAME.log\""
	configEcho "SCRIPTFILE=\"/etc/cron.daily/\$SCRIPTNAME\""
	configEcho "LOGCONFIG=\"/etc/logrotate.d/\$SCRIPTNAME\""
	#Get rsync command options RSYNCCMD
	echo "Please enter the default rsync command line and press ENTER. It's highly recommended you stick to the default here."
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
	else
		rm "$CONFFILE.tmpxyz" #otherwise, remove the temp file we created
		mvcmd="mv" #no sudo needed
	fi
	$mvcmd "$tmpname" "$CONFFILE" #move the temp config file to CONFFILE
	if [[ -e "$CONFFILE" ]]; then
		echo "Config file $CONFFILE created successfully."
	else
		echo "Failed to create config file $CONFFILE."
		exit 18
	fi
}

doLoadConfig()
{
	if $DEBUG; then echo "doLoadConfig"; fi
	if [[ ! -e "$CONFFILE" ]]; then #is the config file missing?
		setDefaults
		doCreateConfig
	fi
	. "$CONFFILE" #execute config file to set config options	
}

getArguments()
{
	if $DEBUG; then echo "getArguments \"$@\""; fi
	command="$1"
	if [[ -z "$command" ]]; then
		displayInfo
	elif [[ "${command:0:1}" = "-" ]]; then
		echo "Unrecognised command: $command. Type $THISSCRIPT help for help"
		exit 20
	fi
	shift
	verbose=false
	while [[ ! -z "$1" ]]; do
		i="$1"
		if [[ "${i:0:8}" != "--config" ]]; then #we've already processed --config, let's just process everything else
			case "$i" in
				("-v")			verbose=true;;
				("-h"|"--help")	displayInfo;;
				(*)				echo "Unknown option $i. Type $THISSCRIPT help for help"; exit 9;;
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
		echo "Failed to get sudo. Exiting."
		exit 19
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
			  echo "Log created: \$(date)" > "$BACKUPLOG"
			fi
			echo >> "$BACKUPLOG"
			$nicebin -n20 "$THISSCRIPT" $parm >> "$BACKUPLOG" 2>&1
		_EOF_
		if [[ -a "$SCRIPTFILE" ]]; then
			sudo chmod a+x "$SCRIPTFILE" #make the launcher script executable
			echo "Finished."
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
				exit 14
			fi
		else
			echo "Failed to create launcher at $SCRIPTFILE." >&2
			exit 3
		fi
	else
		echo "Package logrotate not installed. Please install it from the repository and run the install again."
		exit 13
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
		exit $exitval
	fi

}

doMountVolume()
{
	if $DEBUG; then echo "doMountVolume"; fi
	#Creating the mount point
	a=($(lsblk | grep q "$BACKUPROOT" > /dev/null 2>&1)) #search output of lsblk for BACKUPROOT and save results in an array
	if [[ ! -d "$BACKUPROOT" ]]; then # Does the mount point already exist?
		echotd "Creating backup volume mount point..."  # if not, go ahead and create it
		if ! (mkdir -p "$BACKUPROOT" > /dev/null 2>&1); then #create mountpoint and check for success
			# If mount point creation fails, display a message then exit
			echotd "Could not create mount point: $BACKUPROOT. Exiting." >&2
			errorexit 4
		fi
	elif [[ ! -z "${a[6]}" ]]; then #if the mountpoint exists, and the output of our earlier search is not empty, something is mounted there
		b=${a[0]:-4} #last four chars of device URI for device mounted at BACKUPROOT. Device URI is in first element of array "a" set earlier
		c=${DEVICEURI:-4} #last four chars of our backup device URI
		if [[ "$b" != "$c" ]]; then #  If BACKUPROOT's device URI and DEVICEURI do not match, something else is mounted at BACKUPROOT
			echotd "Something else mounted at $BACKUPROOT. Unmounting"
			if ! (umount "$BACKUPROOT" > /dev/null 2>&1); then #unmount it and check for success
				#failed to unmount, so display a message and exit
				echotd "Could not unmount $BACKUPROOT. Exiting."
				errorexit 17
			fi
		fi
	fi 

	#Mounting the backup volume
	if ! (lsblk | grep -q "$BACKUPROOT" > /dev/null); then #If nothing is mounted to BACKUPROOT
		a=($(lsblk -l | grep "${DEVICEURI:(-4)}")) #search all block devices, for last 4 chars of uri $DEVICEURI, and put info into an array
		backupmounted=${a[6]} # get the 7th item from the array, it's the mountpoint of the backup volume if there is one
		unset a
		if [[ -n "$backupmounted" ]]; then #if the volume has a mount point, it is mounted, so...
			echotd "Backup volume with UUID $UUID mounted elsewhere. Unmounting"
			if ! (umount "$DEVICEURI" > /dev/null 2>&1); then #unmount it and check for success
				# Failed to unmount, so display message and exit
				echotd "Could not unmount backup volume $DEVICEURI. Exiting" >&2
				echotd "$backupmounted" >&2
				errorexit 10
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
					errorexit 14
				fi
			fi
		else #If mount fails, attempt to mount by device address
			echotd "Could not mount device with UUID $UUID to $BACKUPROOT. Attempting to mount by URI $DEVICEURI" 
			if (mount "$DEVICEURI" "$BACKUPROOT" > /dev/null 2>&1); then # Mount backup volume by device URI and check for success
				echotd "Backup volume mounted by device URI successfully." 
			else #If mount by URI fails, add message to log and exit
				echotd "Could not mount device with URI $DEVICEURI. Exiting." >&2
				errorexit 11
			fi
		fi
	fi
}

doUnmountVolume()
{
	if $DEBUG; then echo "doUnmountVolume"; fi
	#Unmount the backup volume
	echotd "Unmounting backup volume" 
	sleep 10 # wait 10 seconds before unmounting, just in case there's write caching involved
	if (umount "$BACKUPROOT" > /dev/null 2>&1); then # unmount the backup volume and check for success
		echotd "Backup volume unmounted successfully" 
	else #Unmount failed
		echotd "Could not unmount backup volume at $BACKUPROOT" >&2
		echo "Backup finished at $(date) with errors" 
		exit 10
	fi

	#Removing the mount point
	if [[ -d "$BACKUPROOT" ]]; then #Does the mount point exist?
		if (rmdir "$BACKUPROOT" > /dev/null 2>&1); then  #If so, remove it and check for success
			echotd "Mount point removed successfully" 
		else 
			echotd "Could not remove mount point $BACKUPROOT" >&2 # It failed, so output fail message
			echo "Backup finished at $(date) with errors" 
			exit 12 
		fi
	fi
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
		if version_gt "$curVersion" "$VERSION"; then # how to test $curVersion -gt $VERSION with decimals
			echo "New version $curVersion available. You are on $VERSION. Hit ENTER to update or CTRL-C to abort."
			if (read dummy); then
				if (wget -q "$SCRIPTURL" > /dev/null 2>&1); then #get the latest release of backup.sh from github
					if [[ -e "$THISSCRIPT.bak" ]]; then
						rm "$THISSCRIPT.bak" #remove old script backup
					fi
					mv "$THISSCRIPT" "$THISSCRIPT.bak" #back up current script
					chmod 755 "backup.sh" #make the new script executable
					mv "backup.sh" "$THISSCRIPT" #move the new script to the location and name of the current script
					echo "Updated backup script. Check what's changed by opening $THISSCRIPT for editing, or going to https://github.com/hp6000x/backup.sh"
					popd > /dev/null #return to previous directory
					exit 0
				else #download failed
					echo "Could not get new script file from $SCRIPTURL. Is the repository still there?"
				fi
			else #update aborted with CTRL-C
				echo "Version unchanged."
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

doReconfig()
{
	if $DEBUG; then echo "doReconfig"; fi

	if ! (touch "$CONFFILE.tmpxyz" > /dev/null 2>&1); then #test for write access to the directory where CONFFILE is stored
		echo "We may need to use sudo to manipulate the config file. Please enter your password if asked."
		if ! (sudo true); then
			echo "Failed to get sudo. Exiting."
			exit 19
		fi
		rmcmd="sudo rm"
		mvcmd="sudo mv"
	else
		rm "$CONFFILE.tmpxyz"
		rmcmd="rm"
		mvcmd="mv"
	fi

	if [[ -e "$CONFFILE.bak" ]]; then
		$rmcmd "$CONFFILE.bak"
	fi
	$mvcmd "$CONFFILE" "$CONFFILE.bak"
	if [[ -e "$CONFFILE.bak" ]]; then
		echo "Old config file saved to $CONFFILE.bak"
	else
		echo "Could not create backup of config file. Hit ENTER to proceed anyway, CTRL-C to cancel"
		read dummy
	fi
	
	defBACKUPROOT="$BACKUPROOT"
	defBACKUPDIR="$BACKUPDIR"
	defBACKUPSRC="$BACKUPSRC"
	defEXCLUDES="$EXCLUDES"
	defSCRIPTNAME="$SCRIPTNAME"
	defRSYNCCMD="$RSYNCCMD"
	defUNMOUNTAFTER=$UNMOUNTAFTER
	
	doCreateConfig
}

doInit()
{
	if $DEBUG; then echo "doInit \"$@\""; fi
	trap killed SIGINT SIGTERM SIGHUP
	#scan arguments for config file
	idx=0
	target=0
	CONFFILE=""
	for i in "$@"; do #search through all the arguments passed to doInit
		idx=$((idx+1))
		if [[ "${i:0:9}" = "--config=" ]]; then #and see if one starts with --config=
			CONFFILE=${i#*=} # if we find it, set CONFFILE to the rest of the argument
		elif [[ "${i:0:8}" = "--config" ]]; then #how about if it starts with just --config
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
		exit 2
	fi
}

doMain()
{
	if $DEBUG; then echo "doMain. Command is: $command. Verbose mode: $verbose"; fi
	case $command in
		("e"|"enable")				doEnableBackups;;
		("d"|"disable")				doDisableBackups;;
#		("daemon")					daemonMode;;
#		("c"|"create")				doCreateStartupScript;;
#		("y"|"destroy")				doDestroyStartupScript;;
		("r"|"run")					if [[ "$(/usr/bin/id -u)" = "0" ]]; then
										if [[ ! -z "$DEVICEURI" ]]; then #is the backup device connected?
											echo "Starting backup: $(date)"
											if $DEBUG;
												then echo "Debugging v$VERSION"
											fi
											echo "Backing up $BACKUPSRC to $BACKUPROOT/$BACKUPDIR"
											doMountVolume
											isBackingUp=true
											doBackup
										else
											echo "Backup volume not connected at $(date)" >&2
											exit 16
										fi
									else
										echo "Not running as root. Exiting." >&2
										exit 5
									fi;;
		("u"|"update")				doUpdateScript;;
		("s"|"setup")				doReconfig;;
		("h"|"help"	)				displayInfo;;
		(*)							echo "Unrecognised command: $command. Type $THISSCRIPT help for help"
									exit 20;;
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

doInit $@
doMain
doDone
