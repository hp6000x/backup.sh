#!/bin/bash
#backup.sh v2
#this time with functions, and configs!
#certified demonic!
#
#CHANGELOG
#
#	v2.1.6	(Aug 19)	Found a few errant lines that had gotten themselves turned around. Moved them to where they belong.
#	v2.1.5	(Aug 19)	Found more opportunities for tidying. Caught a new bug.
#	v2.1.4	(Aug 19)	More tweaks and tidies. Not sure if there are any bugs left. Don't think any escaped the great sweep of 2.1.3
#	v2.1.3	(Aug 19)	Tweaks, changes to output, moved some functions, bug fixes, more code tidying. Added local vars, changed setup to populate default vars when getting input.
#	v2.1.2	(Aug 19)	Fixed an issue with blkid
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
#24 - rsync not installed

#important settings get loaded before anything else happens.
DEBUG=false
VERSION="2.1.6"
THISSCRIPT=$(which "$0")
VERSIONURL="https://raw.githubusercontent.com/hp6000x/backup.sh/master/VERSION"
SCRIPTURL="https://raw.githubusercontent.com/hp6000x/backup.sh/master/backup.sh"
PIDFILE="/tmp/BACKUP_PID"

#output debug message only if in debug mode
echoDebug() 
{
	if $DEBUG; then echo "[DEBUG] $1"; fi
}

#Exit the script unless we're in daemon mode, then just report an exit condition.
doExit()
{
	echoDebug "doExit $1"
	if $isDaemonMode; then
		echo "Exit condition reached. Error code $1"
	else
		exit $1
	fi
}

#Exit with an error message. Format is doExitMessage errnum "error message"
doExitMessage()
{
	echoDebug "doExitMessage $1 \"$2\""
	echo "$2" >&2
	doExit "$1"
}

doSleep()
{
	echoDebug "doSleep $1"
	isSleeping=true
	sleep $1
	isSleeping=false
}

#call me when backup fails :-)
backupFail()
{
	echoDebug "backupFail \"$1\""
	doExitMessage $1 "Backup failed at $(date)"
}

#output time and text, for logging
echotd()
{
	echoDebug "echotd \"$@\""
	echo "[$(date +%T)]" "$@"
}

#trap shutdown and termination signals, contains a super secret easter egg. Are you quick enough?
killed() {
	local sharpshooter
	local a
	echotd "Received SIGINT, SIGTERM or SIGHUP"
	if $DEBUG; then 
		sharpshooter=true
		for a in $isBackingUp $isSettingUp $isDaemonMode $isSleeping; do # yes, using a || b || c || d would be more efficient, but I like this way: it fits with the sharpshooter ethos, pickin' 'em off one by one
			$a && sharpshooter=false
		done
		if $sharpshooter ; then
			echo "Shot through the heart, and you're to blame. Darlin' you give love..."
			sleep 3s
			echo "...a bad name."
			echo
			echo "Seriously, that was some quick shootin', Tex. You've earned your \"CTRL-C Cowboy\" badge!"
			echo
			echo "  ____ _____ ____  _           ____    ____              _                 _ "
			echo " / ___|_   _|  _ \| |         / ___|  / ___|_____      _| |__   ___  _   _| |"
			echo "| |     | | | |_) | |   _____| |     | |   / _ \ \ /\ / / '_ \ / _ \| | | | |"
			echo "| |___  | | |  _ <| |__|_____| |___  | |__| (_) \ V  V /| |_) | (_) | |_| |_|"
			echo " \____| |_| |_| \_\_____|     \____|  \____\___/ \_/\_/ |_.__/ \___/ \__, (_)"
			echo "                                                                     |___/   "
			echo
		fi
	else
		if $isBackingUp; then
			echo "Backup aborted at $(date)" >&2
		fi
		if $isDaemonMode; then
			echo "Stopping daemon at $(date)"
			if [[ -e "$pidfile" ]]; then 
				rm "$PIDFILE"
				doSleep 30s
			fi
			exit 0
		elif $isSettingUp; then
			echo "Setup aborted."
			if [[ -e "$tmpname" ]]; then
				rm "$tmpname"
			fi
		else
			echo "Aborting"
		fi
	fi
	exit 1
}

#compare two version numbers using sort. Returns true if first value is greater than the second.
isGreater()
{
	test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

#are we running as root user? return true if we are
isRoot()
{
	test "$(/usr/bin/id -u)" = "0"
}

#echo text redirected to the temporary config file
configEcho()
{
	echoDebug "configEcho \"$1\""
	echo "$1" >> "$tmpname" 
}

sudoFail()
{
	echoDebug "sudoFail"
	doExitMessage 19 "Failed to get sudo credentials. Exiting."
}

rootFail()
{
	echoDebug "rootFail"
	doExitMessage 5 "Not running as root. Exiting."
}

getParameters()
{
	if [[ "$CONFFILE" != "$defCONFFILE" ]]; then
		echo "setup --config=\"$CONFFILE\""
	else
		echo "setup"
	fi
}

getSudoPassword()
{
	echoDebug "getSudoPassword"
	if ! $alreadyasked; then
		echo "We need to use sudo for this. Please enter your password if asked."
	fi
	isSettingUp=true
	if ! (sudo true); then
		sudoFail
	else
		alreadyasked=true
	fi
	isSettingUp=false
}

getAvailVersion()
{
	local tmpname
	tmpname="$(mktemp)"
	if (wget -q -O "$tmpname" "$VERSIONURL" > /dev/null 2>&1); then #get latest release version number from github 
		cat "$tmpname"
		rm "$tmpname" #and tidy up
	fi
}

getProcess()
{
	ps aux | grep "$THISSCRIPT daemon" | grep -v grep | awk '{printf $2F}'
#	pgrep "$THISSCRIPT daemon" # tried this on shellcheck's advice, didn't work, abandoning.
}

waitForEnter()
{
	local dummy
	isSleeping=true
	read -rs dummy
	isSleeping=false
}

displayInfo()
{
	echoDebug "displayInfo \"$1\""
	local showextra
	local command
	command="$1"
	if [[ -z "$command" ]]; then #no command specified, give general help
		echo "backup.sh v$VERSION"
		echo "Mounts backup volume, backs up data, schedules daily backups, optionally unmounts after backup."
		echo "Ideally suited for backing up laptops with external drives when at home and connected."
		echo
		echo "Format is: $THISSCRIPT {command} [options...]"
		echo
		echo "Commands:"
		echo "	[e]nable	Enable the daily automated backup. (Uses sudo)"
		echo "	[d]isable	Disable the daily automated backup. (Uses sudo)"
		echo "	NOTE: Daemon mode is not intended for permanently connected backup devices."
		echo "	[c]reate	Create init.d script to launch daemon mode at startup. (Uses sudo)"
		echo "	destro[y]	Remove init.d script which launches daemon mode at startup. (Uses sudo)"
		echo "	[r]un		Run a backup job. (Must be run as root)"
		echo "	[u]pdate	Checks github for new version and updates as necessary."
		echo "	[s]etup		Create a new config file (either in the default of $defCONFFILE or where specified with --config, may require sudo)."
		echo "	[h]elp		Display this information page."
		echo
		echo "Options:"
		echo "	-v				Give more details when running backups or displaying info"
		echo "	-h, --help			Give more info about a specific command."
		echo "	--config={path to config file}	Use specified config file instead of default."
		echo "	--debug				Run in debug mode."
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
			echo "INITSCRIPT=$INITSCRIPT"
			echo "LOGCONFIG=$LOGCONFIG"
			echo "UNMOUNTAFTER=$UNMOUNTAFTER"
		fi
	else # command specified. give info about that command.
		case $command in
			("e"|"enable")		echo "Create a script file in /etc/cron.daily which runs \"$THISSCRIPT run\" to perform daily backups. Sudo privileges are required.";;
			("d"|"disable")		echo "Remove the script file from /etc/cron.daily which performs daily backups. Sudo privileges are required.";;
			("c"|"create")		echo "Create a startup script in /etc/init.d which runs this script in daemon mode every time the computer starts, and waits for a backup device to connect. Sudo privileges are required.";;
			("d"|"destroy")		echo "Remove the startup script from /etc/init.d which performs daemon mode backups. Sudo privileges are required.";;
			("r"|"run")			echo "Mount the backup volume, perform an rsync backup and optionally unmount the volume depending on your configs. Must be run as root.";;
			("u"|"update")		echo "Checks the VERSION file stored at the github repository. If a new version is available, this will download the new version and backup the old.";;
			("s"|"setup")		echo "Allows you to change settings in the config file (either default or specified). Use this rather than editing the file directly. Sudo privileges may be required if you don't have write access to the config file location.";;
			(*)					echo "No information found for $command. Please type \"$THISSCRIPT help\" for help.";;
		esac
	fi
}

setDefaults()
{
	echoDebug "setDefaults"
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
	echoDebug "doCreateConfig"
	isSettingUp=true
	local inkey
	local parm
	local a
	local mvcmd
	local rmcmd
	echo "Creating new config file at $CONFFILE."
	if [[ -z "$(blkid)" ]]; then
		echo "blkid has not been initialised. We need to run sudo blkid to initialise it."
		getSudoPassword
		sudo blkid > /dev/null 2>&1
		echo "Done."
		echo
	fi
	#First create a temporary config file
	tmpname="$(mktemp)"
	configEcho "# backup.sh $VERSION configuration file"
	configEcho "# Created $(date) by $USER"
	parm=$(getParameters)
	configEcho "# Do not edit manually, use $THISSCRIPT $parm to configure."
	configEcho ""
	#Get the UUID of the backup volume
	echo "Please connect your backup device now and hit ENTER"
	echo "If it isn't formatted and ready for use, you'll need to take care of that before you continue."
	echo "If it's already connected, unmount and disconnect it, then reconnect"
	waitForEnter
	echo "Waiting ten seconds for file system shenanigans to sort themselves out..."
	doSleep 10s
	if [[ "$defUUID" = "null" ]]; then #if we don't already have a UUID to use as default, get the last mounted device's UUID
		a=$(blkid | tail -n 1 | awk '{printf $3F}') #store the third field from the last line of blkid's output in a
		a="${a#*=}" #get everything after the "=" from a
		a="${a#\"}" #strip out the leading...
		defUUID="${a%\"}" #...and trailing quotes
	fi
	UUID="null"
	#while ! (blkid | grep -q "$UUID"); do
	echoDebug "UUID=$UUID defUUID=$defUUID"
	clear
	blkid | grep -v "/dev/loop"
	echo
	echo "This is a list of attached filesystems. Please enter the UUID of your backup device."
	echo "If you do not see your device listed, and it's definitely connected, abort this script"
	echo "with CTRL-C and run it again."
	echo
	echo "Copy and paste the UUID you want if it's different from that suggested and hit ENTER."
	read -rei "$defUUID" UUID
	configEcho "UUID=\"$UUID\""
	#Get the mount point BACKUPROOT
	echo "Please enter the mount point for the backup volume and press ENTER."
	read -rei "$defBACKUPROOT" BACKUPROOT
	configEcho "BACKUPROOT=\"$BACKUPROOT\""
	#Get the backup folder BACKUPDIR
	echo "Please enter the backup subdirectory name and press ENTER"
	read -rei "$defBACKUPDIR" BACKUPDIR
	configEcho "BACKUPDIR=\"$BACKUPDIR\""
	#Get the source folders BACKUPSRC
	echo "Please enter a space-separated list of folders to back up, and press ENTER."
	read -rei "$defBACKUPSRC" BACKUPSRC
	configEcho "BACKUPSRC=\"$BACKUPSRC\""
	#Get exclude list EXCLUDES
	echo "Please enter a space-separated list of keywords to exclude from the folder list, and press ENTER."
	read -rei "$defEXCLUDES" EXCLUDES
	configEcho "EXCLUDES=\"$EXCLUDES\""
	#Get script name SCRIPTNAME
	echo "Please enter the default script name and press ENTER. This will be used to name the log and script files, and the logrotate config file."
	echo "Warning: Things won't work properly if you add an extension to the filename. So, no full stops, just the file name."
	read -rei "$defSCRIPTNAME" SCRIPTNAME
	configEcho "SCRIPTNAME=\"$SCRIPTNAME\""
	#Get rsync command options RSYNCCMD
	echo "Please enter the command line used to execute rsync and press ENTER. It's highly recommended you stick to the default here."
	read -rei "$defRSYNCCMD" RSYNCCMD
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
	#okay, now to create the actual config file
	if [[ ! -w $(dirname "$CONFFILE") ]]; then # if the config folder directory is not writeable by us
		echo "Writing to config file"
		getSudoPassword
		mvcmd="sudo mv" #we need sudo to do the move
		rmcmd="sudo rm"
	else
		mvcmd="mv" #no sudo needed
		rmcmd="rm"
	fi
	$rmcmd "$CONFFILE" #remove the old config file. We've already backed it up, so it's fine.
	$mvcmd "$tmpname" "$CONFFILE" #move the temp config file to CONFFILE
	if [[ -e "$CONFFILE" ]]; then
		echo "Config file $CONFFILE created successfully."
		justcreated=true
	else
		doExitMessage 18  "Failed to create config file $CONFFILE."
	fi
	isSettingUp=false
}

doReconfig()
{
	echoDebug "doReconfig"
	local rmcmd
	local cpcmd
	local confdir
	confdir="$(dirname $CONFFILE)"
	echo "Writing to $confdir"
	if [[ ! -w "$confdir" ]]; then #test for write access to the directory where CONFFILE is stored
		getSudoPassword
		rmcmd="sudo rm"
		cpcmd="sudo cp"
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
			echo "Could not create backup of config file. Hit ENTER to proceed anyway, CTRL-C to cancel"
			waitForEnter
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
	blkid | grep $UUID | cut -d: -f1 # search output of blkid for UUID. First field, delimited by ":" is device URI
}

doLoadConfig()
{
	echoDebug "doLoadConfig"
	local v
	
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
	
	#Check config file version
	v=$(head -n 1 "$CONFFILE" | awk '{printf $3F}') #Get the third field from the first line of the config file. This is the version of backup.sh used to create the config file
	if [[ -z "$v" ]]; then #Version 2.0 has no version number, so if none is present, assume 2.0 
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
	echoDebug "getArguments \"$@\""
	command=$1
	if [[ -z "$command" ]]; then
		doExitMessage 9 "Usage: $THISSCRIPT command [options]"
	elif [[ "${command:0:1}" = "-" ]]; then
		doExitMessage 20 "Unrecognised command: $command. Type $THISSCRIPT help for help"
	fi
	shift
	while [[ ! -z "$1" ]]; do
		i="$1"
		if [[ "${i:0:8}" != "--config" ]]; then #we've already processed --config, let's just process everything else
			case "$i" in
				("-v")			verbose=true;;
				("-h"|"--help")	displayInfo $command; doExit 0;;
				("--debug")		DEBUG=true;;
				(*)				doExitMessage 9 "Unknown option $i. Type $THISSCRIPT help for help";;
			esac
		fi
		shift
	done
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
		doExitMessage 14 "Failed to create logrotate config at $LOGCONFIG."
	fi
}

doEnableBackups()
{
	echoDebug "doEnableBackups"
	local parm
	local nicebin
	echo "Enabling daily rsync backups"
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
			doExitMessage 3 "Failed to create launcher at $SCRIPTFILE."
		fi
	else
		doExitMessage 13 "Package logrotate not installed. Please install it from the repository and run this script again."
	fi
}

doDisableBackups()
{
	echoDebug "doDisableBackups"
	local exitval
	echo "Disabling daily rsync backups"
	getSudoPassword
	#Removing the launcher script
	exitval=0
	if [[ -a "$SCRIPTFILE" ]]; then # Does the script launcher exist?
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
		doExitMessage $exitval "Exiting due to file removal errors."
		return $exitval
	fi

}

doMountVolume()
{
	echoDebug "doMountVolume"
	local a
	local backupmounted
	if [[ -z "$DEVICEURI" ]]; then
		DEVICEURI="$(getURIFromUUID)"
	fi
	#Creating the mount point
	if [[ ! -d "$BACKUPROOT" ]]; then # Does the mount point already exist?
		echotd "Creating backup volume mount point..."  # if not, go ahead and create it
		if ! (mkdir -p "$BACKUPROOT" > /dev/null 2>&1); then #create mountpoint and check for success
			# If mount point creation fails, display a message then exit
			echotd "Could not create mount point: $BACKUPROOT. Exiting." >&2
			backupFail 4
			return 4
		fi
	elif [[ ! -z $(lsblk -lp | grep $DEVICEURI | awk '{print $NF}') ]]; then #if the mountpoint exists, and a search for DEVICEURI in lsblk -lp is nonzero, something is mounted at the mount point
		a=$(lsblk -lp | grep $BACKUPROOT | awk '{printf $1F}') # get info about whatever is mounted at BACKUPROOT
		a=${a/ */} #everything before the first space in that info is the URI of the device
		if [[ "$a" != "$DEVICEURI" ]]; then #  If BACKUPROOT's device URI and DEVICEURI do not match, something else is mounted at BACKUPROOT
			echotd "Something else mounted at $BACKUPROOT. Unmounting"
			doSleep 5s #wait for 5 seconds just in case linux is still assimilating this volume :-)
			if ! (umount "$BACKUPROOT" > /dev/null 2>&1); then #unmount it and check for success
				#failed to unmount, so display a message and exit
				echotd "Could not unmount $BACKUPROOT. Exiting."
				backupFail 17
				return 17
			fi
		fi
	fi 

	#Mounting the backup volume
	if ! (lsblk | grep -q "$BACKUPROOT" > /dev/null); then #If nothing is mounted to BACKUPROOT
		backupmounted=$(lsblk -p | grep $DEVICEURI | awk '{print $NF}') #search block devices for DEVICEURI and store mount point in a string
		if [[ -n "$backupmounted" ]]; then #if the volume has a mount point, it is mounted, so...
			echotd "Backup volume $DEVICEURI mounted to $backupmounted. Unmounting"
			doSleep 5s #wait for 5 seconds just in case linux is still assimilating this volume :-)
			if ! (umount "$backupmounted" > /dev/null 2>&1); then #unmount it and check for success
				if ! $isDaemonMode; then #not in daemon mode, exit, in daemon mode, carry on
					# Failed to unmount, so display message and exit
					echotd "Could not unmount backup volume $DEVICEURI. Exiting" >&2
					echotd "$backupmounted" >&2
					backupFail 10
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
					if $UNMOUNTAFTER; then # Are we flagged to auto unmount?
						if (umount "$BACKUPROOT" > /dev/null 2>&1); then # unmount the backup volume and check for success
							echotd "Backup volume unmounted successfully"
						else #Unmount failed
							echotd "Could not unmount backup volume at $BACKUPROOT" >&2
						fi
					fi
					backupFail 14
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
				backupFail 11
				return 11
			fi
		fi
	fi
	return 0
}

doUnmountVolume()
{
	echoDebug "doUnmountVolume"
	#Unmount the backup volume
	echotd "Unmounting backup volume" 
	doSleep 10 # wait 10 seconds before unmounting, just in case there's write caching involved
	if (umount "$BACKUPROOT" > /dev/null 2>&1); then # unmount the backup volume and check for success
		echotd "Backup volume unmounted successfully" 
	else #Unmount failed
		echotd "Could not unmount backup volume at $BACKUPROOT" >&2
		doExitMessage 10 "Backup finished at $(date) with errors" 
	fi

	#Removing the mount point
	if [[ -d "$BACKUPROOT" ]]; then #Does the mount point exist?
		if (rmdir "$BACKUPROOT" > /dev/null 2>&1); then  #If so, remove it and check for success
			echotd "Mount point removed successfully" 
		else 
			echotd "Could not remove mount point $BACKUPROOT" >&2 # It failed, so output fail message
			doExitMessage 12 "Backup finished at $(date) with errors" 
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
	echoDebug "doBackup"
	#Performing the backup
	local errorflag
	local opt
	local sourcedir
	local a
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

doDoneBackup()
{
	echoDebug "doDoneBackup"
	if $isBackingUp; then
		echo "Backup finished at $(date) $resultstring errors" 
		isBackingUp=false #Finished backing up
		if $UNMOUNTAFTER; then
			doUnmountVolume
		fi
	fi
}

doBackupProcess()
{
	doInitBackup
	if doMountVolume; then
		isBackingUp=true
		doBackup
		doDoneBackup
	fi
}

doUpdateScript()
{
	echoDebug "doUpdateScript"
	local gitVersion
	local tmpname
	gitVersion=$(getAvailVersion)
	if isGreater "$gitVersion" "$VERSION"; then 
		echo "Updating $THISSCRIPT to v$gitVersion."
		tmpname="$(mktemp)"
		if (wget -q -O "$tmpname" "$SCRIPTURL" > /dev/null 2>&1); then #get the latest release of backup.sh from github
			if [[ -e "$THISSCRIPT.bak" ]]; then
				rm "$THISSCRIPT.bak" #remove old script backup
			fi
			mv "$THISSCRIPT" "$THISSCRIPT.bak" #back up current script
			chmod 755 "$tmpname" #make the new script executable
			mv "$tmpname" "$THISSCRIPT" #move the new script to the location and name of the current script
			echo "Updated backup script. Check what's changed by opening $THISSCRIPT for editing, or going to https://github.com/hp6000x/backup.sh"
			doExit 0
		else #download failed
			echo "Could not get new script file from $SCRIPTURL. Is the repository still there?"
		fi
	elif [[ "$gitVersion" = "$VERSION" ]]; then
		echo "You are already on the latest version ($VERSION)"
	elif isGreater "$VERSION" "$gitVersion"; then
		echo "Your version: $VERSION. Current version: $gitVersion. Can't wait for release, Mr. Developer."
	elif [[ -z "$gitVersion" ]]; then
		echo "Online version information not found."
	fi
}

daemonEnded()
{
	echo "Stopping daemon at $(date)"
	exit 0
}

daemonMode()
{
	echoDebug "daemonMode"
	isDaemonMode=true
	if [[ ! -e "$PIDFILE" ]]; then
		echo "Starting daemon at $(date)"
		echo $$ > "$PIDFILE"
		while [[ -e "$PIDFILE" ]]; do #loop while PID file exists
			while ! (blkid | grep -q "$UUID"); do #while UUID is not connected
				if $DEBUG; then echotd "Waiting for device."; fi
				doSleep 10s
				if [[ ! -e "$PIDFILE" ]]; then
					daemonEnded
				fi
			done
			doSleep 10s # it takes a few seconds for linux to set up the device after connecting.
			if (blkid | grep -q "$UUID"); then #if UUID is connected
				echoDebug "Device connected. Backing up."
				doBackupProcess
			fi
			while (blkid | grep -q "$UUID"); do #while UUID is connected
				if $DEBUG; then echotd "Waiting for device disconnect."; fi
				doSleep 10s
				if [[ ! -e "$PIDFILE" ]]; then
					daemonEnded
				fi
			done
		done
		daemonEnded
	else
		echo "Daemon already running at $(date)"
	fi
}

killDaemon()
{
	echoDebug "killDaemon"
	local process
	process="$(cat $PIDFILE)"
	if [[ -e "$PIDFILE" ]]; then
		rm "$PIDFILE"
	fi
	echo "Waiting for process to end naturally"
	doSleep 30s
	process=$(getProcess)
	if [[ ! -z "$process" ]]; then
		echo "Killing $process"
	fi
	while [[ ! -z "$process" ]]; do
		kill $process
		doSleep 2s
		process=$(getProcess)
	done
}

doCreateStartupScript()
{
	echoDebug "doCreateStartupScript"
	local inkey
	local opt
	local nicebin
	local parm
	if (which apt > /dev/null); then
		if [[ ! -e "$INITSCRIPT" ]]; then
			echo "Creating startup script $INITSCRIPT."
			getSudoPassword
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
				sudo ln -s "$INITSCRIPT" "/etc/rc.d/$(basename $INITSCRIPT)"
			fi
			doCreateLogRotate
			if [[ -e "$INITSCRIPT" ]]; then
				sudo update-rc.d "$SCRIPTNAME" defaults
				echo "Startup script created."
				echo "You can start and stop the service anytime with sudo service $SCRIPTNAME start|stop"
				echo "Do you want to start the $SCRIPTNAME service now? (Y/n)"
				isSleeping=true
				read -r -s -n 1 inkey
				isSleeping=false
				case $inkey in
					("Y"|"y"|"")	sudo service "$SCRIPTNAME" start;;
					(*)				echo "Reboot for changes to take effect.";;
				esac
			else
				doExitMessage 21 "Could not create startup script."
			fi
		else
			echo "Startup service $INITSCRIPT already exists. Cannot create startup service."
			parm=$(getParameters)
			echo "To avoid this, run $THISSCRIPT $parm and change the default script name"
		fi
	else
		echo "Sorry. Debian based distros only. If you want to code init.d scripts for your distro, get in touch."
	fi
}

doDestroyStartupScript()
{
	echoDebug "doDestroyStartupScript"
	local a
	echo "Destroying startup script."
	getSudoPassword
	#First stop the service
	sudo "$INITSCRIPT" stop
	#Okay, now we can remove it.
	sudo update-rc.d -f \"$SCRIPTNAME\" remove
	#Now remove the init.d script file.
	echo "Removing startup script $INITSCRIPT."
	sudo rm "$INITSCRIPT" > /dev/null 2>&1
	a="/etc/rc.d/$(basename $INITSCRIPT)"
	if [[ -e "$a" ]]; then
		sudo rm "$a" > /dev/null/ 2>&1
	fi
	if [[ ! -e "$INITSCRIPT" ]] && [[ ! -e "$a" ]]; then
		echo "Startup script removed."
	else
		doExitMessage 22 "Could not remove startup script."
	fi
}

doInit()
{
	echoDebug "doInit \"$@\""
	trap killed SIGINT SIGTERM SIGHUP
	local gitVersion
	local idx
	local i
	local target
	local tempstring
	local backupfolder
	local parm
	
	verbose=false
	justcreated=false
	isBackingUp=false
	isSettingUp=false
	isDaemonMode=false
	isSleeping=false
	alreadyasked=false
	
	if ! (which rsync > /dev/null 2>&1); then
		echo "Package rsync not installed. Attempting to install."
		if (which apt); then
			getSudoPassword
			if (sudo apt install rsync); then
				echo "Package rsync installed."
			else
				echo "Could not install rsync. Please install the package yourself."
				exit 24
			fi
		else
			echo "Could not install rsync. Please install the package yourself."
			exit 24
		fi
	fi
	
	gitVersion=$(getAvailVersion)
	if isGreater "$gitVersion" "$VERSION"; then
		echo "New version available. Type \"$THISSCRIPT update\" to get it."
	fi

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
				parm=$(getParameters)
				echo "Source folder $backupfolder does not exist. Please run $THISSCRIPT $parm and correct the list of folders to back up." >&2
			fi
		done
		BACKUPSRC="$tempstring" # Change sources list to verified sources list
	fi
	if [[ -z "$BACKUPSRC" ]]; then #if no verified source directories, display a message and exit
		parm=$(getParameters)
		echo "No backup folders specified in $CONFFILE. Exiting." >&2
		echo "Run " >&2
		echo "	$THISSCRIPT $parm" >&2 
		echo "to reconfigure." >&2
		doExit 2
	fi
}

doMain()
{
	echoDebug "doMain. Command is: $command. Verbose mode: $verbose"
	case $command in
		("e"|"enable")				doEnableBackups;;
		("d"|"disable")				doDisableBackups;;
		("daemon")					if isRoot; then
										daemonMode
									else
										rootFail
									fi;;
		("stop")					if isRoot; then
										killDaemon
									else
										rootFail
									fi;;
		("c"|"create")				doCreateStartupScript;;
		("y"|"destroy")				doDestroyStartupScript;;
		("r"|"run")					if isRoot; then
										if [[ ! -z "$DEVICEURI" ]]; then #is the backup device connected?
											doBackupProcess
										else
											doExitMessage 16 "Backup volume not connected at $(date)"
										fi
									else
										rootFail
									fi;;
		("u"|"update")				doUpdateScript;;
		("s"|"setup")				doReconfig;;
		("h"|"help"	)				displayInfo;;
		(*)							doExitMessage 20 "Unrecognised command: $command. Type $THISSCRIPT help for help";;
	esac
}

#At last, we come to the beginning.
echoDebug "$0 $@"
doInit $@
doMain
