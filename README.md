# OpenIPC-air_manager

**OpenIPC-air_manager** is a companion toolset for managing OpenIPC settings on the air unit (VTX) from the ground station (VRX). It supports safe channel switching, persistent video mode configuration, and extension via custom commands.



## 📁 Pre-release Installation (sbc v2.0.0b required for gs rec-fps updating - but not critical)

Consider `sysupgrade -k -r -n` first...

OTA (Over The Air). Power up VTX (drone) and VRX (gs).  Connect VRX (gs) to Internet. ssh to VRX (gs) and paste the following
```
#Run on VRX (gs) connected to Internet - With VTX (drone) powered on
git clone https://github.com/sickgreg/OpenIPC-air_manager
cd OpenIPC-air_manager
chmod +x install.sh
./install.sh 10.5.0.10 # or IP address over Ethernet
```

Double check your wlan_adapter and S and L in `/etc/wfb.yaml` (still testing auto-setting @ wfb startup)
```
# Note: currently defined adapters are [bl-r8812af1,bl-m8812eu2,bl-m8731bu4,default]
# Use default if flying MarioAIO/Ultrasite/PocketFPV.  Need a way to know which au we detect!
  wlan_adapter: bl-m8812eu2
  stbc: 1
  ldpc: 1
```

### 1. `get_all_video_modes`

**Description:** Lists all available named video modes for the detected sensor connected to VTX 

**Usage:**

```sh
air_man_gs 10.5.0.10 "get_all_video_modes"
```

**Response Example:**

```
16:9 720p 30
16:9 720p 30 crop
4:3 720p 60 50HzAC
```


Video modes are defined in sensor-specific `.ini` files:

* **IMX335**: `/etc/sensors/modes_imx335.ini`
* **IMX415**: `/etc/sensors/modes_imx415.ini`


```ini
[MODES]
; 16:9
"16:9 720p 30" = "1280x720 30 33 'nocrop'"
```

---
## `choose_mode.sh`
A VRX (ground station side) demonstrative CLI tool to read video_modes from .ini on drone, select and apply.
```
choose_mode.sh 10.5.0.10
  ```
### 2. `set_simple_video_mode '<name>'`

**Description:** Applies a named video mode from the `.ini` file.

**Usage:**

```sh
air_man_gs 10.5.0.10 "set_simple_video_mode '4:3 720p 60 50HzAC'"
```

* Mode name must exactly match an entry in the mode file.
* The underlying `set_video_mode` command is assembled and applied.
* The selected mode is saved to `/etc/sensors/mode_current`.

**Failure Example:**

```
Mode not found: 4:3 800p 60
```

---

### 3. `get_current_video_mode`

**Description:** Returns the last successfully set video mode name.

**Usage:**

```sh
air_man_gs 10.5.0.10 "get_current_video_mode"
```

**Response Example:**

```
4:3 720p 60 50HzAC
```

**Failure Cases:**

* If the file doesn't exist:

  ```
  Current mode file not found
  ```
* If the file is empty:

  ```
  No current video mode set
  ```

---

- **Channel Change with Negotiation**
  ```bash
  `./air_man_gs 10.5.0.10 "set air wfbng air_channel 165"`

  # or
  
  ./air_man_gs 10.5.0.10 "change_channel 165"
  ```
  - Negotiates channel change on both VTX and VRX.
  - Reverts if the link is lost.
  - Channel persistence on both.

- **Manual Video Mode Configuration (custom resolutions/settings)**
  ```bash
  # Without crop
  ./air_man_gs 10.5.0.10 "set_video_mode 1920x1080 60 10 'nocrop'"

  # With crop
  ./air_man_gs 10.5.0.10 "set_video_mode 1920x1440 60 10 '0 0 376 0 2248 1688'"
  ```
  - Sets resolution, FPS, exposure, and crop in one command.
  - Settings, including crop, persist across reboots.



#### Example commands that will be forwarded:

```bash
# Query contrast
./air_man_gs 10.5.0.10 "get air camera contrast"

# Set WFBNG power
./air_man_gs 10.5.0.10 "set air wfbng power 30"

# List available values
./air_man_gs 10.5.0.10 "values air camera size"
```  

## Custom Commands
- Add `get`, `set`, or `values` functions in `air_man_cmd.sh`.
- Use `air_man_gs` to invoke these custom commands from the ground station.

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


---

