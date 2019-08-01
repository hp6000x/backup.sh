# backup.sh version 2.1

Mounts backup volume, backs up data, schedules daily backups, optionally unmounts after backup.
Now with daemon mode. Just plug in your drive and it backs up almost immediately!
Ideally suited for backing up laptops with external drives when at home and connected.

Format is: 

	backup.sh {command} [options]

Commands:

	[e]nable:	Enable the daily automated backup. (Uses sudo)
	[d]isable:	Disable the daily automated backup. (Uses sudo)
	[c]reate:	Create init.d script to launch daemon mode at startup. (Uses sudo)
	destro[y]:	Remove init.d script which launches daemon mode at startup. (Uses sudo)
	WARNING: Don't use daemon mode if your backup drive is permanently connected!
	[r]un:		Run a backup job. (Must be run as root)
	[u]pdate:	Checks github for new version and updates as necessary.
	[s]etup:	Create a new config file (either in the default place or where specified with --config).
	[h]elp:		Display this information page.

Options:

	-v								Give more details when running backups or displaying info
	--config={path to config file}	Use specified config file instead of default.

Note, if you specify an alternate config which does not exist, you will automatically be taken
through the setup process, just as you are when running this script for the first time.

Second Note, if you are upgrading from v2.0 to v2.1 or later, you will need to run

	backup.sh setup --config={config file}
	
on all your config files, as the config file format has changed. Reconfiguring should be easy, as
the defaults for all the options are derived from the existing config file.

#How do I set it up

Save this script somewhere in your PATH. I have a custom folder (/pub/scripts) which you can mimic
if you like, just don't forget to set the folders to publicly readable with 

	chmod -R 755 /pub

and put it in your PATH by adding the following to your .bashrc file

	PATH="/pub/scripts:$PATH"
	
In the bin folder of your home directory is another good place to put scripts like this. Again, you
need to make sure it's in your PATH. It may be there already. To check, simply type

	echo $PATH
	
As with all my scripts, I'd recommend reading through and understanding this script, and tailoring it
to suit your system before running it for the first time. I take no responsibility for lost data.
This one's quite complex, but it's well commented and if you're using an editor like geany which
makes it easy to jump between functions, it shouldn't be too daunting to get your head round.

The first thing you are going to want to do is configure backup.sh for your system. To do this, run

	backup.sh setup
	
and follow the prompts, either keeping the presented defaults or choosing your own UUID and other settings.

If you want to set up more than one backup job, you'll need to run the command with the --config option.
Just point it to /etc/whatever-you-want-to-call-it.conf and, when setting up, give a different default
script name.

There are three use cases for this script. The first is as an on-demand backup tool. Running

	sudo backup.sh run
	
will, after it has been configured, back up the specified folders to the backup device, if it is connected.
You can add a "-v" to any command to activate verbose mode. This will list all files as they are being
backed up.

The second use case is for daily backups to a permanently connected backup drive. To initiate this, run

	backup.sh enable

with an optional -v. This will schedule a daily anacron job to mount the backup device, run the backup and,
optionally, unmount the device when it's finished.

If you have a problem where you think you may need to restore from your backup sometime soon, it's a good
idea to disable the automated backup with

	backup.sh disable
	
This will remove the scripts which perform the daily anacron job and stop your backups from being overwritten.


The third and final use case is for laptops etc. (only those running Debian-based distros, unfortunately), which
have an external backup device, only occasionally connected. If this is your configuration, and you are running
a Debian-based distro, run

	backup.sh create
	
with an optional -v, and follow the prompts. This will create init.d startup scripts to run backup.sh in daemon
mode, whereby it sits and waits for a device with the correct UUID to be connected, then performs the backup and
optionally unmounts and waits for the device to be disconnected before repeating the process over.

If you want to connect your backup device for reasons other than backing up, such as to do a restore or to
browse the files in the backup, you will need to stop the daemon first. You can do this by typing

	backup.sh destroy
	
This will stop the daemon from running, and remove it from init.d so that it doesn't start automatically at
boot time. Use the aforementioned command to enable it again when you're done browsing, restoring or whatever.

Unfortunately, I have to restrict the create and destroy options to Debian-based systems because I haven't 
learned how to code startup scripts for any other distros yet, and when I do, it will be tricky to test. If
you already know how to code init scripts for other distros, feel free to fork and fill it in yourself. I'd
love to see this functionality available in other distros.

# What's changed?

v2.1

Added daemon mode as well as the ability to create and remove daemon mode startup scripts for debian-based
systems. Sorry I've had to restrict it like that, but that's the only system I currently know how to code
init.d scripts for. I don't even know how much longer this method of starting daemons will be viable, now 
init.d is giving way to systemd. Is this even acheivable without init.d? I don't know.

Added a fun easter egg mini-game. Just have DEBUG set to true and try to CTRL-C while not backing up, 
setting up or in daemon mode. It's right there in the code, so you can see what's going to happen.
I've tried it a few times. Guess I'm not quick enough!

Fixed some more bugs, tidied some more code.

v2.0

The code for mounting, backing up, unmounting, and enabling and disabling anacron backup jobs is all
pretty much the same as v1, only now its been split into functions for ease of understanding and editing.

Instead of hard-coded settings which you have to edit the script to change, all settings are now stored 
in a config file, either saved as /etc/hp6000_backup.conf or as the filename specified at execution time.

Additionally, added an interactive setup routine to create initial config file from user input, with defaults

Finally, script can now update itself if the version hosted at github changes. Call it with update command
to do so.

