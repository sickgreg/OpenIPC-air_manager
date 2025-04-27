TODO air_man

updated wifibroadcast script
  Change "wifibroadcast restart_msposd" to "wifibroadcast restart osd"

remove wfb.conf related stuff
  File /etc/wfb.conf does not exist.

DONE need to use #!/bin/sh instead of bash in man_cmd.sh 

fix if not running alink already, you will be after setting resolution!
  see if it's running / enabled to run.  Better check if enabled really
  restart if enabled, otherwise don't
  
info command needs to do something
  tx power, wifi channel, ... and some more

DONE need alink to be a service, starts if yaml link_manager is "alink" 

air_man should start/stop alink with alink service now (i think?)

DONE need air_man to be a service
  

need to use SO_REUSE port/IP
root@openipc-ssc338q:/usr/bin# air_man
bind failed: Address already in use

don't allow issuing multiple commands at once



ALINK fixes (for joakims scripts)
set tx_factor option to 1 (maybe an option in config to keep compatibility?)
and replace all "cli —get" with "cli -g"
