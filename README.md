# OpenIPC-air_manager

**OpenIPC-air_manager** is a companion toolset for managing OpenIPC settings on the air unit (VTX) from the ground station (VRX). It supports safe channel switching, persistent video mode configuration, and extension via custom commands.

## Components

### `air_man` (Runs on VTX)
- Listens for incoming commands from the ground station.
- Built-in functions:
  - Change channel (with negotiation and fallback)
  - Change video mode (resolution, FPS, exposure, crop)
  - Start/stop services
- Forwards all other commands to customizable script `air_man_cmd.sh` and returns its output.

### `air_man_cmd.sh` (Runs on VTX)
- Defines custom commands (derived from original `gsmenu` script).
- Example:
  ```bash
  air_man_cmd.sh "get air camera contrast"
  ```
- Returns values like `50`. You can define `get`, `set`, or `values` commands inside the script.

### `air_man_gs` (Runs on Ground Station)
- Sends commands to `air_man` on the VTX and prints the response.
- Works for both built-in and custom commands.

#### Example commands that will be forwarded:

```bash
# Query contrast
./air_man_gs 10.5.0.10 "get air camera contrast"

# Set WFBNG power
./air_man_gs 10.5.0.10 "set air wfbng power 30"

# List available values
./air_man_gs 10.5.0.10 "values air camera size"
```

#### Special Commands, built in:
- **Channel Change with Negotiation**
  ```bash
  `./air_man_gs 10.5.0.10 "set air wfbng air_channel 165"`

  # or
  
  ./air_man_gs 10.5.0.10 "change_channel 165"
  ```
  - Negotiates channel change on both VTX and VRX.
  - Reverts if the link is lost.
  - Channel persistence on both.

- **Video Mode Configuration**
  ```bash
  # Without crop
  ./air_man_gs 10.5.0.10 "set_video_mode 1920x1080 60 10 'nocrop'"

  # With crop
  ./air_man_gs 10.5.0.10 "set_video_mode 1920x1440 60 10 '0 0 376 0 2248 1688'"
  ```
  - Sets resolution, FPS, exposure, and crop in one command.
  - Settings, including crop, persist across reboots.

## Video Modes Files
- `video_modes_imx335.ini`
- `video_modes_imx415.ini`

These files contain predefined video modes for respective camera sensors.

## `video_mode_chooser.sh`
A CLI tool to select and apply video modes from `.ini` files.

### Usage:
```bash
./video_mode_chooser.sh 10.5.0.10 video_modes_imx415.ini
```
- Displays a numbered list of modes.
- Applies the selected mode using `air_man_gs`, which also restarts majestic.
- Automatically runs several other command to recalibrate OSD and refresh alink:
  ```bash
  ./air_man_gs "$camera_ip" restart_msposd
  ./air_man_gs "$camera_ip" stop_alink
  ./air_man_gs "$camera_ip" start_alink
  ```
  

## Custom Commands
- Add `get`, `set`, or `values` functions in `air_man_cmd.sh`.
- Use `air_man_gs` to invoke these custom commands from the ground station.

---

