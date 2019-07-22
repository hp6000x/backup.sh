#backup.sh version 2.0

Mounts backup volume, backs up data, schedules daily backups, optionally unmounts after backup.
Ideally suited for backing up laptops with external drives when at home and connected.

Format is: 

	/pub/scripts/backup2.sh {command} [options]

Commands:

	[e]nable:	Enable the daily automated backup. (Uses sudo)
	[d]isable:	Disable the daily automated backup. (Uses sudo)
	[r]un:		Run a backup job. (Must be run as root)
	[u]pdate:	Checks github for new version and updates as necessary.
	[s]etup:	Create a new config file (either in the default place or where specified with --config).
	[h]elp:		Display this information page.

Options:

	-v				Give more details when running backups or displaying info
	--config={path to config file}	Use specified config file instead of default.

Note, if you specify an alternate config which does not exist, you will automatically be taken
through the setup process, just as you are when running this script for the first time.

Save this script somewhere in your PATH. I have a custom folder (/pub/scripts) which you can mimic
if you like, just don't forget to set the folders to publicly readable with 

	chmod -R 755 /pub

Another good place to put scripts is in $HOME/bin, just make sure it's in your path. You may need
to add a line to your .bashrc file:

	PATH="$HOME/bin:$PATH"
	
As with all my scripts, I'd recommend reading through and understanding this script, and tailoring it
to suit your system before running it for the first time. I take no responsibility for lost data.

WHAT'S CHANGED???

The code for mounting, backing up, unmounting, and enabling and disabling anacron backup jobs is all
pretty much the same as v1, only now its been split into functions for ease of understanding and editing.

Instead of hard-coded settings which you have to edit the script to change, all settings are now stored 
in a config file, either saved as /etc/hp6000_backup.conf or as the filename specified at execution time.

Additionally, added an interactive setup routine to create initial config file from user input, with defaults
