# OpenIPC-air_manager
Companion to communicate and control openipc settings, channel, video_mode, alink options


## air_man
air_man runs on drone and waits for commands from ground station

It has a few built in functions (with negotiation, fallback and persistence of settings) to change channel, change video mode, stop and start a few services, etc

If it receives a command that it does not already recognize then it will forward that command to `/usr/bin/air_man_cmd.sh' whose output it will send back to drone

## air_man_cmd.sh
air_man_cmd.sh defines any number of commands.  It is derived from the original gsmenu ssh command script.

example command

`/usr/bin/air_man_cmd.sh "get air camera contrast"`

which is defined within and returns

`50`
