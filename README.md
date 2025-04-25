# OpenIPC-air_manager
Companion to communicate and control openipc settings, channel, video_mode, alink options


## air_man
air_man runs on VTX (drone) and waits for commands from ground station

Has a few built in functions (with negotiation, fallback and persistence of settings) to change channel, change video mode, stop and start a few services, etc

If it receives a command that it does not already recognize, it will forward that command to `air_man_cmd.sh` whose output will be sent back to VRX (ground station)

## air_man_cmd.sh
air_man_cmd.sh defines any number of commands.  It is derived from the original gsmenu ssh command script that ran commands remotely.

example command

`air_man_cmd.sh "get air camera contrast"`

Inner workings are defined within and will return, for example

`50`

## air_man_gs
Communicates with air_man (and by extention, air_man_cmd.sh) from the ground.  Send command, get response and exit

For example, any command defined in air_man_cmd.sh

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

attempts to set channel on both vtx and vrx, waits for confirmation and reverts back if unable to make contact

`./air_man_gs 10.5.0.10 "set_video_mode 1920x1080 60 10 'nocrop'"`

`./air_man_gs 10.5.0.10 "set_video_mode 1920x1440 60 10 '0 0 376 0 2248 1688'"`

set video mode with or without crop and make all parameters persistent (including crop upon reboot)

`"set_video_mode <size> <fps> <exposure> <'crop'>"`


## video_modes_imx335.ini, video_modes_imx415.ini

extensive list of video modes and their parameters

## video_mode_chooser.sh

command line tool that loads a video_modes file and displays the modes in a numbered list and calls air_man_gs upon selection

`./video_mode_chooser.sh 10.5.0.10 video_modes_imx415.ini`

After setting the mode, the script also runs a couple of air_man's other commands...

```
./air_man_gs "$camera_ip" restart_msposd
./air_man_gs "$camera_ip" stop_alink
./air_man_gs "$camera_ip" start_alink
```
the result is recalibrated msposd OSD size and refreshed alink with new size and fps
