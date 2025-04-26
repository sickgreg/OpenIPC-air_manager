TODO air_man

updated wifibroadcast script
  Change "wifibroadcast restart_msposd" to "wifibroadcast restart osd"

remove wfb.conf related stuff
  File /etc/wfb.conf does not exist.

need to use #!/bin/sh instead of bash in man_cmd.sh 

fix if not running alink already, you will be after setting resolution!
  see if it's running / enabled to run.  Better check if enabled really
  restart if enabled, otherwise don't
  
info command needs to do something
  tx power, wifi channel, ... and some more

need alink to be a service
  then mod the way we restart it -- Added a suggestion, check /etc/init.d/ and wfb.yaml - added air_man but not alink related commands //Joakim

need to use SO_REUSE port/IP
root@openipc-ssc338q:/usr/bin# air_man
bind failed: Address already in use

don't allow issuing multiple commands at once
