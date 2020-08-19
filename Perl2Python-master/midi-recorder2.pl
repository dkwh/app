#!/usr/bin/perl

# ##############################################################
# =============== MIDI RECORDER by FLORIAN BADOR ===============
# 
# VIDEO DEMO:
# https://www.youtube.com/watch?v=lPF1IkF51nU
# 
# FILES, PHOTOS and SCREENSHOTS :
# https://florianbador.com/pub/scripts/midi-recorder/
# 
# ========== WHAT IS IT? ==========
# Designed to run on a Raspberry Pi with a 7" touchscreen
# it allows to record performances from a MIDI input into .mid files,
# keep these files organized, and play them back to a MIDI output.
# It is designed for music makers to save their ideas easily.
# The interface is web-hosted with a mini HTTP daemon so it can
# be controlled remotely. In fact, this perl file IS that daemon so
# interface is locally available at http://127.0.0.1/
# 
# ========== WHY? ==========
# Because features-heavy DAWs or MIDI editors distract the composer
# and encourage us to spend more time with the mouse than on the piano
# composing great tunes. On the other hand, recorders integrated to
# electric pianos lack features, memory, and portability.
# Organists can also use this to record their performances and play
# them back.
# 
# ========== WHAT IT'S NOT ==========
# It is not a synthesizer software. It does not handle audio data so
# do not expect to hear your MIDI in a sound card. It will only play it
# back to a MIDI output (e.g. into your electric piano)
# It is not a MIDI editor. MIDI files are never modified. The further it goes
# is playing them at a different speed or from a certain position.

# ========== FEATURES ==========
# * SIMPLE, distraction-free interface
# * Record all MIDI data from a MIDI port into a .mid file w/ a single touch
# * .mid files are saved directly to USB memory (auto-detected, auto-mounted)
# * Multiple USBs can be plugged for redundancy
# * No need to eject USBs, data is safely synced after every write
# * Progress bar and display of current/total time
# * Can go play at any position in the file by touching the progress bar
# * Can (re)name files, delete, rate them
# * Can change the files tempo (BPM) to play at a different speed than recorded
# * Multiple playlists (one folder for each)
# * List all files sorted by date, with name, rating, original and new bpm
# * Can play entire playlist, and loop list or single file
# * Web interface allows to control everything locally or remotely
# * If remotely (via WiFi or Ethernet) can download .mid files individually,
#   or entire USB memory as a tgz archive for backup.
# 
# ========== WHAT YOU NEED ==========
# * A Raspberry Pi (I used Pi 3 B+ with Raspbian)
# * 7-inch touchscreen for Raspberry Pi
# * USB MIDI interface working on Linux (I use iConnectivity mio, 1 in 1 out)
# * arecordmidi (part of alsa-utils)
# * aplaymidi MODIFIED version (by Florian) which allows to change the bpm,
#   go play from a certain position in file, and print information about
#   a file to STDOUT (source and ARM binary available at the URL above)
# * Perl with modules listed below as "use ..."
#   To install perl type: sudo apt-get install perl
#   To install modules, type: sudo cpan The::Module (for each missing module)
# * Chrome browser which will be started w/ --kiosk option to play the interface
#   If you ever get stuck in Chrome press ALT+F4
# * Boot script (available at URL above) which starts this HTTP daemon and Chrome
# * Call the boot script from rc.local so everything opens when Pi starts
# * Configure Raspbian to hide the mouse cursor for Touchscreen
# * At least one USB memory stick (2 recommended). Files are saved in midi/
#   folder (lowercase). Folder is created at start if non-existent.
# * You do NOT need any html or image files for the interface. They are
#   embedded in this perl file.
# 
# ========== FAQs ==========
# * Can I run on something else than a Raspberry Pi?
#   Yes, any Linux system but you will have to recompile aplaymidi from my modified source
#   because I compiled it for ARM architecture (on a Raspbian Pi 3 B+).
# 
# * How to compile the customized version of aplaymidi?
#   Get the latest alsa-utils tgz source, extract it and go in alsa-utils-x.xx/
#	Replace seq/aplaymidi/aplaymidi.c by my version.
#   Then from the alsa-utils-x.xx/ folder execute ./configure --disable-nls && make
#   Then copy the new seq/aplaymidi/aplaymidi binary to a location this script will find.
# 
# * What about arecordmidi?
#	arecordmidi does NOT need to be custimized. Use the default version provided by alsa-utils.
# 
# * Other screen than 7", no touch, or screen-less?
#   Yes, screen-less for remote use. Use a mouse if no touch. Larger screens are fine
#   but smaller is trouble because the buttons of the interface may not fit well.
# 
# * Which File System for the USB memory?
#   This script will auto-detect and auto-mount any file system. I personally use one XFS
#	and one VFAT so I use XFS for me and can give VFAT to someone else, and it provides
#	good redundancy.
# 
# * How are the files stored?
#   In each USB memory you will have a midirec-playlistname/ folder (initially "midirec-default")
#   In each playlist folder files are named "YYYYMMDD-HHMMSS-the-song-title-128-4.mid"
#   Where 128 is the bpm it should be played at, and 4 is the rating (0 to 5. 0 means not rated yet).
#   During recording the BPM set in the right panel is saved as part of the midi data and it
#   will stay the "original BPM". The BPM in the filename is for playback only, the MIDI data
#   in the files is NEVER modified once recorded.
# 
# * Can I put .mid files in the USB midirec-*/ folders that were not recorded with this?
#   Yes but you must keep the file names as described above.
#  
# * Is anything saved on the SD card of the Raspberry Pi?
#   No MIDI. Only some config just to save the options selected in the interface.
#   EXCEPTION: if it fails to copy a .mid file to USB after recording it will try again
#   by (re)mounting the sticks and if it sill fails it will copy to
#   /root/ or / (whichever exists first) and then display a message about this.


# TODO : requirements, put a yum command that includes everything: perl + see where are lsblk and udevadm

# TODO BUGS TO FIX :
# * arecordmidi sometimes (rarely) records all very first notes together at once (few seconds)



use strict;
#use warnings;
#no warnings 'deprecated';

use Fcntl qw(:DEFAULT :flock);
use IO::Socket;
use IO::Select;

use MIME::Base64;
use Time::HiRes qw(gettimeofday tv_interval);


my $conf = {
	# You shouldn't need to change any of these.
	
	# Directories to search for binary files: (in order of priority)
	# (arecordmidi, modified verion of aplaymidi, etc)
	dirSearch		=> ["/root", "/home/pi", ".", "", # "" is "/" because we add /
		"/usr/local/bin", "/usr/bin", "/bin"],
	
	# Where to mount the USB memory sticks:
	# This is a prefix, will add "sda1", "sdb1", etc. and create them if don't exist.
	usbMountPath		=> "/mnt/midirec-usb-",
	
	# The script records MIDI data to ramfs to prevent USB issues from ruining the recording.
	# It will mkdir and mount automatically, then copies the file to USB immidiately when STOP is pressed.
	# If we name the file after it will rename "untitled" into the new name.
	# If it fails to copy to a USB it will try to copy to home folder ~ (which should ne /root/)
	# and then / if fails too.
	# Does not need to pre-exist.
	ramfsPath		=> "/mnt/midirec-ramfs",
	
	# Status file:
	# Where processes save the info others need,
	# e.g. status of player, PID of currently running arecordmidi.
	# MUST be in {ramfsPath} or everything will be very slow.
	# Does not need to pre-exist.
	statusFile		=> "/mnt/midirec-ramfs/status",
	
	# Folder name (not path) to use for MIDI files in USB drives :
	# Must start by "midirec-" to be detected in the list of available folders.
	currentFolder	=> "midirec-default",
	
	# MIDI time resolution in tick per beat:
	# The old standard is 384 (96 PPQ) but it could be so much greater with today's technology and storage space.
	ticksPerBeat	=> 960,
	
	# Config file:
	# Where we save settings from the interface,
	# e.g. MIDI input/output, repeat mode.
	# Each line is a variable "VarName\tValue\n" and it can overwrite this $conf hashref.
	# Does not need to pre-exist.
	confFile		=> "/root/midirec.conf",
	
	# Show "MIDI file" download link in playlist even when visiting from local IP address 127.x.x.x :
	alwaysShowMidiFile	=> 0,
	
	# Local IP on which the HTTP daemon should listen to:
	# e.g. eth0's IP, or "127.0.0.1" for local only, or "0.0.0.0" for all.
	listenInterface		=> "0.0.0.0",
	
	
	chromeStuckFix		=> 35,
	#					To fix a bug I experienced with chrome on Rasperry Pi.
	#					If >0, will kill and restart the local chrome (if there is one running)
	#					if we haven't had a request in the last N seconds.
	#					The bug is that after a while (hours or days) Chrome stops sending any
	#					request so we are stuck.
	
	chromeCommand		=> "chromium-browser --kiosk --disable-infobars --app='http://127.0.0.1/'",
	#					Only for {chromeStuckFix}
	
};



die("You must run this script as root.") unless $< == 0;


# ALREADY RUNNING ?
if( open(PS, "-|", "ps aux") ){
	my $l;
	while(defined($l=<PS>)){
		if( $l =~ /^root\s+(\d+)\s.+[^a-z\d]midi-recorder\.pl\W/i
			&& $1 != $$
			&& (stat("/proc/$1"))[9] < time - 2
		){
			close(PS);
			die("Another instance is already running (pid $1 - I am $$)");
		}
	}
	close(PS);
}


$SIG{CHLD} = "IGNORE";


# ==================== START MANAGER CHILD : ====================
# This process handles USB drives, status and config.

my $pid_mng = fork();

# IN CHILD :
if( $pid_mng == 0 ){
	
	$0 = "midi-recorder.pl (manager child)";
	system("renice 5 -p $$");
	childManager();
	exit;
	
# IN PARENT, FORK SUCCESS :
}elsif( $pid_mng > 0 ){
	
# FORK FAILED :
}else{
	die("Cannot fork manager : $!");
}


# ==================== START EXEC CHILD : ====================
# This process handles the execution of binaries (arecordmidi, aplaymidi)

my $pid_exec = fork();

# IN CHILD :
if( $pid_exec == 0 ){
	
	$0 = "midi-recorder.pl (exec child)";
	childExec();
	exit;
	
# IN PARENT, FORK SUCCESS :
}elsif( $pid_exec > 0 ){
	
# FORK FAILED :
}else{
	die("Cannot fork exec : $!");
}



# ==================== HTTP DAEMON LOOP : ====================
$0 = "midi-recorder.pl (HTTP daemon parent)";
while(1){
print("=========== MAIN WHILE\n");
	
	my $sock = IO::Socket::INET->new(
		Listen		=> 50,
		Proto		=> "tcp",
		LocalHost	=> $conf->{listenInterface},
		LocalPort	=> 80,
		ReuseAddr	=> 1,
		Timeout		=> 5,
	);
	unless( $sock ){
print("CANNOT CREATE SOCKET: $!\n");
		sleep(1);
		next;
	}
	$sock->autoflush(1);
	
	while( $sock ){
print("===========   while SOCK\n");
		
		# NEW CONNECTION:
		while( my $client = $sock->accept() ){
print("===========      new connection\n");
			
			my $pid = fork();
			
			# IN CHILD :
			if( $pid == 0 ){
				
				close($sock);
				handleConnection($client);
				exit;
				
			# IN PARENT, FORK SUCCESS :
			}elsif( $pid > 0 ){
				
			# FORK FAILED :
			}else{
				warn("Cannot fork : $!");
			}
			
			close($client);
		}
		
	} # while($sock)
	
	warn("Lost listener socket");
	
} # while(1) http daemon loop.


sub childManager {
	# Child daemon process that handles everything the HTTP daemon children don't do.
	# e.g. mounting USB drives, detecting MIDI interfaces, finding location of binaries, etc.
	
	my $mgmt; # hashref to remember various things
	
	fdbset($conf->{statusFile}, {
		player_status	=> "",
		exec			=> "",
		exec_time		=> "",
		exec_pid		=> "",
		play_position	=> "",
	}) if -e $conf->{statusFile};
	
	while(1){
		
		# LOAD WEB CONFIG :
		my $conf_db = fdbget($conf->{confFile});
		$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
		
		# LIST ALL CURRENT MOUNTS (/proc/mounts) :
		my $mounts = getMounts();
		
		# CREATE AND/OR MOUNT RAMFS :
		my $ramfs_mkdir = mkdirRecursive($conf->{ramfsPath});
		unless( $ramfs_mkdir ){
			showError($conf, "Cannot create ramfs directory \"$conf->{ramfsPath}\". Are you root?");
			sleep(10);
			next;
		}
		# Ramfs not mounted :
		if( $ramfs_mkdir == 1 || !exists $mounts->{byDir}->{ $conf->{ramfsPath} } ){
			system("mount -t ramfs -o 'mode=774,uid=0,gid=0' none $conf->{ramfsPath}"); # size shouldnt matter in ramfs
			$mounts = getMounts();
			if( exists $mounts->{byDir}->{ $conf->{ramfsPath} } ){
				print("Mounted ramfs to $conf->{ramfsPath}\n");
				fdbset($conf->{statusFile}, { ramfs_time => time } );
			}else{
				showError($conf, "Cannot mount ramfs directory \"$conf->{ramfsPath}\". Are you root?");
				sleep(10);
				next;
			}
		}
		
		# LOAD STATUS :
		my $status = fdbget($conf->{statusFile});
		
		my $now = time;
		
		# SHUTDOWN :
		if( $status->{shutdown} > $now - 180 ){
			
			system("sync");
			system("killall chromium-browser");
			
			foreach( keys %$status ){
				if( $_ =~ /^usb_[a-z\d]+_dir$/ ){
					system("umount $status->{$_}");
				}
			}
			
			sleep(2);
			system("killall -9 chromium-browser");
			sleep(1);
			system("shutdown -h now");
			sleep(6);
			system("init 0");
			sleep(3);
			system("halt");
			sleep(2);
			system("poweroff");
			
			exit;
		}
		
		# DETECT USB DRIVES :
		if( $status->{player_status} ne "rec"
			&& ( $mgmt->{last_usbdetect} < $now - 15
				|| $status->{player_status} ne "play"
					&& $mgmt->{last_usbdetect} < $now - 5
				|| $status->{menu_open}
			)
		){
			$mgmt->{last_usbdetect} = time;
			# Mount the sticks and put their details in status file
			unless( updateUsbSticks($conf, $status, $mounts) ){
				sleep(10);
				next;
			}
		}
		# TODO : we also need to update status file if no drives are there but everything is mounted... (e.g. if program was restarted and status file was lost)
		
		# FIND BINARIES :
		if( $status->{player_status} !~ /^(rec|play)$/
			&& $mgmt->{last_search} < $now - 14
			&& $conf->{dirSearch} ne ""
		){
			$mgmt->{last_search} = time;
			unless( searchSystem($conf, $status, $mounts) ){
				sleep(10);
				next;
			}
		}
		
		
		# REBUILD PLAYLIST :
		if( (stat("$conf->{ramfsPath}/playlist"))[7] < 10
			&& $mgmt->{last_playlist} < $now - 19
		){
			$mgmt->{last_playlist} = time;
			buildPlaylist($status);
		}
		
		# DETECT MIDI INTERFACES :
		if( $status->{player_status} !~ /^(rec|play)$/
			&& ( $mgmt->{last_mididetect} < $now - 12
				|| $status->{menu_open}
			)
			&& $status->{bin_arecordmidi} ne ""
			&& $status->{bin_aplaymidi} ne ""
		){
			$mgmt->{last_mididetect} = time;
			my $midi = updateMidiInt($conf, $status, $mounts);
			unless( $midi ){
				sleep(10);
				next;
			}
			
			my $confset;
			foreach my $type ( "midiin", "midiout" ){
				next if $conf->{$type} ne "";
				
				foreach( sort{ $midi->{$a} <=> $midi->{$b} } keys %$midi ){
					if( $_ =~ /^(\Q$type\E_\d+)_port$/
						&& $midi->{"$1\_client"} !~ /through/i
					){
						$confset->{$type} = $midi->{$_};
						$conf->{$type} = $midi->{$_};
						last;
					}
				}
			}
			
			fdbset($conf->{confFile}, $confset) if $confset;
			
		}
		
		# EXEC PROCESS DIED :
		if( $status->{exec_pid} > 0
			&& !kill(0, $status->{exec_pid})
		){
			
			# Verify that no one killed it and wrote to status :
			my $exec_pid_prev = $status->{exec_pid};
			$status = fdbget($conf->{statusFile});
			if( $status->{exec_pid} == $exec_pid_prev
				&& !kill(0, $status->{exec_pid})
			){
				
				fdbset($conf->{statusFile}, {
					exec				=> "",
					exec_time			=> "",
					exec_pid			=> "",
					exec_started		=> "",
					player_status		=> "",
					play_position		=> "",
				} );
			}
		}
		
		# CHROME IS STUCK, RESTART IT :
		if( $conf->{chromeStuckFix} > 0
			&& $status->{lastLocalRequest} < time - $conf->{chromeStuckFix}
		){
			my $chromePid = 0;
			if( open(PS, "-|", "ps aux") ){
				my $l;
				while(defined($l=<PS>)){
					if( $l =~ /^\S+\s+(\d+)\s.+[^a-z\d]chrom(e|ium)[^a-z].*--kiosk[^a-z].*[^a-z]http:\/\/127\.0\.0\.1[\/\s]/i
						&& (stat("/proc/$1"))[9] < time - $conf->{chromeStuckFix}
					){
						$chromePid = $1;
						last;
					}
				}
				close(PS);
			}
			
			if( $chromePid > 0 ){
				print("Restarting Chrome $chromePid (no request in ".(time-$status->{lastLocalRequest})."s)\n");
				killWell($chromePid);
				system("$conf->{chromeCommand}&");
			}
		}
		
		sleep(2);
		
	}
	
}

sub childExec {
	# Child daemon process that handles the execution of binaries (typically arecordmidi & aplaymidi)
	
	my $exec; # hashref to remember various things
	
	while(1){
		
		# LOAD WEB CONFIG :
		if( $exec->{last_conf_load} < time - 3 ){
			my $conf_db = fdbget($conf->{confFile});
			$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
			$exec->{last_conf_load} = time;
		}
		
		# LOAD STATUS :
		my $status = fdbget($conf->{statusFile});
		
		# Something to execute :
		if( $status->{exec} ne ""
			&& $status->{exec_time} > 0
			&& ( $status->{exec_pid} eq ""
				|| !kill(0, $status->{exec_pid})
			)
		){
			
		 	fdbset($conf->{statusFile}, {exec_time => "", exec_pid => ""} );
		 	
			my $exec_fh;
			my $exec_pid = open($exec_fh, "-|", $status->{exec});
			
			my $status_set = {
				exec_pid 			=> $exec_pid,
				exec_started		=> scalar gettimeofday(),
				exec_player_status	=> "",
				exec_killing		=> "",
			};
			$status_set->{player_status} = $status->{exec_player_status} if $status->{exec_player_status} ne "";
			
			unless( fdbset($conf->{statusFile}, $status_set) ){
				killWell($exec_pid);
				close $exec_fh;
				sleep(2);
				next;
			}
			
			# => Will hang in close() until the process is done. So we may want to kill the process gently (-15) using exec_pid )
			close $exec_fh;
			
			my $status_old = $status;
			$status = fdbget($conf->{statusFile});
			
		 	fdbset($conf->{statusFile}, {
		 		exec				=> "",
		 		exec_time			=> "",
		 		exec_pid			=> "",
		 		exec_started		=> "",
		 		player_status		=> "",
		 		play_position		=> "",
		 	} ) if $status->{exec_pid} == $exec_pid; # so we dont overwrite everything if another execution was set (e.g. when relocating twice quickly with progress bar)
		 	
		 	# PLAY SOMETHING ELSE AFTER :
		 	if( $status_old->{exec_player_status} eq "play" # we were playing something (not recording)
		 		&& $status->{player_status} eq "play" # player still in play mode (no one paused)
		 		&& $status->{exec_killing} eq ""
		 		&& $status->{selected_file} ne ""
		 	){
		 		
				# LOAD WEB CONFIG :
				my $conf_db = fdbget($conf->{confFile});
				$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
				
		 		if( $conf->{repeat} || $conf->{continue} ){
					
		 			my $file_next = "";
					# FIND NEXT FILE :
		 			if( $conf->{continue} ){
		 				
		 				# GET NEXT SONG AND FIRST SONG FROM PLAYLIST :
		 				my $playlist = fdbget("$conf->{ramfsPath}/playlist");
		 				
		 				my $base_current;
		 				$base_current = $1 if $status->{selected_file} =~ /^(\d{8}-\d{6})-/;
		 				my $base_first = "";
		 				my $base_next = "";
		 				my $current_seen = 0;
		 				
		 				foreach( sort{ $b cmp $a } keys %$playlist ){
							my $base;
							$base = $1 if $_ =~ /^(\d{8}-\d{6})\./;
		 					$base_first = $base if $base_first eq "";
							
		 					if( $current_seen ){
		 						next if $base eq $base_current;
		 						$base_next = $base;
		 						last;
		 					}elsif( $base eq $base_current ){
		 						$current_seen = 1;
		 					}
		 					
		 				}
		 				
		 				my $base_toplay = "";
						if( $base_next ne "" ){
							$base_toplay = $base_next;
						}elsif( $conf->{repeat} && $base_first ne "" ){
							$base_toplay = $base_first;
						}
						
						$file_next = songToFilename($base_toplay, $playlist->{"$base_toplay.t"}, $playlist->{"$base_toplay.bo"}, $playlist->{"$base_toplay.bn"}, $playlist->{"$base_toplay.r"})
							if $base_toplay ne "";
						
						
		 			# REPEAT SAME FILE :
		 			}else{
		 				$file_next = $status->{selected_file};
					}
					
					if( $file_next ne "" ){
						
						$status = fdbset($conf->{statusFile}, {
							selected_file		=> $file_next,
							play_position		=> 0,
						} );
						
						pageAjaxPlayStart(undef, undef, undef, $status, 1);
						
					}
					
		 		}
		 		
		 	}
		 	
		}else{
			
			select(undef, undef, undef, 0.15);
			
		}
		
	}
	
}

sub fdbget {
	# Read variables from a file storing them as "VarName\tValue\n"
	# $_[0] : file path
	# 
	# RETURN hashref:
	# ->{VarName} = Value
	
	my ($fdb_file) = @_;
	
	my $ret;
	
	my $fdb_l;
	my $fdb_fh;
	return undef unless open($fdb_fh, "<$fdb_file");
	
	flock($fdb_fh, LOCK_SH);
	
	while(defined($fdb_l=<$fdb_fh>)){
		if( $fdb_l =~ /^([\w.-]+)\t(.*)\n$/ ){
			$ret->{$1} = $2;
		}
	}
	
	close $fdb_fh;
	
	return $ret;
	
}

sub fdbset {
	# Write variables in a file storing them as "VarName\tValue\n"
	# $_[0] : file path
	# $_[1] : hashref of vars to write ->{VarName} = Value
	#		  empty value means deleting the var.
	# $_[2] : delete existing vars
	# 
	# RETURN:
	# hashref of all vars ->{VarName} = Value
	# or undef on error
	
	my ($fdb_file, $fdb_wrt, $fdb_del) = @_;
	
	my $vars;
	
	my $fdb_l;
	my $fdb_fh;
	return undef unless sysopen($fdb_fh, $fdb_file, O_CREAT|O_RDWR);
	
	unless( flock($fdb_fh, LOCK_EX) ){
		close $fdb_fh;
		return undef;
	}
	
	unless( $fdb_del ){
		while(defined($fdb_l=<$fdb_fh>)){
			if( $fdb_l =~ /^([\w.-]+)\t(.*)\n$/ ){
				$vars->{$1} = $2;
			}
		}
	}
	
	foreach( keys %$fdb_wrt ){
		if( $fdb_wrt->{$_} eq "" ){
			delete $vars->{$_};
		}else{
			$vars->{$_} = $fdb_wrt->{$_};
		}
	}
	
	return undef unless(
		seek($fdb_fh, 0, 0)
		&& truncate($fdb_fh, 0)
	);
	
	print($fdb_fh "$_\t$vars->{$_}\n") foreach sort{ $a cmp $b } keys %$vars;
	
	close $fdb_fh;
	
	return $vars;
	
}

sub showError {
	# Show error message in STDOUT and in interface
	# $_[0] : $conf
	# $_[1] : message
	
	print($_[1]);
	fdbset($_[0]->{statusFile}, { error_time => time, error => $_[1] } );
	return(1);
	
}

sub mkdirRecursive {
	# A recursive mkdir
	# $_[0] : directory path
	# 
	# RETURN:
	# 2		: already existed
	# 1		: success
	# undef : failed
	
	return(2) if -d $_[0];
	
	my $path = $_[0];
	my $path_tmp = "";
	if( $path =~ s!^([^/]+)/?!! ){
		$path_tmp = $1;
		mkdir $path_tmp unless -e $path_tmp;
	}else{
		$path =~ s!^/+!!;
	}
	
	foreach( split("/", $path) ){
		next if $_ eq "";
		$path_tmp .= "/$_";
		mkdir $path_tmp unless -e $path_tmp;
	}
	
	return(1) if -d $_[0];
	return undef;
	
}

sub timeToFileDate {
	# Return "YYYYMMDD-HHMMSS" from epoch time
	# $_[0] : optional epoth time (current time otherwise)
	
	my ($datsec, $datmin, $dathou, $datday, $datmon, $datyear) = localtime($_[0] || time);
	my @dat = localtime($_[0] || time);
	$dat[5] += 1900;
	$dat[4]++;
	
	for( my $i=0 ; $i<5 ; $i++ ){
		$dat[$i] = "0$dat[$i]" if length($dat[$i])==1;
	}
	
	return("$dat[5]$dat[4]$dat[3]-$dat[2]$dat[1]$dat[0]");
	
}

sub killWell {
	# Kill a PID nicely, then harder until it works
	# $_[0] : pid
	# 
	# RETURN:
	# 2 = pid was not running
	# 1 = successfully terminated
	# 0 = does not respond, still running
	
	return(2) unless kill(0, $_[0]);
	
	kill(15, $_[0]);
	return(1) unless kill(0, $_[0]);
	select(undef, undef, undef, 0.2);
	return(1) unless kill(0, $_[0]);
	
	kill(15, $_[0]);
	return(1) unless kill(0, $_[0]);
	select(undef, undef, undef, 0.8);
	return(1) unless kill(0, $_[0]);
	
	kill(9, $_[0]);
	return(1) unless kill(0, $_[0]);
	select(undef, undef, undef, 0.2);
	return(1) unless kill(0, $_[0]);
	
	kill(9, $_[0]);
	return(1) unless kill(0, $_[0]);
	select(undef, undef, undef, 0.5);
	return(1) unless kill(0, $_[0]);
	
	kill(9, $_[0]);
	return(1) unless kill(0, $_[0]);
	select(undef, undef, undef, 0.8);
	return(1) unless kill(0, $_[0]);
	
	return(0);
	
}

sub getMounts {
	# List all current mounting points
	# 
	# RETURN hashref:
	# ->{byDir}->{/mnt/mounted-here} = "/dev/sdb1"
	# ->{byDev}->{/dev/sdb1} = "/mnt/mounted-here"
	# ->{byDir}->{/mnt/some-ramfs} = "ramfs"
	
	return undef unless open(MNTS, "/proc/mounts");
	
	my $ret;
	
	my $l;
	while(defined($l=<MNTS>)){
		if( $l =~ /^\s*(\S+)\s+(\S+)\s+(\S+)\s/ ){
			if( $1 eq "none" ){
				$ret->{byDir}->{$2} = $3;
			}else{
				$ret->{byDir}->{$2} = $1;
				$ret->{byDev}->{$1} = $2;
			}
		}
	}
	
	close(MNTS);
	
	return $ret;
	
}

sub updateUsbSticks {
	# Detect USB memory sticks, mount them and put all info into status file
	
	my ($conf, $status, $mounts) = @_;
	
	# UMOUNT DRIVES THAT ARE GONE :
	foreach( keys %$status ){
		if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
			my $disk_name = $1;
			
			my $lsblk = lsblk($status->{"usb_$disk_name\_dev"});
			next if $lsblk->{dir} ne ""; # still mounted
			print($status->{"usb_$disk_name\_dev"}." no longer mounted, according to lsblk\n");
			
			# But content still shows, try to write to make sure it fails :
			if( -d "$status->{$_}/$conf->{currentFolder}" ){
				my $now = time;
				fdbset("$status->{$_}/$conf->{currentFolder}/.test-mounted", { t => $now } );
				my $test = fdbget("$status->{$_}/$conf->{currentFolder}/.test-mounted");
				if( $test && $test->{t} == $now ){
					print($status->{"usb_$disk_name\_dev"}." still mounted since we can write to it\n");
					unlink("$status->{$_}/$conf->{currentFolder}/.test-mounted");
					next;
				}
			}
			
			system("umount $status->{$_}");
			
			# Failed to umount :
			if( -d "$status->{$_}/$conf->{currentFolder}"
				|| system("umount -f $status->{$_}")
					&& sleep(1)
					&& -d "$status->{$_}/$conf->{currentFolder}"
			){
				print("Could not umount ".$status->{"usb_$disk_name\_dev"}." because dir still exists $status->{$_}/$conf->{currentFolder}\n");
				next;
			}
			
			fdbset( $conf->{statusFile}, {
				"usb_$disk_name\_dev"			=> "",
				"usb_$disk_name\_dir"			=> "",
				"usb_$disk_name\_fs"			=> "",
				"usb_$disk_name\_label"			=> "",
				"usb_$disk_name\_manufacturer"	=> "",
				"usb_$disk_name\_product"		=> "",
				"usb_$disk_name\_time"			=> "",
			} );
			
		}
	}
	
	# EACH USB STICK CURRENTLY PLUGGED :
	my $usb_sticks = findUsbSticks();
	foreach( keys %$usb_sticks ){
		# print("$_ : \"$usb_sticks->{$_}->{manufacturer}\" \"$usb_sticks->{$_}->{product}\" [$usb_sticks->{$_}->{parts}]\n  $usb_sticks->{$_}->{drive} [$usb_sticks->{$_}->{drive_fs}] \"$usb_sticks->{$_}->{drive_label}\"\n");
		
		my $disk_name;
		if( $usb_sticks->{$_}->{drive} =~ m!([a-z\d]+)$! ){
			$disk_name = $1;
		}else{
			next;
		}
		
		my $mount_path = "$conf->{usbMountPath}$disk_name";
		
		# USB ALREADY MOUNTED :
		if( exists $mounts->{byDir}->{$mount_path} ){
			
			# BUT MIDIREC DIR DOES NOT EXIST :
			unless( -d "$mount_path/$conf->{currentFolder}" ){
				unless( mkdir("$mount_path/$conf->{currentFolder}") && -d "$mount_path/$conf->{currentFolder}" ){
					showError($conf, "Cannot create \"$conf->{currentFolder}\" directory in usb drive \"$usb_sticks->{$_}->{drive}\" ($usb_sticks->{$_}->{manufacturer} $usb_sticks->{$_}->{product} $usb_sticks->{$_}->{drive_label}). Is it write-protected?");
					return undef;
				}
				print("Created directory $mount_path/$conf->{currentFolder}\n");
			}
			
			next if $status->{"usb_$disk_name\_time"} ne "";
			
		# NOT MOUNTED :
		}else{
			
			# CREATE MOUNTING POINT DIR :
			my $mkdir = mkdirRecursive($mount_path);
			unless( $mkdir ){
				showError($conf, "Cannot create usb mounting point directory \"$mount_path\". Are you root?");
				return undef;
			}
			
			# MOUNT :
			system("mount -t $usb_sticks->{$_}->{drive_fs} -o sync $usb_sticks->{$_}->{drive} $mount_path");
			$mounts = getMounts();
			unless( exists $mounts->{byDir}->{$mount_path} ){
				showError($conf, "Cannot mount usb drive \"$usb_sticks->{$_}->{drive}\" to \"$mount_path\" ($usb_sticks->{$_}->{manufacturer} $usb_sticks->{$_}->{product} $usb_sticks->{$_}->{drive_label}). Are you root?");
				return undef;
			}
			print("Mounted $mount_path\n");
			
			# CREATE MIDIREC DIR :
			unless( -d "$mount_path/$conf->{currentFolder}" ){
				unless( mkdir("$mount_path/$conf->{currentFolder}") && -d "$mount_path/$conf->{currentFolder}" ){
					showError($conf, "Cannot create \"$conf->{currentFolder}\" directory in usb drive \"$usb_sticks->{$_}->{drive}\" ($usb_sticks->{$_}->{manufacturer} $usb_sticks->{$_}->{product} $usb_sticks->{$_}->{drive_label}). Is it write-protected?");
					return undef;
				}
				print("Created directory $mount_path/$conf->{currentFolder}\n");
			}
			
		}
		
		# WRITE USB DISK INFO TO STATUS FILE :
		$status = fdbset( $conf->{statusFile}, {
			"usb_$disk_name\_dev"			=> $usb_sticks->{$_}->{drive},
			"usb_$disk_name\_dir"			=> $mount_path,
			"usb_$disk_name\_fs"			=> $usb_sticks->{$_}->{drive_fs},
			"usb_$disk_name\_label"			=> $usb_sticks->{$_}->{drive_label},
			"usb_$disk_name\_manufacturer"	=> $usb_sticks->{$_}->{manufacturer},
			"usb_$disk_name\_product"		=> $usb_sticks->{$_}->{product},
			"usb_$disk_name\_time"			=> time,
		} );
		
	}
	
	return 1;
	
}

sub findUsbSticks {
	# Find all USB memory sticks (the devices, not their partitions)
	# 
	# RETURN HASHREF:
	# ->{/dev/sdb}->{manufacturer}	= Brand
	# ->{/dev/sdb}->{product}		= Product Name
	# ->{/dev/sdb}->{parts}			= Nb of partitions
	# ->{/dev/sdb}->{drive}			= Partition we pick (e.g. "/dev/sdb1")
	# ->{/dev/sdb}->{drive_fs}		=  its file system (e.g. "vfat")
	# ->{/dev/sdb}->{drive_label}	=  its label if any
	
	my $ret;
	
	return undef unless opendir(DEVDIR, "/dev");
	
	my $devmax = {}; # nb of partitions for each device (e.g. ->{/dev/sda} = 5)
	
	foreach(readdir(DEVDIR)){
		# DRIVE :
		if( $_ =~ /^sd[a-z]+$/ ){
			
			my $usbdev = devUsbInfo("/dev/$_");
			if( $usbdev->{usbstick} ){
				$ret->{"/dev/$_"} = {
					manufacturer	=> $usbdev->{manufacturer},
					product			=> $usbdev->{product},
				};
			}
			
		# PARTITION :
		}elsif( $_ =~ /^(sd[a-z]+)(\d+)$/ ){
			$devmax->{"/dev/$1"} = $2 if $2 > $devmax->{"/dev/$1"};
			
		}
	}
	
	closedir(DEVDIR);
	
	# EACH USB STICK FOUND :
	foreach my $dev ( keys %$ret ){
		
		my $parts = $devmax->{$dev};
		$ret->{$dev}->{parts} = $parts;
		
		# EACH PARTITION :
		foreach( my $p = $parts > 0 ? 1 : 0 ; $p <= $parts ; $p++ ){
			my $devpart = $dev.( $p > 0 ? $p : ""); # e.g. "/dev/sda1"
			
			my $partinfo = lsblk($devpart);
			next unless $partinfo;
			
			$ret->{$dev}->{drive} = $devpart;
			$ret->{$dev}->{drive_fs} = $partinfo->{fs};
			$ret->{$dev}->{drive_label} = $partinfo->{label};
			last;
		}
		
	}
	
	return $ret;
	
}

sub devUsbInfo {
	# Return some info about a /dev/sdX device we expect to be a usb memory
	# $_[0] : device path (e.g. "/dev/sdb")
	# 
	# RETURN HASHREF:
	# ->{usbstick}		= 1 if is a USB memory stick
	# ->{manufacturer}	= Brand
	# ->{product}		= Product Name
	
	my ($dev) = @_;
	my $ret = {};
	
	return undef unless open(CMD, "-|", "udevadm info -n $dev -a");
	
	my $block = "";
	my $l;
	while(defined($l=<CMD>)){
		if( $l =~ /^\s*looking at /i ){
			last if devUsbParseBlock($block, $ret);
			$block = $l;
		}elsif( $l =~ /^\s*$/ && $block ne "" ){
			last if devUsbParseBlock($block, $ret);
			$block = "";
		}elsif( $block ne "" ){
			$block .= $l;
		}
	}
	
	close(CMD);
	
	return $ret;
	
}

sub devUsbParseBlock {
	# Parse a paragraph from the udevadm command
	# $_[0] : paragraph string
	# $_[1] : hashref to put info into
	# 
	# RETURN:
	# 1 if we got what we wanted (which we put in $ret)
	# 0 if not
	
	my $blockstr = "\n$_[0]\n";
	$blockstr =~ s/\n\s+/\n/g;
	
	return(0) unless $blockstr =~ /\nSUBSYSTEMS==\"usb\"/i;
	
	my $attrs = {};
	$blockstr =~ s!\nATTRS\{([\w.-]+)\}==\"([^"\n]*)\"\K!
		$attrs->{lc($1)} = $2;
		"";
	!eig;
	
	return(0) if " $attrs->{product} " =~ /\W(hub|controller)\W/i;
	
	if( $attrs->{removable} =~ /removable|yes|true|^1/i
		|| $attrs->{bmaxpower} =~ /^\d/
		|| $attrs->{serial} ne ""
		|| $attrs->{manufacturer} =~ /kingston|transcend|samsung|corsair|sandisk|hewlett/i
		|| $attrs->{product} =~ /memory|stick/i
	){
		$_[1]->{manufacturer} = $attrs->{manufacturer};
		$_[1]->{product} = $attrs->{product};
		$_[1]->{usbstick} = 1;
		return(1);
	}
	
	return(0);
	
}

sub lsblk {
	# Return the filesystem and label of a disk
	# $_[0] : /dev/sda1
	# 
	# RETURN:
	# ->{fs}	= xfs
	# ->{label}	= "MyDrive"
	# ->{dir}	= "/mnt/mounting-point"
	# or undef
	
	my ($disk) = @_;
	my $ret;
	
	my $disk_name = "";
	if( $disk =~ m!([a-z\d]+)$! ){
		$disk_name = $1;
	}
	my $label_end = 0; # char pos where LABEL column ends
	
	return undef unless open(CMD, "-|", "lsblk -f $disk 2>/dev/null");
	
	my $l;
	while(defined($l=<CMD>)){
		if( $label_end == 0
			&& $l =~ /^(.+LABEL[ \t]*)/
		){
			$label_end = length($1);
			
		}elsif( $l =~ /^(\Q$disk_name\E\s+(\w+)\s+)/i ){
			
			$ret->{fs} = $2;
			
			my $label_start = length($1);
			if( $label_end > $label_start
				&& substr($l, $label_start, $label_end - $label_start) =~ m/^(\w.*?)\s*$/
			){
				$ret->{label} = $1;
			}
			
			if( $l =~ m!\s(/\S*)\n$! ){
				$ret->{dir} = $1;
			}
			
			last;
		}
	}
	
	close(CMD);
	
	return $ret;
	
}

sub updateMidiInt {
	# Detect MIDI interfaces and put then in status file
	# If none is selected, select the first one.
	
	my ($conf, $status, $mounts) = @_;
	
	my $status_set;
	
	foreach my $type ( "midiin", "midiout" ){
		
		if( $type eq "midiin" ){
			return undef unless open(CMD, "-|", "$status->{bin_arecordmidi} -l");
		}else{
			return undef unless open(CMD, "-|", "$status->{bin_aplaymidi} -l");
		}
		
		foreach( keys %$status ){
			$status_set->{$_} = "" if $_ =~ /^\Q$type\E_/;
		}
		
		my $block = "";
		my $l;
		my $midi_cnt = 0;
		while(defined($l=<CMD>)){
			if( $l =~ /^\s*(\d[\d:.]+)\s+(\S.*?\S)\s{3,}(\S.*?)\n/ ){
				$midi_cnt++;
				$status_set->{"$type\_$midi_cnt\_port"} = $1;
				$status_set->{"$type\_$midi_cnt\_client"} = $2;
				$status_set->{"$type\_$midi_cnt\_name"} = $3;
			}
		}
		
		close(CMD);
		
	}
	
	return fdbset($conf->{statusFile}, $status_set) if $status_set;
	return(1);
	
}

sub searchSystem {
	# Find binary/program files by look in directories of {dirSearch}
	
	my ($conf, $status, $mounts) = @_;
	
	my $found;
	my $status_set;
	
	# EACH DIR TO SEARCH IN :
	foreach my $dir ( @{ $conf->{dirSearch} } ){
		next unless -d $dir;
		
		# ARECORDMIDI :
		if( !exists $status_set->{bin_arecordmidi}
			&& !$found->{arecordmidi}
			&& -f "$dir/arecordmidi"
		){
			if( $status->{bin_arecordmidi} ne "$dir/arecordmidi" ){
				print("Found arecordmidi in $dir/arecordmidi\n");
				$status_set->{bin_arecordmidi} = "$dir/arecordmidi";
			}
			$found->{arecordmidi} = 1;
		}
		
		# APLAYMIDI (Florian custom version, NOT the original) :
		if( !exists $status_set->{bin_aplaymidi}
			&& !$found->{aplaymidi}
			&& -f "$dir/aplaymidi"
		){
			
			if( open(APM, "-|", "$dir/aplaymidi --help") ){
				my $l;
				while(defined($l=<APM>)){
					if( $l =~ /FLORIAN BADOR/i ){
						if( $status->{bin_aplaymidi} ne "$dir/aplaymidi" ){
							print("Found aplaymidi in $dir/aplaymidi\n");
							$status_set->{bin_aplaymidi} = "$dir/aplaymidi";
						}
						$found->{aplaymidi} = 1;
						last;
					}
				}
				close(APM);
				
			}
			
		}
		
	}
	
	return fdbset($conf->{statusFile}, $status_set) if $status_set;
	return(1);
	
}

sub getLatestMidiFile {
	# Return filename of most recent midi file (NOT by mtime but by date in filename)
	# $_[0] : directory path to search in
	
	my $files;
	
	return "" unless opendir(DIR, $_[0]);
	
	foreach( readdir(DIR) ){
		if( $_ =~ /^2[01]\d{6}-\d{6}-.+\.mid$/ ){
			$files->{$_} = 1;
		}
	}
	
	closedir(DIR);
	
	foreach( sort{$b cmp $a} keys %$files ){
		return $_;
	}
	
	return "";
	
}

sub songToFilename {
	# Return a MIDI filename for a song
	# $_[0] : base filename 'YYYYMMDD-HHMMSS'
	# $_[1] : song title
	# $_[2] : bpm original
	# $_[3] : bpm new
	# $_[4] : rating
	
	my $title = lc $_[1];
	$title =~ tr/ /-/;
	
	return( $_[0]
		."-$title-"
		.( $_[3] || $_[2] )
		."-$_[4].mid"
	);
}

sub secToTime {
	# Return a time '1:59' from seconds 119
	# $_[0] : seconds duration
	
	my $sec = int($_[0] + 0.5);
	my $min = int($sec / 60);
	$sec -= $min * 60;
	$sec = "0$sec" if $sec < 10;
	
	return("$min:$sec");
	
}

sub midiFileInfo {
	# Return info about a midi file
	# This requires aplaymidi customized version by Florian
	# $_[0] : $status hashref
	# $_[1] : file path
	# 
	# RETURN HASHREF :
	# ->{time_division}		= resolution in divisions per beat (typically 384)
	# ->{original_bpm}		= bpm saved in the file during recording
	# ->{new_bpm}			= bpm speed of play (same as original in this case)
	# ->{total-ticks}		= total nb of ticks
	# ->{total_beats}		= total nb of beats (e.g. 542)
	# ->{total_duration}	= float seconds (e.g. 119.123)
	
	my ($status, $file_path) = @_;
	
	my $ret = {};
	
	if( open(APM, "-|", "$status->{bin_aplaymidi} -p $conf->{midiout} -n $file_path") ){
		
		my $l;
		while(defined($l=<APM>)){
			if( $l =~ /^\s*([\w-]+)\s+=\s+([\w.-]+)/ ){
				$ret->{$1} = $2;
			}
		}
		close APM;
	}
	
	$ret->{original_bpm} = int($ret->{original_bpm} * 1000 + 0.5) / 1000 if exists $ret->{original_bpm};
	
	return $ret;
	
}

sub buildPlaylist {
	# (re)Build the list of MIDI files from USB drives.
	# $_[0] : $status hashref
	# $_[1] : "YYYYMMDD-HHMMSS" to only rebuild this file
	#         or "" to rebuild everything (may take some time)
	
	my ($status, $build_file) = @_;
	
	# PICK A USB DRIVE RANDOMLY :
	my $disk;
	my $disk_dir = "";
	foreach( sort{ int(rand(3)) - 1 } keys %$status ){
		if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
			$disk = $1;
			$disk_dir = $status->{$_};
			last;
		}
	}
	
	return undef if $disk_dir eq "";
	
	my $list_file = "$conf->{ramfsPath}/playlist";
	$build_file = "" unless -e $list_file; # if no list yet, rebuild everything
	
	# (RE)LOAD WEB CONFIG :
	my $conf_db = fdbget($conf->{confFile});
	$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
	
	my $listset;
	
	# READ MIDI DIRECTORY :
	my $midi_dir = "$disk_dir/$conf->{currentFolder}";
	return undef unless opendir(MDR, $midi_dir);
	
	foreach my $file_name ( readdir(MDR) ){
		if( $file_name =~ /^(2[01]\d{6}-\d{6})-(.+)\.mid$/
			&& ( $build_file eq "" || $1 eq $build_file )
		){
			my $file_base = $1;
			my $file_rest = $2;
			
			my $file_newbpm = "";
			my $file_rating = 0;
			if( $file_rest =~ s/-(\d{2,3})-([0-5])$// ){
				$file_newbpm = $1;
				$file_rating = $2;
			}
			
			my $file_title = ucfirst($file_rest);
			$file_title =~ tr/-/ /;
			$file_title =~ s/ \K([a-z])(?=[a-z]{3})/ uc($1) /eig;
			
			
			my $file_info = midiFileInfo($status, "$midi_dir/$file_name");
			
			$listset->{"$file_base.t"} = $file_title;
			$listset->{"$file_base.r"} = $file_rating;
			$listset->{"$file_base.d"} = $file_info->{total_duration};
			$listset->{"$file_base.bo"} = $file_info->{original_bpm};
			$listset->{"$file_base.bn"} = $file_newbpm || "";
			
			last if $build_file ne "";
		}
	}
	
	closedir(MDR);
	
	fdbset( $list_file,
		$listset,
		$build_file ne "" ? 0 : 1
	);
	
	return $listset;
	
}

sub handleConnection {
	# Handle the connection of an accepted client in a child.
	# $_[0] : client accepted socket
	
	# WARNING: this HTTP server is very insecure and basic. Do not use it for something else than MIDI-Recorder.
	
	my ($client) = @_;
	
	my $client_info = {
		ip		=> $client->peerhost(),
		#port	=> $client->peerport(),
	};
	$client_info->{islocal} = $client_info->{ip} =~ /^127\.\d+\.\d+\.\d+$/ ? 1 : 0;
	
	$0 = "midi-recorder.pl (child for connection from $client_info->{ip})";
	
	my $cs = IO::Select->new($client); # Client Select
	my $conOpenTime = [gettimeofday];
	
	while( $client ){
		
		
		# WAITING FOR NEXT REQUEST:
		$client->blocking(0); # sysread() will never wait
		my $request = "";
		my $closecon = 0;
		my $canNoWait = 0; # how many times in a row can_read did not wait
		my $inwait = [gettimeofday];
		while(1){
			
			# Read byte by byte from input buffer :
			if( sysread($client, my $byte, 1) ){
				
				$request .= $byte;
				last if( $byte eq "\n" && $request =~ /\n\r?\n$/ );
				
			# Nothing to read in the buffer :
			}else{
				
				my $canBefore = [gettimeofday];
				$cs->can_read(1);
				my $canWaited = tv_interval($canBefore, [gettimeofday]); # time can_read has been waiting
				
				my $canSleep = 0;
				# can_read did not wait :
				if( $canWaited < 0.001 ){
					
					$canNoWait++ if $canNoWait < 100; # this limit determines how long we will sleep max
					
					my $canSleep = 0.002 + $canNoWait / 5000 if(
						$canNoWait > 2 # can_read did not wait N times in a row
						&& index($request,"\n") == -1 # no valid line received
					);
					
					select(undef, undef, undef, $canSleep);
					
				}else{
					$canNoWait = 0;
					
					# Connection life time :
					# (some bug makes that old connections tend to no longer listen, this is a quick fix to avoid 3 days of research)
					my $conLife = tv_interval($conOpenTime, $canBefore);
					if( $conLife > 600 ){
						if( $conLife > 630 ){
							close $client;
							return(1);
						}
						$closecon = 1;
					}
				}
				
				last unless $client;
				
				# We've been waiting for a request for too long (keep-alive)
				if( tv_interval($inwait, [gettimeofday]) > 35 ){
					close $client;
					last;
				}
				
			}
			
		} # while(1) waiting for next request
		
		last unless $client;
		
		# Incomplete request :
		unless( $request =~ /\n\r?\n$/ ){
			close $client;
			last;
		}
		
		# Empty request :
		next unless $request =~ /\w/;
		
		$client->blocking(1);
		
		handleRequest($client, $client_info, \$request, $closecon);
		if( $closecon ){
			close $client;
			return(1);
		}
		
	} # while $client
	
	return(1);
	
}

sub parseHeaders {
	# Parse an HTTP request headers (very basic)
	# $_[0] : scalar-ref of request data
	
	my $prret;
	my $prtmp = ${$_[0]};
	$prtmp =~ s/[\n\r]+/\n/g;
	
	# METHOD / URI / PROTOCOL :
	if( $prtmp =~ s/^\s*([A-Z]{1,9}) ([\x21-\x7E]{0,4000}) ([a-zA-Z].*)// ){
		$prret->{method} = $1;
		$prret->{uri} = $2;
		$prret->{proto} = $3;
		$prret->{uridec} = $prret->{uri};
		$prret->{uridec} =~ s/%([\dA-F]{2})/pack("H*",$1)/eig;
	}else{
		return(undef);
	}
	
	# HOST :
	if( $prtmp =~ s/\nHost *: *([\w.:-]{1,90})(?=\s)/\n/i ){
		$prret->{host} = $1;
		$prtmp =~ s/\nHost *:.*//ig;
	}
	
	# Other headers :
	$prtmp =~ s!\n([\w.-]{1,90}) *: *([\x21-\x7E][\x20-\x7E]{0,4000})!
		my $field = lc($1);
		my $value = $2;
		$field =~ s/^accept-//;
		$field =~ s/^user-//;
		$field =~ s/^content-//;
		$field =~ s/[^a-z\d]+//g;
		
		$prret->{$field} .= "$value\n" if $field ne "";
		"";
	!eg;
	
	$prret->{$_} =~ s/\n$// foreach( keys %$prret );
	
	# Lowercase versions for common fields :
	foreach( "agent", "host", "uri", "uridec", "ref", "encoding" ){
		$prret->{$_."lc"} = lc($prret->{$_}) if $prret->{$_} ne "";
	}
	
	return($prret);
	
}

sub handleRequest {
	# Handle an HTTP request from a client
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : scalar-ref of request data
	# $_[3] : send "Connection: close"
	
	my ($client, $client_info, $request_ref, $closecon) = @_;
	
	my $headers = parseHeaders($request_ref);
	# ->{method}	: method
	# ->{urideclc}	: URI decoded and in lowercase
	# ... and more.
	
	my $response; # each page of files puts response in this
	# ->{headers}
	# ->{body}
	# ->{code} : HTTP response code if not "200 OK"
	
	print(" < $headers->{uridec}\n"); # DEBUGGING
	
	# HOME PAGE (recorder interface) :
	if( "$headers->{uri}?" =~ m!^/[?&]! ){
		
		$response = pageHome($client, $client_info, $headers);
		
	# AJAX COMMANDS :
	}elsif( $headers->{urideclc} =~ m!^/ajax/! ){
		
		# GET ALL INTERFACE CONTENT :
		if( $headers->{urideclc} =~ m!^/ajax/get-int! ){
			$response = pageInterface($client, $client_info, $headers);
			
		# START RECORDING :
		}elsif( $headers->{urideclc} =~ m!^/ajax/rec-start-(\d+)! ){
			$response = pageAjaxRecStart($client, $client_info, $headers, $1); # $1 = bpm
			
		# STOP RECORDING :
		}elsif( $headers->{urideclc} =~ m!^/ajax/rec-stop! ){
			$response = pageAjaxRecStop($client, $client_info, $headers);
			
		# START PLAYING :
		}elsif( $headers->{urideclc} =~ m!^/ajax/play-start! ){
			$response = pageAjaxPlayStart($client, $client_info, $headers);
			
		# STOP PLAYING (pause) :
		}elsif( $headers->{urideclc} =~ m!^/ajax/play-stop! ){
			$response = pageAjaxPlayPause($client, $client_info, $headers);
			
		# START (go to beginning) :
		}elsif( $headers->{urideclc} =~ m!^/ajax/start! ){
			$response = pageAjaxStart($client, $client_info, $headers);
			
		# PRESSING DELETE BUTTON :
		}elsif( $headers->{urideclc} =~ m!^/ajax/del-open! ){
			$response = pageAjaxDelOpen($client, $client_info, $headers);
			
		# CONFIRMING DELETE :
		}elsif( $headers->{urideclc} =~ m!^/ajax/del-confirm/([\w.-]+)! ){
			$response = pageAjaxDelConfirm($client, $client_info, $headers, $1);
			
		# PRESSING RENAME BUTTON :
		}elsif( $headers->{urideclc} =~ m!^/ajax/ren-open! ){
			$response = pageAjaxRenOpen($client, $client_info, $headers);
			
		# ACTUALLY RENAMING :
		}elsif( $headers->{urideclc} =~ m!^/ajax/ren-confirm/([\w-.]+)/([\w-]*)! ){
			$response = pageAjaxRenConfirm($client, $client_info, $headers, $1, $2);
			
		# NEW PLAYLIST FORM :
		}elsif( $headers->{urideclc} =~ m!^/ajax/newlist-open! ){
			$response = pageAjaxNewlistOpen($client, $client_info, $headers);
			
		# ACTUALLY CREATING NEW PLAYLIST :
		}elsif( $headers->{urideclc} =~ m!^/ajax/newlist-make/([\w-]+)! ){
			$response = pageAjaxNewlistMake($client, $client_info, $headers, $1);
			
		# PRESSING SHUTDOWN BUTTON (from menu) :
		}elsif( $headers->{urideclc} =~ m!^/ajax/shut-open! ){
			$response = pageAjaxShutOpen($client, $client_info, $headers);
			
		# CONFIRMING SHUTDOWN :
		}elsif( $headers->{urideclc} =~ m!^/ajax/shut-confirm! ){
			$response = pageAjaxShutConfirm($client, $client_info, $headers);
			
		# PROGRESS BAR CLICK (relocate) :
		}elsif( $headers->{urideclc} =~ m!^/ajax/prog-([\d.]+)-([\d.]+)! ){
			$response = pageAjaxBar($client, $client_info, $headers, $1, $2);
			
		# SET OPTION (e.g. repeat) :
		}elsif( $headers->{uridec} =~ m!^/ajax/setconf/(\w+)/(.+)! ){
			my $var = $1;
			my $value = $2;
			
			$conf->{$var} = $value;
			fdbset($conf->{confFile}, { $var => $value } );
			
			my $status;
			# Changing playlist :
			if( $var eq "currentFolder" ){
				$status = fdbget($conf->{statusFile});
				buildPlaylist($status);
			}
			
			$response = pageInterface($client, $client_info, $headers, $status);
			
		# RATE CURRENT SONG :
		}elsif( $headers->{urideclc} =~ m!^/ajax/rate-(\d)! ){
			$response = pageAjaxRate($client, $client_info, $headers, $1);
			
		# CHANGE BPM OF CURRENT SONG :
		}elsif( $headers->{urideclc} =~ m!^/ajax/bpm-(\d+)! ){
			
			pageAjaxPlayPause($client, $client_info, $headers); # pause if playing
			$response = pageAjaxBpm($client, $client_info, $headers, $1);
			
		# SELECT A SONG IN PLAYLIST :
		}elsif( $headers->{urideclc} =~ m!^/ajax/selectsong-([\w.-]+)! ){
			my $fn = $1;
			
			my $playlist = fdbget("$conf->{ramfsPath}/playlist");
			
			my $status = fdbset($conf->{statusFile}, {
				selected_file	=> $1,
				play_duration	=> $playlist->{"$fn.d"},
				play_position	=> 0,
			} );
			
			if( $status->{player_status} eq "play" ){
				pageAjaxPlayPause($client, $client_info, $headers, $status, 0);
				$response = pageAjaxPlayStart($client, $client_info, $headers);
			}else{
				$response = pageInterface($client, $client_info, $headers, $status, 1);
			}
			
		# OPEN THE MENU :
		}elsif( $headers->{urideclc} =~ m!^/ajax/menu! ){
			$response = pageMenu($client, $client_info, $headers);
			
		# UNKNOWN COMMAND :
		}else{
			$response->{code} = "404 Not Found";
			$response->{body} = "Unknown AJAX command\n";
		}
		
		$response->{headers} = "Content-Type: text/plain; charset=UTF-8\nCache-Control: no-cache, no-store, max-age=0, must-revalidate\nPragma: no-cache\nExpires: Fri, 01 Jan 1990 00:00:00 GMT\n"
			if $response->{headers} eq "";
		
	# UNKNOWN URI :
	}else{
		$response->{code} = "404 Not Found";
		$response->{headers} = "Content-Type: text/plain; charset=UTF-8\n";
		$response->{body} = "\"$headers->{uri}\" is not found\n";
	}
	
	
	# PREPARE HEADERS AND PRINT RESPONSE :
	$response->{headers} =~ s/\n+/\r\n/g;
	my $body_length = length $response->{body};
	$response->{headers} =~ s/[\r\n]*$/\r\nContent-Length: $body_length\r\n/;
	$response->{headers} .= "Connection: close\r\n" if $closecon;
	
	print($client "HTTP/1.1 ".( $response->{code} || "200 OK" )."\r\n$response->{headers}\r\n$response->{body}");
	
	fdbset($conf->{statusFile}, { lastLocalRequest => time }) if $client_info->{ip} eq "127.0.0.1";
	
	return(1);
	
}

sub pageHome {
	# Returns the home page (interface)
	# The images are embedded in the css (encoded in base64)
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	
	my ($client, $client_info, $headers) = @_;
	
	my $response;
	
	$response->{headers} = "Content-Type: text/html; charset=UTF-8\n";
	
	$response->{body} = "<!DOCTYPE html>
<html>
<head>
<title>MIDI Recorder</title>
<style>

* {
	position:relative;
	margin:0;
	padding:0;
	font-family:inherit;
	line-height:100%;
	cursor:default;
	outline:none;
	outline-style:none;
	-moz-outline-style:none;
	-webkit-appearance:none;
	background-repeat:no-repeat;
	border-radius:0;
	text-rendering:optimizeLegibility;
	touch-action:manipulation;
}
select {
	-webkit-appearance:menulist;
}
input[type=\"search\"], input[type=\"text\"]{
	-webkit-appearance:textfield;
}
input[type=\"checkbox\"]{
	-webkit-appearance:checkbox;
}

html, body {
	width:100%;
	height:100%;
	background-color:#000000;
	font-family:arial,verdana;
	text-align:center;
	overflow:hidden;
	-webkit-touch-callout:none;
	-webkit-user-select:none;
	-khtml-user-select:none;
	-moz-user-select:none;
	-ms-user-select:none;
	user-select:none;
}

/* CONTROL PANEL : */
#ctrl {
	position:absolute;
	right:0;
	top:0;
	bottom:0;
	width:20%;
	height:100%;
	background-color:#bababa;
	font-size:90px; /* javascript makes is dynamic based on window size */
}
	
	/* TIMECODE : */
	#ctrl #time {
		position:absolute;
		top:0;
		left:0;
		right:0;
		width:100%;
		height:15%;
	}
		
		#ctrl #time div {
			display:block;
			position:absolute;
			left:0;
			right:0;
			width:100%;
			text-align:center;
		}
		#ctrl #time div:nth-of-type(1) {
			height:auto;
			bottom:50%;
		}
		#ctrl #time div:nth-of-type(2) { /* TOTAL TIME (BOTTOM) */
			top:50%;
			height:50%;
		}
		
		#ctrl #time div span { /* CURRENT TIME (TOP) */
			padding:0 20px 2px 20px;
			border-bottom:1px solid #484848;
		}
		
		#ctrl #time div span, #ctrl #time div:nth-of-type(2) {
			font-size:43%;
			line-height:130%;
			color:#202020;
			letter-spacing:1px;
		}
		
	
	#nbdisk {
		position:absolute;
		top:0;
		right:0;
		padding:4px 6px 4px 6px;
		font-size:27%;
		color:#38ff38;
		text-align:right;
		background-color:#484848;
	}
	
	/* TEMPO : */
	#ctrl #bpmwrp {
		display:table;
		position:absolute;
		left:12%;
		right:12%;
		width:76%;
		top:14%;
		height:11%;
	}
		
		#ctrl #bpmwrp div {
			display:table-cell;
			vertical-align:middle;
			width:25%;
			font-size:43%;
			line-height:130%;
			color:#202020;
			cursor:pointer;
		}
		#ctrl #bpmwrp div#bpm { /* BPM NUMBER */
			width:50%;
			cursor:default;
		}
		
	
	/* RATING STARS : */
	#ctrl #rating {
		position:absolute;
		left:3%;
		right:3%;
		top:25%;
		height:9%;
		cursor:pointer;
		background-size:200% auto;
	}
	
	#ctrl #rating, #list .song div:nth-of-type(6) {
		background-image:url(data:image/png;base64,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P994/+D9g9gH+yD2cerd3+l/uI/KykoxxijnHC644AKsWbNGtm3b5qLRqL3zzjt5/yD2cRr3Qfz3c/bB+wexD/ZB7OPI+hD+wxcRERERERERERERERERERGgeAmIiIiIiIiIiIiIiIiIiIj4AJ2IiIiIiIiIiIiIiIiIiAgAH6ATEREREREREREREREREREB4AN0IiIiIiIiIiIiIiIiIiIiAHyATkREREREREREREREREREBIAP0ImIiIiIiIiIiIiIiIiIiADwAToREREREREREREREREREREAPkAnIiIiIiIiIiIiIiIiIiICwAfoREREREREREREREREREREAPgAnYiIiIiIiIiIiIiIiIiICAAfoBMREREREREREREREREREQHgA3QiIiIiIiIiIiIiIiIiIiIAfIBOREREREREREREREREREQEgA/QiYiIiIiIiIiIiIiIiIiIAPABOhEREREREREREREREREREQA+QCciIiIiIiIiIiIiIiIiIgLAB+hEREREREREREREREREREQA+ACdiIiIiIiIiIiIiIiIiIgIAB+gExERERERERERERERERERAeADdCIiIiIiIiIiIiIiIiIiIgB8gE5ERERERERERERERERERASAD9CJiIiIiIiIiIiIiIiIiIgA8AE6ERERERERERERERERERERAD5AJyIiIiIiIiIiIiIiIiIiAgD8/wEAhkpBxbCU0DYAAAAASUVORK5CYII=);
	}
	.star0 {
		background-position:100% center;
	}
	.star1 {
		background-position:80% center;
	}
	.star2 {
		background-position:60% center;
	}
	.star3 {
		background-position:40% center;
	}
	.star4 {
		background-position:20% center;
	}
	.star5 {
		background-position:0 center;
	}
	
	
	/* BUTTONS : */
	#ctrl #buts {
		position:absolute;
		left:5%;
		right:5%;
		bottom:1%;
		height:63%;
	}
		
		#ctrl #buts a {
			display:block;
			float:left;
			width:50%;
			height:25%;
			cursor:pointer;
			background-image:url('data:image/png;base64,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AAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwADAACQAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAMAAJwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMAAxAAjAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwADkAAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwADAACQAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAMAAJwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMAAxAAjAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMADAAwAAAAwAMAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwAMADAAAADAAwADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADAAwAMAAAAMADABYAS1dc0ohZB1WAAAAAElFTkSuQmCC');
			background-size:auto 2100%;
		}
		
		/* BUTTON RENAME : */
		#ctrl #buts a#but_ren {
			background-position:center 0;
		}
		/* BUTTON MENU : */
		#ctrl #buts a#but_men {
			background-position:center 5.25%;
		}
		/* BUTTON DELETE : */
		#ctrl #buts a#but_del {
			background-position:center 10.5%;
		}
		/* BUTTON CONTINUE TO NEXT FILE : */
		#ctrl #buts a#but_con {
			background-position:center 15.75%;
		}
		#ctrl #buts a#but_con.ena {
			background-position:center 21%;
		}
		/* BUTTON GO TO START : */
		#ctrl #buts a#but_sta {
			background-position:center 26.25%;
		}
		/* BUTTON REPEAT : */
		#ctrl #buts a#but_rep {
			background-position:center 31.5%;
		}
		#ctrl #buts a#but_rep.ena {
			background-position:center 36.75%;
		}
		/* BUTTON PLAY : */
		#ctrl #buts a#but_ply {
			background-position:center 42%;
		}
		#ctrl #buts a#but_ply.pause {
			background-position:center 47.25%;
		}
		/* BUTTON REC : */
		#ctrl #buts a#but_rec {
			background-position:center 52.5%;
		}
		#ctrl #buts a#but_rec.stop {
			background-position:center 57.75%;
		}
		
	
.loading, #ctrl #buts a.loading {
	background-image:url(data:image/gif;base64,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);
	background-position:center center;
	background-size:auto 70%;
}

/* FILES LIST : */
#list {
	position:absolute;
	left:0;
	top:0;
	width:80%;
	height:91%;
	background-color:#181818;
	overflow-y:scroll;
}
::-webkit-scrollbar {
    width:36px;
    background:#0a0a0a;
}

::-webkit-scrollbar-thumb {
    background:#2b3742;
}

	
	#list .song {
		height:13.4%;
		background:#181818;
		background:-webkit-linear-gradient(rgb(13,20,26) , rgb(21,30,41));
		background:-o-linear-gradient(rgb(13,20,26) , rgb(21,30,41));
		background:-moz-linear-gradient(rgb(13,20,26) , rgb(21,30,41));
		background:linear-gradient(rgb(13,20,26) , rgb(21,30,41));
		border-bottom:1px solid #233140;
	}
	
	/* TODO :
		Have 2 slightly different BG gradient colors, and we will alternate to
		group files together based on their date/time.
		e.g. if 3 files were recorded at 20 minutes interval, they get the same bg,
		then the next file in list was 8 hours before, it changes bg color slightly.
	*/
	
	#list .sel {
		background:-webkit-linear-gradient(rgb(5,32,56) , rgb(4,39,79));
		background:-o-linear-gradient(rgb(5,32,56) , rgb(4,39,79));
		background:-moz-linear-gradient(rgb(5,32,56) , rgb(4,39,79));
		background:linear-gradient(rgb(5,32,56) , rgb(4,39,79));
	}
	
		
		/* Song content elements : */
		#list .song div {
			position:absolute;
			font-size:38%;
			color:#e8e8e8;
			white-space:nowrap;
		}
		
		/* DATE yyyy-mm-dd : */
		#list .song div:nth-of-type(1) {
			top:21%;
			left:6%;
		}
		
		/* TIME X.XXpm : */
		#list .song div:nth-of-type(2) {
			bottom:21%;
			left:6%;
			font-size:27%;
			color:#a0a0a0;
		}
		
		/* DURATION M:SS : */
		#list .song div:nth-of-type(3) {
			top:21%;
			left:28%;
		}
		
		/* BPM : */
		#list .song div:nth-of-type(4) {
			bottom:21%;
			left:28%;
			font-size:27%;
			color:#a0a0a0;
		}
		
		/* SONG TITLE : */
		#list .song div:nth-of-type(5) {
			top:21%;
			left:47%;
		}
		
		/* RATING STARS : */
		#list .song div:nth-of-type(6) {
			bottom:10%;
			left:47%;
			height:41%;
			width:8%;
			background-size:200% auto;
		}
		
		/* MIDI file download link : */
		#list .song a {
			position:absolute;
			bottom:21%;
			left:58%;
			font-size:25%;
			color:#12d800;
			cursor:pointer;
		}
		
	

/* PROGRESS BAR : */
#progwrp {
	position:absolute;
	left:0;
	bottom:0;
	width:80%;
	height:9%;
	background-color:#282828;
	overflow:hidden;
}
	#progwrp nav {
		float:left;
		height:100%;
		width:12.5%;
		border-right:1px dotted #ffffff;
		opacity:0.27;
	}
	#progwrp nav.b {
		opacity:0.07;
	}
	
	#prog {
		position:absolute;
		left:0;
		top:0;
		bottom:0;
		height:100%;
		width:0%;
		background-color:#1d66bf;
	}
	#prog.recording {
		background-color:#ff0000;
		width:100%;
	}

/* OVERLAY : */
#ovr {
	display:none;
	position:absolute;
	top:0;
	bottom:0;
	left:0;
	right:0;
	z-index:10;
	background-color:rgba(0,0,0, 0.95);
}
#ovr.visible {
	display:block;
}
	
	#ovrcon {
		position:absolute;
		top:9%;
		bottom:8%;
		left:6%;
		right:6%;
		font-size:36%;
		color:#ffffff;
		text-align:center;
	}
	
	#ren_input, #plylst_input { /* Text Input to rename a song or new playlist */
		display:block;
		position:absolute;
		top:10%;
		left:0;
		width:70%;
		padding:0 0 0 9px;
		font-weight:bold;
		font-size:110%;
		line-height:200%;
		background-color:#b0b0b0;
		color:#383838;
		border-radius:8px;
		cursor:text;
	}
	
	a.button {
		display:block;
		position:absolute;
		font-weight:bold;
		font-size:110%;
		line-height:200%;
		background-color:#b0b0b0;
		color:#383838;
		border-radius:8px;
		cursor:pointer;
	}
	
	a#ovrclose {
		position:absolute;
		top:0;
		right:0;
		padding:2% 2.5% 2% 2.5%;
		font-size:60%;
		color:#ffffff;
		cursor:pointer;
	}
	
	/* ===== MENU ELEMENTS : ===== */
	
	#menu_midiin, #menu_midiout {
		position:absolute;
		top:0;
		width:40%;
		text-align:left;
	}
	#menu_midiin {
		left:0;
	}
	#menu_midiout {
		left:50%;
	}
		#menu_midiin label, #menu_midiout label {
			display:block;
			padding:0 0 8px 0;
		}
		#menu_midiin select, #menu_midiout select {
			display:block;
			width:100%;
			font-size:100%;
			line-height:150%;
			background-color:#606060;
			color:#ffffff;
			border:0;
			border-radius:8px;
			cursor:pointer;
		}
	
	#menu_noteoff {
		position:absolute;
		left:50.7%;
		top:15%;
		text-align:left;
	}
	#menu_noteoff input { /* checkbox */
		-ms-transform: scale(2);
		-moz-transform: scale(2);
		-webkit-transform: scale(2);
		-o-transform: scale(2);
		cursor:pointer;
	}
	#menu_noteoff label {
		margin-left:20px;
		cursor:pointer;
	}
	
	#menu_usb {
		position:absolute;
		left:0;
		top:30%;
		width:100%;
		text-align:left;
	}
		#menu_usb label {
			line-height:175%;
		}
		
		#menu_usb div { /* each drive */
			border-top:1px dotted #808080;
		}
		#menu_usb div:last-of-type {
			border-bottom:1px dotted #686868;
		}
			
			#menu_usb div nav:nth-of-type(1) {
				text-indent:25px;
			}
			#menu_usb div nav {
				display:inline-block;
				font-size:84%;
				line-height:175%;
				width:50%;
			}
			
		
	
	#menu_ply {
		position:absolute;
		left:0;
		top:66%;
		width:100%;
		text-align:left;
	}
		#menu_ply label {
			display:block;
			padding:0 0 8px 0;
		}
		#menu_ply select {
			display:block;
			width:40%;
			font-size:100%;
			line-height:150%;
			background-color:#606060;
			color:#ffffff;
			border:0;
			border-radius:8px;
			cursor:pointer;
		}
	
	#menu_shut { /* <a> */
		position:absolute;
		display:block;
		left:0;
		top:92%;
		width:40%;
		border:1px solid #ff0000;
		background-color:#a00000;
		color:#ffffff;
		font-weight:bold;
		line-height:200%;
		border-radius:8px;
		cursor:pointer;
	}
	
	#menu_shut_info {
		position:absolute;
		left:50%;
		top:95%;
		font-size:80%;
		color:#a0a0a0;
	}
	
	

#kbd {
	display:none;
	position:absolute;
	z-index:99;
	bottom:0;
	height:54%;
	left:0;
	right:0;
	background-color:#b0b0b0;
}
#kbd.visible {
	display:block;
}
	
	#kbd div { /* Row of characters */
		height:25%;
		border-bottom:1px dotted #5c5c5c;
		margin-top:-1px;
	}
	#kbd div:nth-of-type(1) {
		margin-top:0;
	}
	#kbd div:last-of-type {
		border-bottom:0;
	}
		
		#kbd div a { /* Character */
			
			/* TO CENTER VERTICALLY : */
			display:block;
			display:-webkit-box;
			display:-webkit-flex;
			display:-moz-box;
			display:-ms-flexbox;
			display:flex;
			/* Vertical center : */
			-webkit-box-orient:vertical;
			-webkit-box-pack:center;
			-webkit-align-items:center;
			-moz-box-orient:vertical;
			-moz-box-pack:center;
			-ms-flex-align:center;
			align-items:center;
			
			/* TO CENTER HORIZONTALLY : */
			-webkit-box-align:center;
			-webkit-justify-content:center;
			-moz-box-align:center;
			justify-content:center;
			
			float:left;
			height:100%;
			font-size:37%;
			line-height:100%;
			border-right:1px dotted #5c5c5c;
			margin-left:-1px;
			cursor:pointer;
		}
		#kbd div a:nth-of-type(1) {
			margin-left:0;
		}
		#kbd div a:last-of-type {
			border-right:0;
		}
		
		#kbd div:nth-of-type(1) a {
			width:8%;
		}
		#kbd div:nth-of-type(2) a {
			width:10%;
		}
		#kbd div:nth-of-type(3) a {
			width:10.4%;
		}
		#kbd div:nth-of-type(3) a:last-of-type {
			border-right:1px dotted #5c5c5c;
		}
		
		#kbd div:nth-of-type(4) a {
			width:10%;
		}
		
	
	

</style>
</head>
<body>

<div id=ctrl>
	
	<div id=time>
		<div>
			<span id=time_cur>0:00</span>
		</div>
		<div id=time_tot>0:00</div>
	</div>
	
	<div id=nbdisk></div>
	
	<div id=bpmwrp>
		<div id=bpmm>-</div>
		<div id=bpm>120</div>
		<div id=bpmp>+</div>
	</div>
	
	<div id=rating class=star0></div>
	
	<div id=buts>
		<a id=but_ren></a>
		<a id=but_men onclick=\"sendRequest('menu')\"></a>
		<a id=but_del></a>
		<a id=but_con></a>
		<a id=but_sta></a>
		<a id=but_rep></a>
		<a id=but_ply></a>
		<a id=but_rec></a>
	</div>
	
</div>

<div id=list></div>

<div id=progwrp>
	<div id=prog></div>
	<nav class=b></nav>
	<nav></nav>
	<nav class=b></nav>
	<nav></nav>
	<nav class=b></nav>
	<nav></nav>
	<nav class=b></nav>
</div>


<div id=ovr>
	<div id=ovrcon></div>
	<a id=ovrclose onclick=\"eleOvr.className='';eleKbd.className=''\">X</a>
</div>


<div id=kbd>
	<div>
		<a>1</a><a>2</a><a>3</a><a>4</a><a>5</a><a>6</a><a>7</a><a>8</a><a>9</a><a>0</a><a style=\"width:8.5%;font-size:65%;font-weight:bold\">&larr;</a><a style=\"width:11.5%\">CLEAR</a>
	</div>
	<div>
		<a>Q</a><a>W</a><a>E</a><a>R</a><a>T</a><a>Y</a><a>U</a><a>I</a><a>O</a><a>P</a>
	</div>
	<div>
		<a>A</a><a>S</a><a>D</a><a>F</a><a>G</a><a>H</a><a>J</a><a>K</a><a>L</a>
	</div>
	<div>
		<a>Z</a><a>X</a><a>C</a><a>V</a><a>B</a><a>N</a><a>M</a><a style=\"width:30%\">SPACE</a>
	</div>
	
	
	
	
</div>

<script>
	
	var istouch = 'ontouchstart' in document.documentElement; // true if touch browser
	
	var eleCtrl = gebi('ctrl');
	var eleList = gebi('list');
	var eleOvr = gebi('ovr');
	var eleOvrCon = gebi('ovrcon');
	
	var eleKbd = gebi('kbd');
	var kbdInp;
	
	var eleNbDisk = gebi('nbdisk');
	var eleButPly = gebi('but_ply');
	var eleButRec = gebi('but_rec');
	var eleButSta = gebi('but_sta');
	var eleButCon = gebi('but_con');
	var eleButRep = gebi('but_rep');
	var eleButDel = gebi('but_del');
	var eleButRen = gebi('but_ren');
	var eleProg = gebi('prog');
	var eleProgWrp = gebi('progwrp');
	var eleRating = gebi('rating');
	var eleBpm = gebi('bpm');
	var eleBpmP = gebi('bpmp');
	var eleBpmM = gebi('bpmm');
	var eleTimeCur = gebi('time_cur');
	var eleTimeTot = gebi('time_tot');
	
	var bpm = 120; // bpm of current song
	var lastBpmClick = 0; // last time we clicked +/- to change bpm so we dont force it while we adjust
	var duration = 0; // duration of current song in seconds
	var elapsed = 0; // COUNTER of elapsed seconds in current song
	var elapsedCompensation = 0; // when making a request to update player status, add half the time of the request to elasped
	var timerStatus = 0; // 1=playing ; 2=recording ; so that we update elapsed/duration and progress bar
	
	var updateIn = 0; // count down timer so we update entire interface content every N/10 seconds
	
	
	// ==================== SHORTCUT FUNCTIONS : ====================
	
	// Shortcut to function getElementById
	function gebi(d){
		return document.getElementById(d);
	}
	
	// Substitute of function addEventListener for browsers that dont support it
	function ael(ele, evt, func){
		if(!ele) return;
		if( ele.addEventListener ){
			ele.addEventListener(evt, func, true);
		}else{
			ele.attachEvent('on'+evt, func);
		}
	}
	
	// Create an AJAX object
	function newAjax(){
		if( window.XMLHttpRequest ){ // IE7+, Firefox, Chrome, Opera, Safari
			return new XMLHttpRequest();
		}else{ // IE6, IE5
			return new ActiveXObject('Microsoft.XMLHTTP');
		}
	}
	
	// ==================== SEND REQUEST TO BACK-END : ====================
	function sendRequest(cmd, e, s){
		// cmd : command string to send (e.g. 'play-stop')
		// e : OPTIONAL element to put loading icon into and restore as soon as request received
		// s : make sync request (wait for response)
		
		var ajax = newAjax();
		if( ajax ){
			
			var eClass;
			var eColor;
			if(e){
				eClass = e.className;
				e.className += ' loading';
				eColor = e.style.color;
				e.style.color = 'rgba(255,255,255,0)';
				if( eClass == 'loading' ) eClass = '';
			}
			
			var requestStart = ( new Date() ).getTime();
			
			// Syncronous :
			if( s ){
				
				ajax.open('GET', '/ajax/'+cmd, false);
				ajax.send();
				
				if(typeof eClass !== 'undefined'){
					e.className = eClass;
					e.style.color = eColor;
				}
				
				// SUCCESS :
				if( ajax.status==200 ){
					
					var requestEnd = ( new Date() ).getTime();
					elapsedCompensation = (requestEnd - requestStart) / 2000;
					if( elapsedCompensation > 3 ) elapsedCompensation = 0.15; // to fix a potential bug
					
					// Each line in response updates something.
					// e.g. 'PLAYER\tbut_rec=stop' updates element 'but_rec' to set class to 'stop'
					//      the next line may update the play list content e.g. in this same response.
					
					parseResponse(ajax.responseText);
					
				// FAILED :
				}else if( ajax.responseText != '' ){
					
					alert(ajax.responseText);
					
				}
				
			// Asyncronous :
			}else{
				
				ajax.open('GET', '/ajax/'+cmd, true);
				ajax.send();
				
				ajax.onreadystatechange=function(){
					if( ajax.readyState==4 ){
						
						if(typeof eClass !== 'undefined'){
							e.className = eClass;
							e.style.color = eColor;
						}
						
						// SUCCESS :
						if( ajax.status==200 ){
							
							var requestEnd = ( new Date() ).getTime();
							elapsedCompensation = (requestEnd - requestStart) / 2000;
							if( elapsedCompensation > 3 ) elapsedCompensation = 0.15; // to fix a potential bug
							
							// Each line in response updates something.
							// e.g. 'PLAYER\tbut_rec=stop' updates element 'but_rec' to set class to 'stop'
							//      the next line may update the play list content e.g. in this same response.
							
							parseResponse(ajax.responseText);
							
						// FAILED :
						}else if( ajax.responseText != '' ){
							
							alert(ajax.responseText);
							
						}
						
					}
				}
				
			}
			
		}
	}
	
	
	// ==================== UPDATE INTERFACE FROM AJAX RESPONSE : ====================
	
	function parseResponse(r) {
		// Parse an AJAX response and call other functions to update the interface
		// r : response body
		
		// Each line wants to update a certain thing in the interface (e.g. player status, progress bar, playlist)
		var lines = r.split('\\n');
		for( var i=0, imax=lines.length ; i<imax ; i++ ){
			
			var data = lines[i].split('\\t');
			
			// PLAYER STATUS :
			if( data[0] == 'PLAYER' ){
				updatePlayer(data);
				updateIn = 30;
				
			// PLAYLIST CONTENT :
			}else if( data[0] == 'PLAYLIST' ){
				updatePlayList(data);
				updateIn = 30;
				
			// PUT SOME CONTENT IN THE OVERLAY & OPEN IT :
			}else if( data[0] == 'OVERLAY' ){
				openOverlay(data[1]);
				
			// PUT AN ELEMENT IN FOCUS (typically input when renaming) :
			}else if( data[0] == 'FOCUS' ){
				
				var ele = gebi(data[1]);
				if(ele) setTimeout( function(e){ e.focus() }, 100, ele );
				
			// OPEN THE KEYBOARD TO TYPE IN AN INPUT :
			}else if( data[0] == 'KEYBOARD' ){
				
				setTimeout( function(id){ openKeyboard(id) }, 100, data[1] );
				
			}
			
		}
		
	}
	
	
	// ==================== PLAYER STATUS : ====================
	
	function updatePlayer(data){
		// data : array of things to update
		
		for( var i=1, imax=data.length ; i<imax ; i++ ){
			
			// Set a certain class to an element (id) :
			// (typically for all buttons and rating)
			if( data[i].match(/^setIdClass:/) ){
				var id = data[i].replace(/^setIdClass:/, '').replace(/(\\w+):.*\$/, '\$1');
				var cls = data[i].replace(/^setIdClass:\\w+:/, '');
				var ele = gebi(id);
				if( ele && ele.className != cls ) ele.className = cls;
				
			// Progress bar play position :
			}else if( data[i].match(/^prog:[\\d.]+\$/) ){
				if( timerStatus == 0 ) eleProg.style.width = data[i].replace(/^prog:/, '')+'%';
				// so we dont update it if we are playing
				
			// BPM of current song :
			}else if( data[i].match(/^bpm:\\d/) ){
				
				if( lastBpmClick < new Date().getTime() - 5000 ){
					bpm = parseInt( data[i].replace(/^bpm:/, '') );
					eleBpm.innerHTML = bpm;
				}
				
			// Duration of current song (in seconds) :
			}else if( data[i].match(/^duration:\\d/) ){
				duration = data[i].replace(/^duration:/, '');
				if( duration == '0' ){
					eleTimeTot.innerHTML = '';
				}else{
					eleTimeTot.innerHTML = secToTime(duration);
				}
				
			// Position in current song (in seconds) :
			}else if( data[i].match(/^elapsed:\\d/) ){
				elapsed = parseFloat( data[i].replace(/^elapsed:/, '') ) + elapsedCompensation;
				eleTimeCur.innerHTML = secToTime(elapsed);
				
			// Set timer status (stopped / playing / recording) :
			}else if( data[i].match(/^timer:\\d+\$/) ){
				timerStatus = parseInt( data[i].replace(/^timer:/, '') );
				
			// Number of mounted USB drives :
			}else if( data[i].match(/^nbdisk:\\d+\$/) ){
				eleNbDisk.innerHTML = data[i].replace(/^nbdisk:/, '');
				
			}
			
		}
		
	}
	
	
	// ==================== PLAYLIST : ====================
	
	function updatePlayList(data){
		// data : array of playlist new content
		// NOTE: only updated when the list has changed (e.g. after recording or delete)
		//       because we loose the selection and scrolling position
		
		var playlistHtml = '';
		
		// Each tab-seperated element is a song :
		for( var i=1, imax=data.length ; i<imax ; i++ ){
			
			var info = data[i].split('\\|');
			// [0] : base filename 'YYYYMMDD-HHMMSS'
			// [1] : date 'YYYY-MM-DD'
			// [2] : time of day 'H.MM pm'
			// [3] : duration in seconds
			// [4] : bpm original
			// [5] : bpm new
			// [6] : Song Title
			// [7] : Rating (0-5, 0 means not-rated)
			// [8] : 1 if selected
			// [9] : 1 if MIDI file download
			
			playlistHtml += '<div class='+( info[8] == '1' ? '\"song sel\"' : 'song' )+' id=\"'+info[0]+'\" onclick=\"songSelect(this)\" data-d=\"'+info[3]+'\" data-bo=\"'+info[4]+'\" data-bn=\"'+info[5]+'\" data-t=\"'+info[6]+'\" data-r=\"'+info[7]+'\"><div>'+info[1]+'</div><div>'+info[2]+'</div><div>'+secToTime(info[3])+'</div><div>'+info[4]+(info[5] != info[4] ? ' > '+info[5] : '')+' bpm</div><div>'+info[6]+'</div><div class=star'+info[7]+'></div>';
			
			if( info[9] == '1' ) playlistHtml += '<a href=\"/dl/'+songToFilename(info[0],info[6],info[4],info[5],info[7])+'\" target=_blank>MIDI file</a>';
			
			playlistHtml += '</div>';
			
		}
		
		eleList.innerHTML = playlistHtml;
		
	}
	
	// ==================== OVERLAY : ====================
	
	function openOverlay(data){
		// data : html content to put in #ovrcon
		
		ovrcon.innerHTML = data;
		ovr.className = 'visible';
		
	}
	
	// ==================== KEYBOARD : ====================
	
	function openKeyboard(input_id){
		// input_id : element id of the input to type in
		
		kbdInp = gebi(input_id);
		if( !kbdInp ) return;
		
		var inpLength = kbdInp.value.length;
		kbdInp.selectionStart = inpLength;
		kbdInp.selectionEnd = inpLength;
		
		eleKbd.className = 'visible';
		
	}
	
	function songSelect(e){
		// Clicking a song in the playlist
		// e : element clicked
		
		lastBpmClick = 0;
		
		var ds = e.dataset;
		var fn = songToFilename(e.id, ds.t, ds.bo, ds.bn, ds.r);
		
		sendRequest('selectsong-'+fn);
		
		return 1;
	}
	
	function songToFilename(b,t,bo,bn,r){
		// Return a MIDI filename for a song
		// b  : base filename 'YYYYMMDD-HHMMSS'
		// t  : song title
		// bo : bpm original
		// bn : bpm new
		// r  : rating
		
		return b
			+'-'+t.toLowerCase().replace(/ /g,'-')
			+'-'+( bn != '' ? bn : bo )
			+'-'+r+'.mid';
		
	}
	
	function secToTime(s){
		// Return a time '1:59' from seconds 119
		
		s = Math.round( parseFloat(s) );
		var min = Math.floor(s / 60);
		var sec = s - min*60;
		if(sec < 10) sec = '0'+sec;
		
		return(min+':'+sec);
		
	}
	
	
	if( istouch ){
		
		ael( eleButPly, 'touchstart', pressPlay );
		ael( eleButRec, 'touchstart', pressRec );
		ael( eleButSta, 'touchstart', pressStart );
		ael( eleButRep, 'touchstart', setconfRepeat );
		ael( eleButCon, 'touchstart', setconfContinue );
		ael( eleButDel, 'touchstart', pressDel );
		ael( eleButRen, 'touchstart', pressRen );
		
		ael( eleBpmP, 'touchstart', function(){ bpmClick(1) });
		ael( eleBpmM, 'touchstart', function(){ bpmClick(-1) });
		ael( eleBpm, 'touchstart', function(){ bpmClick(0) });
		
		ael( eleRating, 'touchstart', ratingClick);
		ael( eleProgWrp, 'touchstart', barClick );
		
	}else{
		
		ael( eleButPly, 'mousedown', pressPlay );
		ael( eleButRec, 'mousedown', pressRec );
		ael( eleButSta, 'mousedown', pressStart );
		ael( eleButRep, 'mousedown', setconfRepeat );
		ael( eleButCon, 'mousedown', setconfContinue );
		ael( eleButDel, 'mousedown', pressDel );
		ael( eleButRen, 'mousedown', pressRen );
		
		ael( eleBpmP, 'mousedown', function(){ bpmClick(1) });
		ael( eleBpmM, 'mousedown', function(){ bpmClick(-1) });
		ael( eleBpm, 'mousedown', function(){ bpmClick(0) });
		
		ael( eleRating, 'mousedown', ratingClick);
		ael( eleProgWrp, 'mousedown', barClick );
		
	}
	
	ael( eleKbd, 'click', kbdPress );
	
	function pressPlay(){
		bpmSend();
		if( eleButPly.className == 'pause' ){
			sendRequest('play-stop', eleButPly);
		}else{
			sendRequest('play-start', eleButPly);
		}
	}
	
	function pressRec(){
		if( eleButRec.className == 'stop' ){
			sendRequest('rec-stop', eleButRec);
		}else{
			sendRequest('rec-start-'+bpm, eleButRec);
		}
	}
	
	function pressStart(){
		bpmSend();
		sendRequest('start', eleButSta);
	}
	
	function setconfRepeat(){
		if( eleButRep.className == 'ena' ){
			sendRequest('setconf/repeat/0', eleButRep);
		}else{
			sendRequest('setconf/repeat/1', eleButRep);
		}
	}
	
	function setconfContinue(){
		if( eleButCon.className == 'ena' ){
			sendRequest('setconf/continue/0', eleButCon);
		}else{
			sendRequest('setconf/continue/1', eleButCon);
		}
	}
	
	function pressDel(){
		sendRequest('del-open', eleButDel);
	}
	
	function pressRen(){
		sendRequest('ren-open', eleButRen);
	}
	
	function bpmClick(x){
		// Clicking + or - to change bpm
		// x : 1=plus -1=minus 0=reset to original
		
		if( x == 0 ){
			bpm = 0;
			lastBpmClick = 0;
			bpmSend(1);
		}else{
			bpm += x;
			eleBpm.innerHTML = bpm;
			lastBpmClick = new Date().getTime();
		}
		
	}
	
	function bpmSend(f){
		// Send BPM to back-end
		// f : force to send right now
		
		// if( lastBpmClick == 0 || !f && new Date().getTime() < lastBpmClick + 1500 ) return; // not time to send yet
		if( !f && lastBpmClick == 0 ) return;
		
		lastBpmClick = 0;
		sendRequest('bpm-'+bpm, false, true);
		
	}
	
	function ratingClick(e){
		
		var clkx = e.pageX || e.touches[0].pageX;
		var clkLeft = clkx - eleRating.getBoundingClientRect().left; // X position in stars png
		var clkWidth = eleRating.clientWidth; // Total width of all 5 stars
		var clkRating = Math.ceil( 5 * clkLeft / clkWidth ); // From 1 to 5
		
		sendRequest('rate-'+clkRating);
		
	}
	
	function barClick(e) {
		// Click/Touch the progress bar so relocate player
		
		var clkx = e.pageX || e.touches[0].pageX;
		var barw = eleProgWrp.clientWidth;
		
		sendRequest('prog-'+clkx+'-'+barw );
		
	}
	
	function kbdPress(v){
		// Pressing a key on the keyboard
		// v : event on #kbd (NOT on the <a> tag of the key)
		
		var e = v.target || v.toElement || v.relatedTarget; // Element clicked
		
		if( e.tagName.toLowerCase() != 'a' ) return false;
		v.preventDefault();
		
		if( !kbdInp ) return false;
		
		var inpVal = kbdInp.value;
		var inpBefore = inpVal.substring(0, kbdInp.selectionStart);
		var inpAfter = inpVal.substring(kbdInp.selectionEnd);
		
		var letter = e.innerHTML;
		
		if( letter == 'SPACE' ){
			letter = ' ';
			
		}else if( letter == 'CLEAR' ){
			letter = '';
			inpBefore = '';
			inpAfter = '';
			
		// Backspace :
		}else if( !letter.match(/^[a-z\\d]\$/i) ){
			
			if( kbdInp.selectionStart == kbdInp.selectionEnd )
				inpBefore = inpBefore.substring(0, inpBefore.length - 1);
			
			letter = '';
		}
		
		kbdInp.value = inpBefore + letter + inpAfter;
		var pos = (inpBefore + letter).length;
		kbdInp.selectionStart = pos;
		kbdInp.selectionEnd = pos;
		kbdInp.focus();
		
	}
	
	function playerTimer(){
		// Executed by timer to update progress bar position
		
		if( timerStatus == 0 ) return(1);
		
		elapsed += 0.1;
		// Reached end of song :
		if( timerStatus == 1 && elapsed > duration ){
			timerStatus = 0;
			elapsed = 0;
			eleButPly.className = '';
			eleButRec.className = '';
			updateIn = 15;
		}
		
		// Recording :
		if( timerStatus == 2 ){
			eleProg.style.width = '100%';
			
		// Playing :
		}else if( duration > 0 ){
			eleProg.style.width = (100 * elapsed / duration) + '%';
		}else{
			eleProg.style.width = 0;
		}
		
		eleTimeCur.innerHTML = secToTime(elapsed);
		
	}
	setInterval( playerTimer, 100);
	
	
	function updateInterface(){
		// Executed by timer to request interface content regularily.
		// Timer is pushed whenever we receive the content from a request,
		// e.g. pressing play sends a request which get the content in the response so we wont request it again before a while.
		
		updateIn--;
		if( updateIn > 0 ) return;
		
		updateIn = 30;
		sendRequest('get-int');
		
	}
	setInterval( updateInterface, 99);
	
	
	var ww = 0; // Window width
	var wh = 0; // Window height
	var wwPrev = 0; // Previous ww read so we can compare
	var whPrev = 0; // ... wh
	
	function updwin(){
		// Update what depends on window size
		
		ww = window.innerWidth || (document.documentElement && document.documentElement.clientWidth) || document.body.clientWidth;
		wh = window.innerHeight || (document.documentElement && document.documentElement.clientHeight) || document.body.clientHeight;
		if( ww == wwPrev && wh == whPrev ) return;
		
		eleCtrl.style.fontSize = Math.round( (ww + 3.7*wh) / 55 )+'px';
		eleList.style.fontSize = Math.round( (ww + 2.5*wh) / 45 )+'px';
		eleOvr.style.fontSize = Math.round( (ww + 3*wh) / 50 )+'px';
		eleKbd.style.fontSize = Math.round( (ww + 6*wh) / 60 )+'px';
		
		wwPrev = ww;
		whPrev = wh;
		return;
	}
	
	setInterval( updwin, 50);
	
</script>

</body>
</html>

";
	
	return $response;
	
}

sub pageInterface {
	# Return AJAX response with entire interface status
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : optional $status
	# $_[4] : 1 if we are selecting a song (so that we set the bpm in right panel)
	# $_[5] : additional content for PLAYER (e.g. "\tsetIdClass:ovr:" to close overlay)
	
	my ($client, $client_info, $headers, $status, $selecting, $player_extra) = @_;
	
	$status = fdbget($conf->{statusFile}) unless $status;
	
	# (RE)LOAD WEB CONFIG :
	my $conf_db = fdbget($conf->{confFile});
	$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
	
	
	# ===== PLAYLIST CONTENT : =====
	my $body = "PLAYLIST";
	
	my $playlist = fdbget("$conf->{ramfsPath}/playlist");
	my $songsel; # hashref of info of currently selected song
	# ->{b} = bpm
	# ->{d} = duration
	# ->{r} = rating
	
	# EACH MIDI FILE (recent first) :
	foreach( sort{ $b cmp $a } keys %$playlist ){
		if( $_ =~ /^((\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\d{2})\.t$/ ){
			my $base = $1;
			my ($year, $mon, $day, $hou, $min) = ($2, $3, $4, $5, $6);
			
			my $tim = ( $hou > 12 ? $hou - 12 : int($hou) )
				.".$min "
				.( $hou > 11 ? "pm" : "am");
			
			my $title = $playlist->{$_};
			my $duration = $playlist->{"$base.d"};
			my $rating = $playlist->{"$base.r"} || 0;
			my $bpm_ori = $playlist->{"$base.bo"};
			my $bpm_new = $playlist->{"$base.bn"};
			
			my $fn = songToFilename($base, $title, $bpm_ori, $bpm_new, $rating);
			$status->{selected_file} = $fn if $status->{selected_file} eq ""; # select first song by default
			
			$body .= "\t$base|$year-$mon-$day|$tim|$duration|$bpm_ori|$bpm_new|$title|$rating|"
				.( $status->{selected_file} eq $fn ? "1" : "" )
				."|".( $conf->{alwaysShowMidiFile} || !$client_info->{islocal} ? "1" : "" );
			
			$songsel = {
				b => $bpm_new || $bpm_ori,
				d => $duration,
				r => $rating,
			} if $status->{selected_file} eq $fn;
			
		}
	}
	
	$body .= "\n";
	
	
	# ===== PLAYER BUTTONS + PROGRESS : =====
	$body .= "PLAYER$player_extra";
	
	if( $status->{player_status} eq "rec" ){
		
		$body .= "\telapsed:".( gettimeofday() - $status->{exec_started} ) if $status->{exec_started} > 0;
		$body .= "\tsetIdClass:but_rec:stop\tsetIdClass:but_ply:\tsetIdClass:prog:recording\tduration:0\tsetIdClass:rating:star0\tprog:0\ttimer:2";
		
	}else{
		
		$body .= "\tsetIdClass:prog:";
		
		$status->{play_duration} = $songsel->{d} if( $status->{play_duration} eq "" || $selecting );
		
		if( $status->{play_duration} > 0 ){
			my $cur_position;
			if( $status->{exec_started} > 0 ){
				$cur_position = $status->{play_position} + gettimeofday() - $status->{exec_started};
			}else{
				$cur_position = $status->{play_position};
			}
			$body .= "\telapsed:$cur_position\tprog:".( int( 10000 * ( $cur_position + 0.05 ) / $status->{play_duration} + 0.5 ) / 100 );
		}else{
			$body .= "\telapsed:0\tprog:0"
		}
		
		if( $status->{player_status} eq "play" ){
			$body .= "\tsetIdClass:but_rec:\tsetIdClass:but_ply:pause\ttimer:1";
		}else{
			$body .= "\tsetIdClass:but_rec:\tsetIdClass:but_ply:\ttimer:0";
		}
		
		$body .= "\tduration:$status->{play_duration}" if $status->{play_duration} > 0;
		$body .= "\tsetIdClass:rating:star$songsel->{r}" if $songsel->{r} ne "";
		
		$body .= "\tbpm:$songsel->{b}" if( $songsel->{b} > 0
			&& ( $selecting || $status->{player_status} eq "play" )
		);
		
	}
	
	
	if( $conf->{continue} ){
		$body .= "\tsetIdClass:but_con:ena";
	}else{
		$body .= "\tsetIdClass:but_con:";
	}
	
	if( $conf->{repeat} ){
		$body .= "\tsetIdClass:but_rep:ena";
	}else{
		$body .= "\tsetIdClass:but_rep:";
	}
	
	# Number of mounted USB drives :
	my $nbdisk = 0;
	my $folder = $status->{currentFolder} || "midirec-default";
	foreach( keys %$status ){
		$nbdisk++ if(
			$_ =~ /^usb_([a-z\d]+)_dir$/
			&& $status->{"usb_$1\_time"} > 0
			&& -e "$status->{$_}/$folder"
		);
	}
	$body .= "\tnbdisk:$nbdisk";
	
	
	$body .= "\n";
	
	
	return({
		body	=> $body,
	});
	
}

sub pageAjaxRecStart {
	# Start recording and return AJAX response
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : bpm
	
	my ($client, $client_info, $headers, $bpm) = @_;
	$bpm = 120 unless $bpm;
	
	my $status = fdbget($conf->{statusFile});
	
	# CANNOT READ IN RAMFS :
	unless( $status && $status->{ramfs_time} > 0 ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot start recording. Something is wrong with temp folder. Please try to restart the program.",
		});
	}
	
	# ALREADY RECORDING :
	if( $status->{player_status} eq "rec" ){
		return pageInterface($client, $client_info, $headers, $status);
	}
	
	# WE NEED TO STOP PLAYER FIRST :
	if( $status->{player_status} eq "play"
		&& $status->{exec_pid} > 0
	){
		
		$status = fdbset($conf->{statusFile}, {
			exec_killing	=> time,
		} );
		
		# TERMINATE aplaymidi :
		unless( killWell($status->{exec_pid})
			|| sleep(3) && killWell($status->{exec_pid})
		){
			return({
				code	=> "500 Internal Server Error",
				body	=> "Cannot stop the playing process. Please wait a few seconds and try again or restart the program.",
			});
		}
		
		$status = fdbset($conf->{statusFile}, {
			exec			=> "",
			exec_pid		=> "",
			exec_started	=> "",
			exec_time		=> "",
			player_status	=> "",
			play_position	=> "",
		} );
		
		return({
			code	=> "500 Internal Server Error",
			body	=> "The player was not stopped correctly. Please wait a few seconds and try again or restart the program.",
		}) unless $status;
		
	}
	
	# (RE)LOAD WEB CONFIG :
	my $conf_db = fdbget($conf->{confFile});
	$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
	
	# NO INTERFACE :
	if( $conf->{midiin} eq "" ){
		return({
			code	=> "406 Not Acceptable",
			body	=> "No MIDI input interface selected. Please check config menu.",
		});
	}
	
	# NO arecordmidi FOUND :
	if( $status->{bin_arecordmidi} eq "" ){
		return({
			code	=> "406 Not Acceptable",
			body	=> "Could not find arecordmidi anywhere. Please make sure you have it somewhere indicated by {dirSearch} in the config.",
		});
	}
	
	# EXEC process is already executing something :
	if( $status->{exec_time} > 0 || $status->{exec_pid} > 0 ){
		return({
			code	=> "406 Not Acceptable",
			body	=> "The exec process is already working on something. If this persists please restart the program.",
		});
	}
	
	# Ask EXEC process to start recording :
	my $now = time;
	my $rec_file = "$conf->{ramfsPath}/".timeToFileDate($now)."-untitled-$bpm-0.mid";
	
	unless( fdbset($conf->{statusFile}, {
		exec				=> "nice -n -15 $status->{bin_arecordmidi}"
			.( $conf->{ticksPerBeat} > 0 ? " -t $conf->{ticksPerBeat}" : "" )
			." -b $bpm -p $conf->{midiin} $rec_file",
		exec_time			=> $now,
		exec_player_status	=> "rec",
		rec_file			=> $rec_file,
	}) ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot start recording. Cannot write to status file.",
		});
	}
	
	# WAIT UNTIL RECORDING HAS STARTED :
	my $timeout = $now + 10;
	while( time < $timeout ){
		
		select(undef, undef, undef, 0.2);
		$status = fdbget($conf->{statusFile});
		
		# Recording started :
		if( $status->{player_status} eq "rec" && -f $rec_file ){
			return pageInterface($client, $client_info, $headers, $status);
			
		# Exec process wrote error message :
		}elsif( $status->{error} ne "" && $status->{error_time} >= $now ){
			return({
				code	=> "500 Internal Server Error",
				body	=> $status->{error},
			});
		}
	}
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Timeout! The exec process had trouble starting the recording.",
	});
	
}

sub pageAjaxRecStop {
	# Stop recording and return AJAX response
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : optional $status
	
	my ($client, $client_info, $headers, $status) = @_;
	
	$status = fdbget($conf->{statusFile}) unless $status;
	
	# CANNOT READ IN RAMFS :
	unless( $status && $status->{ramfs_time} > 0 ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot stop recording. Something is wrong with temp folder. Please try to restart the program.",
		});
	}
	
	# NOT RECORDING :
	unless( $status->{player_status} eq "rec"
		&& $status->{exec_pid} > 0
		&& $status->{rec_file} ne ""
	){
		return({
			code	=> "406 Not Acceptable",
			body	=> "The recording was already stopped. Please wait a few seconds and if you don't see that try to restart the program.",
		});
	}
	
	$status = fdbset($conf->{statusFile}, {
		exec_killing	=> time,
	} );
	
	# TERMINATE arecordmidi :
	unless( killWell($status->{exec_pid})
		|| sleep(3) && killWell($status->{exec_pid})
	){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot stop the recording process. Please wait a few seconds and try again or restart the program.",
		});
	}
	
	my $rec_filename = "";
	if( $status->{rec_file} =~ /([\w.+-]+)$/ ){
		$rec_filename = $1;
	}
	
	unless( fdbset($conf->{statusFile}, {
		exec			=> "",
		exec_pid		=> "",
		exec_started	=> "",
		exec_time		=> "",
		rec_file		=> "",
		selected_file	=> $rec_filename,
		player_status	=> "",
		play_position	=> 0,
	} ) ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "The recording was not stopped correctly. Please go find your file in $conf->{ramfsPath} then restart the program.",
		});
	}
	
	my $rec_filesize = (stat($status->{rec_file}))[7];
	unless( $rec_filesize > 0 ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Sorry, something went wrong in the recording. Please go search for your file in $conf->{ramfsPath}.",
		});
	}
	
	
	# ========== NOW COPY MID FILE EVERYWHERE : ==========
	
	my $copy_total = 0;
	my $copy_done = 0;
	
	# EACH USB DRIVE :
	foreach( keys %$status ){
		if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
			my $disk = $1;
			$copy_total++;
			
			system("cp -f \"$status->{rec_file}\" \"$status->{$_}/$conf->{currentFolder}/$rec_filename\"");
			select(undef, undef, undef, 0.05);
			
			my $newsize = (stat("$status->{$_}/$conf->{currentFolder}/$rec_filename"))[7];
			$copy_done++ if $newsize == $rec_filesize;
			
		}
	}
	
	system("sync");
	
	# EVERYTHING COPIED OK :
	if( $copy_total > 0 && $copy_done == $copy_total ){
		unlink($status->{rec_file});
		if( $rec_filename =~ /^(\d{8}-\d{6})-/ ){
			my $fn = $1;
			my $playlist = buildPlaylist($status, $fn);
			$status = fdbset($conf->{statusFile}, { play_duration => $playlist->{"$fn.d"} } );
		}else{
			$status = undef;
		}
		
		my $resp_rename = pageAjaxRenOpen($client, $client_info, $headers, 1);
		my $resp_int = pageInterface($client, $client_info, $headers, $status, 1);
		
		$resp_int->{body} .= $resp_rename->{body} unless exists $resp_rename->{code};
		return $resp_int;
	}
	
	# PARTIAL SUCCESS :
	if( $copy_done > 0 ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "WARNING: the file could only be copied on $copy_done of the $copy_total disks. Please investigate in the drives. We also kept the file in $conf->{ramfsPath} just in case.",
		});
	}
	
	# TRY TO COPY ANYWHERE :
	my $copy_dir = "";
	foreach my $dir ( "/root/", "/" ){
		
		system("cp -f \"$status->{rec_file}\" \"$dir$rec_filename\"");
		select(undef, undef, undef, 0.1);
		
		my $newsize = (stat("$dir$rec_filename"))[7];
		if( $newsize == $rec_filesize ){
			system("sync");
			$copy_dir = $dir;
			last;
		}
		
	}
	
	# COPIED TO HARD DRIVE INSTEAD :
	if( $copy_dir ne "" ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "WARNING: the file could not be copied to any USB drive. We copied it to $copy_dir and also kept the original in $conf->{ramfsPath} just in case. Please investigate and make sure the file is safe before restarting anything.",
		});
	}
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "WARNING: the file could not be copied to any USB drive. We also failed to copy it anywhere else. The original should still be in $conf->{ramfsPath}. Please investigate and make sure the file is safe before restarting anything. A reboot would probably DELETE it.",
	});
	
}

sub pageAjaxPlayStart {
	# Start playing and return AJAX response
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : optional $status
	# $_[4] : 1 = do not wait for player to start and return no web page
	
	my ($client, $client_info, $headers, $status, $nowait) = @_;
	
	$status = fdbget($conf->{statusFile}) unless $status;
	
	# CANNOT READ IN RAMFS :
	unless( $status && $status->{ramfs_time} > 0 ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot start playing. Something is wrong with temp folder. Please try to restart the program.",
		});
	}
	
	# ALREADY PLAYING :
	if( $status->{player_status} eq "play" ){
		
		# Close to end of file :
		if( $status->{play_duration} > 0
			&& $status->{exec_started} > 0
			&& $status->{play_position} + gettimeofday() - $status->{exec_started} > $status->{play_duration} - 4
			&& $status->{exec_pid} > 0
		){
			
			$status = fdbset($conf->{statusFile}, {
				exec_killing	=> time,
			} );
			
			# TERMINATE aplaymidi :
			unless( killWell($status->{exec_pid})
				|| sleep(3) && killWell($status->{exec_pid})
			){
				return({
					code	=> "500 Internal Server Error",
					body	=> "Cannot stop the playing process. Please wait a few seconds and try again or restart the program.",
				});
			}
			
			$status = fdbset($conf->{statusFile}, {
				exec			=> "",
				exec_pid		=> "",
				exec_started	=> "",
				exec_time		=> "",
				player_status	=> "",
				play_position	=> "",
			} );
			
			return({
				code	=> "500 Internal Server Error",
				body	=> "The player was not stopped correctly. Please wait a few seconds and try again or restart the program.",
			}) unless $status;
			
		}else{
			return pageInterface($client, $client_info, $headers, $status);
		}
		
	}
	
	
	# WHICH USB TO PLAY FROM :
	my $disk = "";
	foreach( keys %$status ){
		if( $_ =~ /^usb_[a-z\d]+_dir$/ && -e $status->{$_} ){
			$disk = $status->{$_};
			last;
		}
	}
	my $midi_dir = "$disk/".( $status->{currentFolder} || "midirec-default" );
	my $filename = $status->{selected_file};
	if( $filename eq "" ){
		$filename = getLatestMidiFile($midi_dir);
		$status->{play_position} = 0;
	}
	
	if( $filename eq "" ){
		return({
			code	=> "404 Not Found",
			body	=> "No file to play.",
		});
	}
	
	# WE NEED TO STOP RECORDING FIRST :
	if( $status->{player_status} eq "rec" ){
		my $recstop = pageAjaxRecStop($client, $client_info, $headers, $status);
		return $recstop if exists $recstop->{code};
	}
	
	# (RE)LOAD WEB CONFIG :
	my $conf_db = fdbget($conf->{confFile});
	$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
	
	# NO INTERFACE :
	if( $conf->{midiout} eq "" ){
		return({
			code	=> "406 Not Acceptable",
			body	=> "No MIDI output interface selected. Please check config menu.",
		});
	}
	
	# NO aplaymidi FOUND :
	if( $status->{bin_aplaymidi} eq "" ){
		return({
			code	=> "406 Not Acceptable",
			body	=> "Could not find aplaymidi anywhere (Florian custom version). Please make sure you have it somewhere indicated by {dirSearch} in the config.",
		});
	}
	
	# EXEC process is already executing something :
	if( $status->{exec_time} > 0 || $status->{exec_pid} > 0 ){
		return({
			code	=> "406 Not Acceptable",
			body	=> "The exec process is already working on something. If this persists please restart the program.",
		});
	}
	
	
	# Ask EXEC process to start playing :
	
	my $file_path = "$midi_dir/$filename";
	my $file_info = midiFileInfo($status, $file_path); # mostly for duration
	my $play_bpm = $file_info->{original_bpm};
	$play_bpm = $1 if $filename =~ /-([\d.]+)-\d\.mid$/;
	my $now = time;
	my $new_duration = int( $file_info->{total_duration} * $file_info->{original_bpm} / $play_bpm * 1000 + 0.5 ) / 1000;
	
	unless( fdbset($conf->{statusFile}, {
		exec				=> "nice -n -5 $status->{bin_aplaymidi} -d 1"
			.( $conf->{noteoff} eq "0" ? "" : " -c" )
			." -p $conf->{midiout}".( $status->{play_position} ? " -s $status->{play_position}" : "" )
			.( $play_bpm ? " -b $play_bpm" : "" )
			.( $status->{currentPosition} > 0 ? " -s $status->{currentPosition}" : "" )
			." $file_path",
		exec_time			=> $now,
		exec_player_status	=> "play",
		selected_file		=> $filename,
		play_duration		=> $new_duration,
	}) ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot start playing. Cannot write to status file.",
		});
	}
	
	return(1) if $nowait;
	
	# WAIT UNTIL PLAYER HAS STARTED :
	my $timeout = $now + 10;
	while( time < $timeout ){
		
		select(undef, undef, undef, 0.2);
		$status = fdbget($conf->{statusFile});
		
		# Player started :
		if( $status->{player_status} eq "play" ){
			return pageInterface($client, $client_info, $headers, $status);
			
		# Exec process wrote error message :
		}elsif( $status->{error} ne "" && $status->{error_time} >= $now ){
			return({
				code	=> "500 Internal Server Error",
				body	=> $status->{error},
			});
		}
	}
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Timeout! The exec process had trouble starting the player.",
	});
	
}

sub pageAjaxPlayPause {
	# Pause playing and return AJAX response
	# This kills aplaymidi and saves current position.
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : optional $status
	# $_[4] : force play_position
	
	my ($client, $client_info, $headers, $status, $force_pos) = @_;
	
	$status = fdbget($conf->{statusFile}) unless $status;
	
	# CANNOT READ IN RAMFS :
	unless( $status && $status->{ramfs_time} > 0 ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot stop recording. Something is wrong with temp folder. Please try to restart the program.",
		});
	}
	
	# NOT PLAYING :
	unless( $status->{player_status} eq "play"
		&& $status->{exec_pid} > 0
		&& $status->{exec_started} > 0
	){
		return pageInterface($client, $client_info, $headers, $status);
	}
	
	my $new_position = $force_pos;
	if( $new_position eq "" ){
		my $cur_position = $status->{play_position} + gettimeofday() - $status->{exec_started};
		$new_position = $cur_position - 0.1;
	}
	
	$status = fdbset($conf->{statusFile}, {
		exec_killing	=> time,
	} );
	
	# TERMINATE aplaymidi :
	unless( killWell($status->{exec_pid})
		|| sleep(3) && killWell($status->{exec_pid})
	){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot stop the playing process. Please wait a few seconds and try again or restart the program.",
		});
	}
	
	$status = fdbset($conf->{statusFile}, {
		exec			=> "",
		exec_pid		=> "",
		exec_started	=> "",
		exec_time		=> "",
		player_status	=> "",
		play_position	=> $new_position,
	} );
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "The player was not stopped correctly. Please wait a few seconds and try again or restart the program.",
	}) unless $status;
	
	return pageInterface($client, $client_info, $headers, $status);
	
}

sub pageAjaxStart {
	# Go to start and return AJAX response
	# If was playing, go to start and play. If not, just go to start.
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	
	my ($client, $client_info, $headers) = @_;
	
	return pageAjaxBar($client, $client_info, $headers, 0, 0);
	
}

sub pageAjaxBar {
	# Go to specific position and return AJAX response
	# If was playing, go and play. If not, just go..
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : click X location in px
	# $_[4] : X width of bar in px
	
	my ($client, $client_info, $headers) = @_;
	
	my $status = fdbget($conf->{statusFile});
	
	my $prog_ratio = $_[4] > 0 ? $_[3] / $_[4] : 0;
	
	# CANNOT READ IN RAMFS :
	unless( $status && $status->{ramfs_time} > 0 ){
		return({
			code	=> "500 Internal Server Error",
			body	=> "Cannot stop recording. Something is wrong with temp folder. Please try to restart the program.",
		});
	}
	
	# IS RECORDING :
	if( $status->{player_status} eq "rec" ){
		return pageInterface($client, $client_info, $headers, $status);
	}
	
	# IS PLAYING :
	if( $status->{player_status} eq "play"
		&& $status->{exec_pid} > 0
		&& $status->{exec_started} > 0
	){
		
		$status = fdbset($conf->{statusFile}, {
			exec_killing	=> time,
		} );
		
		# TERMINATE aplaymidi :
		unless( killWell($status->{exec_pid})
			|| sleep(3) && killWell($status->{exec_pid})
		){
			return({
				code	=> "500 Internal Server Error",
				body	=> "Cannot stop the playing process. Please wait a few seconds and try again or restart the program.",
			});
		}
		
		$status = fdbset($conf->{statusFile}, {
			exec			=> "",
			exec_pid		=> "",
			exec_started	=> "",
			exec_time		=> "",
			player_status	=> "",
			play_position	=> $status->{play_duration} * $prog_ratio,
		} );
		
		return({
			code	=> "500 Internal Server Error",
			body	=> "The player was not stopped correctly. Please wait a few seconds and try again or restart the program.",
		}) unless $status;
		
		return pageAjaxPlayStart($client, $client_info, $headers, $status);
		
	}
	
	$status = fdbset($conf->{statusFile}, {
		play_position	=> $status->{play_duration} * $prog_ratio,
	} );
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "The player was not stopped correctly. Please wait a few seconds and try again or restart the program.",
	}) unless $status;
	
	return pageInterface($client, $client_info, $headers, $status);
	
}

sub pageAjaxRate {
	# Rate a song (by renaming it)
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : new rating (0-5)
	
	my ($client, $client_info, $headers, $rating) = @_;
	$rating = 5 if $rating > 5;
	
	my $status = fdbget($conf->{statusFile});
	
	# Current file name :
	my $fn_ori = $status->{selected_file};
	return({
		code	=> "406 Not Acceptable",
		body	=> "Please select a song in the playlist first.",
	}) if $fn_ori eq "";
	
	# New file name :
	my $fn_new = $fn_ori;
	$fn_new =~ s/-\d\.mid$/-$rating.mid/;
	
	if( $fn_new ne $fn_ori ){
		
		my $folder = $status->{currentFolder} || "midirec-default";
		
		# RENAME FILE IN ALL DISKS :
		foreach( keys %$status ){
			if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
				my $file_ori = "$status->{$_}/$folder/$fn_ori";
				my $file_new = "$status->{$_}/$folder/$fn_new";
				
				return({
					code	=> "404 Not Found",
					body	=> "Cannot find original file. Please refresh the player or restart it and try again.",
				}) unless -e $file_ori;
				
				system("mv -f \"$file_ori\" \"$file_new\"");
				
				return({
					code	=> "500 Internal Server Error",
					body	=> "Cannot rename the file in the USB. Please refresh the player or restart it and try again.",
				}) unless( !-e $file_ori && -e $file_new );
				
			}
		}
		system("sync");
		
		my $base;
		$base = $1 if $fn_ori =~ /^(\d{8}-\d{6})-/;
		
		fdbset("$conf->{ramfsPath}/playlist", {
			"$base.r"	=> $rating,
		});
		
		$status = fdbset("$conf->{ramfsPath}/status", {
			"selected_file"	=> $fn_new,
		});
		
	}
	
	return pageInterface($client, $client_info, $headers, $status);
	
}

sub pageAjaxBpm {
	# Change a song BPM (by renaming it)
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : new bpm (0 means reset to original)
	
	my ($client, $client_info, $headers, $bpm) = @_;
	
	my $status = fdbget($conf->{statusFile});
	
	# Current file name :
	my $fn_ori = $status->{selected_file};
	return({
		code	=> "406 Not Acceptable",
		body	=> "Please select a song in the playlist first.",
	}) if $fn_ori eq "";
	
	my $base;
	$base = $1 if $fn_ori =~ /^(\d{8}-\d{6})-/;
	
	# Reset to original :
	if( $bpm == 0 ){
		my $playlist = fdbget("$conf->{ramfsPath}/playlist");
		$bpm = $playlist->{"$base.bo"};
	}
	
	return({
		code	=> "406 Not Acceptable",
		body	=> "Incorrect BPM value.",
	}) unless $bpm >= 10;
	
	# New file name :
	my $fn_new = $fn_ori;
	$fn_new =~ s/-\K\d+(?=-\d\.mid$)/$bpm/;
	
	if( $fn_new ne $fn_ori ){
		
		my $folder = $status->{currentFolder} || "midirec-default";
		my $file_new;
		
		# RENAME FILE IN ALL DISKS :
		foreach( keys %$status ){
			if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
				my $file_ori = "$status->{$_}/$folder/$fn_ori";
				$file_new = "$status->{$_}/$folder/$fn_new";
				
				return({
					code	=> "404 Not Found",
					body	=> "Cannot find original file. Please refresh the player or restart it and try again.",
				}) unless -e $file_ori;
				
				system("mv -f \"$file_ori\" \"$file_new\"");
				
				return({
					code	=> "500 Internal Server Error",
					body	=> "Cannot rename the file in the USB. Please refresh the player or restart it and try again.",
				}) unless( !-e $file_ori && -e $file_new );
				
			}
		}
		system("sync");
		
		my $file_info = midiFileInfo($status, $file_new);
		my $new_duration = $status->{play_duration};
		my $new_position = $status->{play_position};
		
		if( $file_info->{original_bpm} > 0 ){
			$new_duration = int( $file_info->{total_duration} * $file_info->{original_bpm} / $bpm * 1000 + 0.5 ) / 1000;
			$new_position = int( $new_duration * $status->{play_position} / $status->{play_duration} * 1000 + 0.5 ) / 1000 if $status->{play_duration} > 0;
			
			fdbset("$conf->{ramfsPath}/playlist", {
				"$base.bo"	=> $file_info->{original_bpm},
				"$base.bn"	=> $bpm,
				"$base.d"	=> $new_duration,
			});
			
		}
		
		$status = fdbset("$conf->{ramfsPath}/status", {
			"selected_file"	=> $fn_new,
			"play_duration"	=> $new_duration,
			"play_position"	=> $new_position,
		});
		
	}
	
	return pageInterface($client, $client_info, $headers, $status, 1);
	
}

sub pageMenu {
	# Return AJAX response with menu content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	
	my ($client, $client_info, $headers) = @_;
	
	# LOAD STATUS :
	my $status = fdbget($conf->{statusFile});
	
	# LOAD WEB CONFIG :
	my $conf_db = fdbget($conf->{confFile});
	$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
	
	
	
	# TODO HERE : if needed rebuild midi in/out and usb drives list
	# then reload status
	
	
	
	
	
	
	my $ovrhtml = "";
	
	
	# ===== MIDI INPUT/OUTPUT SELECTOR : =====
	
	foreach my $type ( "midiin", "midiout" ){
		$ovrhtml .= "<div id=menu_$type><label>MIDI ".( $type eq "midiin" ? "input" : "output")."</label><select onchange=\"sendRequest('setconf/$type/'+this.value)\">";
		foreach( sort{ $a cmp $b } keys %$status ){
			if( $_ =~ /^\Q$type\E_(\d+)_port$/ ){
				my $midi_name = $status->{"$type\_$1\_name"};
				my $midi_client = $status->{"$type\_$1\_client"};
				$midi_name = "$midi_client $midi_name" if $midi_name !~ /\Q$midi_client\E/i;
				$midi_name =~ s![^\w.:/+-]+! !g;
				$ovrhtml .= "<option value=\"$status->{$_}\"".( $status->{$_} eq $conf->{$type} ? " selected" : "").">$midi_name ($status->{$_})</option>";
			}
		}
		$ovrhtml .= "</select></div>";
	}
	
	
	# ===== SEND NOTES-OFF : =====
	$ovrhtml .= "<div id=menu_noteoff><input id=menu_noteoff_chk type=checkbox name=menu_noteoff_chk value=1".( $conf->{noteoff} eq "0" ? "" : " checked" )." onchange=\"sendRequest('setconf/noteoff/'+( this.checked ? 1 : 0) )\"><label for=menu_noteoff_chk>Send notes-off before playing</label></div>";
	
	
	# ===== USB DRIVES : =====
	my $last_disk_dir; # save it so we can read folders
	$ovrhtml .= "<div id=menu_usb><label>USB Drives</label>";
	foreach( sort{ $a cmp $b } keys %$status ){
		if( $_ =~ /^usb_([a-z\d]+)_dev$/ ){
			my $disk = $1;
			$ovrhtml .= "<div>";
			
			$ovrhtml .= "<nav>".$status->{"usb_$disk\_manufacturer"}." ".$status->{"usb_$disk\_product"}."</nav>";
			
			my $disk_dir = $status->{"usb_$disk\_dir"};
			
			if( $status->{"usb_$disk\_time"} > 0
				&& -e "$disk_dir/midirec-default"
			){
				$ovrhtml .= "<nav>".$status->{"usb_$disk\_fs"}." <span style=\"color:#30ff30\">mounted</span> to $disk_dir</nav>";
				$last_disk_dir = $disk_dir;
			}else{
				$ovrhtml .= "<nav style=\"color:#ff4848\">not mounted</nav>";
			}
			
			$ovrhtml .= "</div>";
		}
	}
	$ovrhtml .= "</div>";
	
	
	# ===== PLAYLIST FOLDERS : =====
	
	my $folders_html = "";
	if( opendir(USB, $last_disk_dir) ){
		foreach( readdir(USB) ){
			if( $_ =~ /^midirec-([a-z\d-]+)$/ ){
				my $playlist_name = ucfirst($1);
				$playlist_name =~ tr/-/ /;
				$playlist_name =~ s/ \K([a-z])(?=[a-z]{3})/ uc($1) /eig;
				
				my $playlist_songs = 0;
				if( opendir(PLY, "$last_disk_dir/$_") ){
					foreach( readdir(PLY) ){
						$playlist_songs++ if $_ =~ /^\d{8}-\d{6}-[\w-]*-\d+-\d\.mid$/;
					}
					closedir(PLY);
				}
				
				$folders_html .= "<option value=\"$_\"".(
					$_ eq $conf->{currentFolder}
					|| $_ eq "midirec-default" && $conf->{currentFolder} eq ""
					? " selected"
					: ""
				).">$playlist_name ($playlist_songs)</option>";
				
			}
		}
		closedir(USB);
	}
	
	$ovrhtml .= "<div id=menu_ply><label>Playlist Folder</label>";
	if( $folders_html ne "" ){
		$ovrhtml .= "<select onchange=\"if( this.value == '_' ){ sendRequest('newlist-open') }else{ sendRequest('setconf/currentFolder/'+this.value) }\">$folders_html<option value=\"_\">NEW PLAYLIST</option></select>";
	}else{
		$ovrhtml .= "<span style=\"color:#ff4848\">Cannot find any playlist. Please try to re-insert the USB sticks.</span>";
	}
	$ovrhtml .= "</div>";
	
	
	
	# -> USB drives : list & status
	
	# PLaylist folder : select + create new
	
	# Download tgz of entire folder
	
	
	
	
	
	
	# ===== SHUTDOWN : =====
	$ovrhtml .= "<a id=menu_shut onclick=\"sendRequest('shut-open',this)\">SHUTDOWN</a><div id=menu_shut_info>Or close Chrome kiosk with ALT+F4</div>";
	
	
	
	$ovrhtml =~ s/\n+//g;
	$ovrhtml =~ tr/\t/ /;
	
	return({
		body	=> "OVERLAY\t$ovrhtml\n",
	});
	
}

sub pageAjaxDelOpen {
	# Return AJAX response with delete overlay content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	
	my ($client, $client_info, $headers) = @_;
	
	
	my $status = fdbget($conf->{statusFile});
	
	return({
		code	=> "406 Not Acceptable",
		body	=> "Please select a song first.",
	}) unless( $status && $status->{selected_file} ne "" );
	
	my $filebase = "";
	$filebase = $1 if $status->{selected_file} =~ /^(\d{8}-\d{6})-/;
	
	my $playlist = fdbget("$conf->{ramfsPath}/playlist");
	return({
		code	=> "500 Internal Server Error",
		body	=> "Cannot find this song in playlist, please refresh the player, click the song again, and try again.",
	}) unless( $playlist
		&& $playlist->{"$filebase.t"} ne ""
		&& $playlist->{"$filebase.d"} > 0
	);
	
	return({
		body	=> "OVERLAY\t<div style=\"position:absolute;top:30%;left:0;right:0;color:#ff6060\">Permanently delete <span style=\"color:#ffffff\"><b>".$playlist->{"$filebase.t"}."</b> (".secToTime($playlist->{"$filebase.d"}).")</span> from all USBs?</div><a class=button style=\"top:72%;left:20%;width:20%;background-color:#d00000;color:#ffffff\" onclick=\"sendRequest('del-confirm/$status->{selected_file}',this)\">DELETE</a><a class=button style=\"top:72%;left:60%;width:20%\" onclick=\"eleOvr.className=''\">CANCEL</a>\n",
	});
	
}

sub pageAjaxDelConfirm {
	# Delete a song and return AJAX content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : file name "YYYYMMDD-HHMMSS-title-120-5.mid"
	
	my ($client, $client_info, $headers, $fn) = @_;
	
	
	# LOAD STATUS :
	my $status = fdbget($conf->{statusFile});
	
	return({
		code	=> "406 Not Acceptable",
		body	=> "Sorry, it seems this was not the song you selected in the playlist. Please try to select the right song again before pressing the delete icon.",
	}) unless( $status && $status->{selected_file} eq $fn );
	
	# LOAD WEB CONFIG :
	my $conf_db = fdbget($conf->{confFile});
	$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
	
	return({
		code	=> "406 Not Acceptable",
		body	=> "Sorry, no playlist folder seems selected. Please select the playlist and the song again before pressing the delete icon.",
	}) unless( $conf && $conf->{currentFolder} ne "" );
	
	my $count_drives = 0;
	my $count_found = 0;
	my $count_deleted = 0;
	
	# EACH USB DRIVE :
	foreach( keys %$status ){
		if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
			my $disk = $1;
			$count_drives++;
			
			my $file = "$status->{$_}/$conf->{currentFolder}/$fn";
			next unless -e $file;
			$count_found++;
			
			$count_deleted++ if(
				unlink($file)
					&& !-e $file
				|| sleep(1)
					&& system("rm -f $file")
					&& !-e $file
			);
			
		}
	}
	
	system("sync");
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Sorry, no drive could be found. Nothing was deleted. Please try to refresh the page and playlist, select the song again before pressing the delete icon.",
	}) unless $count_drives;
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Sorry, the file could not be found on any drive. Nothing was deleted. Please try to refresh the page and playlist, select the song again before pressing the delete icon.",
	}) unless $count_found;
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Sorry, the file could not be delete from any drive. Please make sure the script is executed as root and that the drives can be accessed.",
	}) unless $count_deleted;
	
	
	# REBUILD THE PLAYLIST :
	my $playlist = buildPlaylist($status);
	
	my $filebase_float = "";
	if( $status->{selected_file} =~ /^((\d{8})-(\d{6}))-/ ){
		$filebase_float = "$2.$3";
	}
	
	# Select next (more recent) song in playlist
	my $firstbase = "";
	my $prevbase = "";
	foreach( sort{ $b cmp $a } keys %$playlist ){
		if( $_ =~ /^((\d{8})-(\d{6}))\.t$/ ){
			my $base = $1;
			my $base_float = "$2.$3";
			
			$firstbase = $base unless $firstbase;
			last if $base_float < $filebase_float;
			$prevbase = $base;
		}
	}
	
	my $newbase = $prevbase || $firstbase;
	my $new_selected_file = "";
	$new_selected_file = songToFilename($newbase, $playlist->{"$newbase.t"}, $playlist->{"$newbase.bo"}, $playlist->{"$newbase.bn"}, $playlist->{"$newbase.r"})
		if $newbase ne "";
	
	$status = fdbset($conf->{statusFile}, {
		selected_file	=> $new_selected_file,
	} );
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Sorry, the file could only be delete from $count_deleted of $count_drives drives.",
	}) unless $count_deleted == $count_drives;
	
	
	return pageInterface($client, $client_info, $headers, $status, 1, "\tsetIdClass:ovr:");
	
}

sub pageAjaxRenOpen {
	# Return AJAX response with rename overlay content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : 1 = if no title yet try to get title from "previous title 1" so we suggest "previous title 2" (typically for after recording)
	
	my ($client, $client_info, $headers, $title_suggest) = @_;
	
	
	my $status = fdbget($conf->{statusFile});
	
	return({
		code	=> "406 Not Acceptable",
		body	=> "Please select a song first.",
	}) unless( $status && $status->{selected_file} ne "" );
	
	my $filebase = "";
	$filebase = $1 if $status->{selected_file} =~ /^(\d{8}-\d{6})-/;
	
	my $playlist = fdbget("$conf->{ramfsPath}/playlist");
	return({
		code	=> "500 Internal Server Error",
		body	=> "Cannot find this song in playlist, please refresh the player, click the song again, and try again.",
	}) unless( $playlist
		&& $playlist->{"$filebase.t"} ne ""
		&& $playlist->{"$filebase.d"} > 0
	);
	
	# No title yet :
	if( lc($playlist->{"$filebase.t"}) eq "untitled" || $playlist->{"$filebase.t"} eq "" ){
		$playlist->{"$filebase.t"} = "";
		if( $title_suggest ){
			foreach( sort{ $b cmp $a } keys %$playlist ){
				if( $_ =~ /^((\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\d{2})\.t$/ ){
					next if $1 eq $filebase;
					if( $playlist->{$_} =~ /^(.+ )(\d+)$/ ){
						$playlist->{"$filebase.t"} = $1.($2+1);
					}
					last;
				}
			}
		}
	}
	
	return({
		body	=> "OVERLAY\t<input id=ren_input type=text value=\"".uc($playlist->{"$filebase.t"})."\"><a class=button style=\"top:10%;left:75%;width:20%\" onclick=\"var title = gebi('ren_input').value.toLowerCase().replace(/[^a-z\\d]+/g,'-'); sendRequest('ren-confirm/$status->{selected_file}/'+title,this)\">RENAME</a>\nFOCUS\tren_input\nKEYBOARD\tren_input\n",
	});
	
}

sub pageAjaxRenConfirm {
	# Rename a song and return AJAX content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : file name "YYYYMMDD-HHMMSS-title-120-5.mid" of song to rename
	# $_[4] : new title "THE-TITLE"
	
	my ($client, $client_info, $headers, $fn, $title) = @_;
	
	
	# LOAD STATUS :
	my $status = fdbget($conf->{statusFile});
	
	return({
		code	=> "406 Not Acceptable",
		body	=> "Sorry, it seems this was not the song you selected in the playlist. Please try to select the right song again before pressing the rename icon.",
	}) unless( $status && $status->{selected_file} eq $fn );
	
	# LOAD WEB CONFIG :
	my $conf_db = fdbget($conf->{confFile});
	$conf->{$_} = $conf_db->{$_} foreach keys %$conf_db;
	
	return({
		code	=> "406 Not Acceptable",
		body	=> "Sorry, no playlist folder seems selected. Please select the playlist and the song again before pressing the rename icon.",
	}) unless( $conf && $conf->{currentFolder} ne "" );
	
	$title = lc($title);
	$title =~ s/[^a-z\d]+/-/g;
	$title =~ s/^-//;
	$title =~ s/-$//;
	$title = "untitled" if $title eq "";
	
	my $fn_new = $fn;
	$fn_new =~ s/^\d{8}-\d{6}-\K[\w-]*(?=-\d+-\d\.mid$)/$title/;
		
	if( $fn_new ne $fn ){
		
		my $count_drives = 0;
		my $count_found = 0;
		my $count_renamed = 0;
		
		# EACH USB DRIVE :
		foreach( keys %$status ){
			if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
				my $disk = $1;
				$count_drives++;
				
				my $file = "$status->{$_}/$conf->{currentFolder}/$fn";
				next unless -e $file;
				$count_found++;
				
				my $file_new = "$status->{$_}/$conf->{currentFolder}/$fn_new";
				
				$count_renamed++ if(
					system("mv -f \"$file\" \"$file_new\"")
						&& !-e $file
						&& -e $file_new
				);
				
			}
		}
		
		system("sync");
		
		return({
			code	=> "500 Internal Server Error",
			body	=> "Sorry, no drive could be found. Nothing was renamed. Please try to refresh the page and playlist, select the song again before pressing the rename icon.",
		}) unless $count_drives;
		
		return({
			code	=> "500 Internal Server Error",
			body	=> "Sorry, the file could not be found on any drive. Nothing was renamed. Please try to refresh the page and playlist, select the song again before pressing the rename icon.",
		}) unless $count_found;
		
		return({
			code	=> "500 Internal Server Error",
			body	=> "Sorry, the file could not be renamed on any drive. Please make sure the script is executed as root and that the drives can be accessed.",
		}) unless $count_renamed;
		
		
		# REBUILD THE PLAYLIST :
		buildPlaylist($status);
		
		$status = fdbset($conf->{statusFile}, {
			selected_file	=> $fn_new,
		} );
		
		return({
			code	=> "500 Internal Server Error",
			body	=> "Sorry, the file could only be renamed on $count_renamed of $count_drives drives.",
		}) unless $count_renamed == $count_drives;
		
	}
	
	return pageInterface($client, $client_info, $headers, $status, 1, "\tsetIdClass:ovr:\tsetIdClass:kbd:");
	
}

sub pageAjaxNewlistOpen {
	# Return AJAX response with overlay content to create a new playlist
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : 1 = if no title yet try to get title from "previous title 1" so we suggest "previous title 2" (typically for after recording)
	
	#my ($client, $client_info, $headers, $title_suggest) = @_;
	
	return({
		body	=> "OVERLAY\t<input id=plylst_input type=text value=\"\"><a class=button style=\"top:10%;left:75%;width:20%\" onclick=\"var name = gebi('plylst_input').value.toLowerCase().replace(/[^a-z\\d]+/g,'-'); sendRequest('newlist-make/'+name,this)\">CREATE</a>\nFOCUS\tplylst_input\nKEYBOARD\tplylst_input\n",
	});
	
}

sub pageAjaxNewlistMake {
	# Create a new playlist folder and return AJAX content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	# $_[3] : Playlist name
	
	my ($client, $client_info, $headers, $playlist) = @_;
	
	# LOAD STATUS :
	my $status = fdbget($conf->{statusFile});
	
	$playlist = lc($playlist);
	$playlist =~ s/[^a-z\d]+/-/g;
	$playlist =~ s/^-//;
	$playlist =~ s/-$//;
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Please enter a new playlist name.",
	}) if $playlist eq "";
	
	my $playlist_folder = "midirec-$playlist";
	my $mkdir_cnt = 0;
	
	foreach( sort{ $a cmp $b } keys %$status ){
		if( $_ =~ /^usb_([a-z\d]+)_dir$/ ){
			my $disk_dir = $status->{$_};
			
			return({
				code	=> "406 Not Acceptable",
				body	=> "Sorry, this playlist already exists.",
			}) if -e "$disk_dir/$playlist_folder";
			
			return({
				code	=> "500 Internal Server Error",
				body	=> "Sorry, the playlist could not be created in $disk_dir. Please make sure the script is executed as root and that the drives can be accessed.",
			}) unless( mkdir("$disk_dir/$playlist_folder")
				&& -e "$disk_dir/$playlist_folder"
			);
			
			$mkdir_cnt++;
			
		}
	}
	
	return({
		code	=> "500 Internal Server Error",
		body	=> "Sorry, no drive could be found. Please try to re-insert them.",
	}) unless $mkdir_cnt;
	
	my $status = fdbset($conf->{statusFile}, {
		selected_file	=> "",
		play_duration	=> "",
		play_position	=> "",
	} );
	
	$conf->{currentFolder} = $playlist_folder;
	fdbset($conf->{confFile}, {
		currentFolder	=> $playlist_folder,
	} );
	
	buildPlaylist($status);
	
	return pageInterface($client, $client_info, $headers, $status, 1, "\tsetIdClass:ovr:\tsetIdClass:kbd:");
	
}

sub pageAjaxShutOpen {
	# Return AJAX response with shutdown confirmation overlay content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	
	my ($client, $client_info, $headers) = @_;
	
	return({
		body	=> "OVERLAY\t<div style=\"position:absolute;top:30%;left:0;right:0;color:#ff6060\">Shutdown now?</div><a class=button style=\"top:72%;left:20%;width:20%;background-color:#d00000;color:#ffffff\" onclick=\"sendRequest('shut-confirm',this)\">SHUTDOWN</a><a class=button style=\"top:72%;left:60%;width:20%\" onclick=\"eleOvr.className=''\">CANCEL</a>\n",
	});
	
}

sub pageAjaxShutConfirm {
	# Return AJAX response with shutdown confirmation overlay content
	# $_[0] : client accepted socket
	# $_[1] : hashref of client info
	# $_[2] : hashref of request headers parsed
	
	fdbset($conf->{statusFile}, {
		shutdown	=> time,
	} );
	
	return({
		body	=> "OVERLAY\t<div style=\"position:absolute;top:30%;left:0;right:0;color:#ff6060\">Shutting down ...</div>\n",
	});
	
}

