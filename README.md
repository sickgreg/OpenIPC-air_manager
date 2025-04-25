# OpenIPC-air_manager
Companion to communicate and control openipc settings, channel, video_mode, alink options


## air_man
air_man runs on drone and waits for commands from ground station

It has a few built in functions (with negotiation, fallback and persistence of settings) to change channel, change video mode, stop and start a few services, etc

If it receives a command that it does not already recognize then it will forward that command to `/usr/bin/air_man_cmd.sh` whose output it will send back to drone

## air_man_cmd.sh
air_man_cmd.sh defines any number of commands.  It is derived from the original gsmenu ssh command script that used to run remotely.

example command

`/usr/bin/air_man_cmd.sh "get air camera contrast"`

which is defined within and returns

`50`

## air_man_gs
Communicates with air_man (and by extention, air_man_cmd.sh) from the ground.  Send command, get response and exit

eg any command defined in air_man_cmd.sh
`./air_man_gs 10.5.0.10 "get air camera contrast"`
returns contrast value
`./air_man_gs 10.5.0.10 "set air wfbng power 30"`
sets power to 30
`./air_man_gs 10.5.0.10 "values air camera size"`
returns value
`./air_man_gs 10.5.0.10 "values air telemetry serial"`
returns value


air_man_gs also has built in functions to negotiate channel,  set predefined video modes (size, fps, exposure and crop if any all at once), etc.

`./air_man_gs 10.5.0.10 "set air wfbng air_channel 136"`

"set air wfbng air_channel" is a special case.  Because negotiation is required, channel changes are handled by air_man directly
It is equivelent to:

`./air_man_gs 10.5.0.10 "change_channel 165"`

`./air_man_gs 10.5.0.10 "set_video_mode 1920x1080 60 10 'nocrop'"`
`./air_man_gs 10.5.0.10 "set_video_mode 1920x1440 60 10 '0 0 376 0 2248 1688'"`


