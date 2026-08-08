#!/bin/sh
# Run Movie Battles II windowed on the host NVIDIA GPU via X11.
#
# Usage: ./run.sh [gamedata-path]
#   The gamedata path can be given as an argument, the GAMEDATA env var, or
#   left at the default below.
#
# Adjust as needed:
#   - resolution: r_mode -1 + r_customwidth/height (default 1920x1080)
#   - fullscreen: add +set r_fullscreen 1
#   - sound: change to "+set s_initsound 1" to enable audio
set -e

GAMEDATA=${1:-$GAMEDATA}
GAMEDATA=${GAMEDATA:-/PATH_TO_YOUR/gamedata}
[ -d "$GAMEDATA" ] || { echo "error: gamedata dir not found: $GAMEDATA" >&2; exit 1; }
# X auth cookie of the running X server (path changes each session).
XAUTH=${XAUTH:-$(ps -eo args 2>/dev/null | awk '/Xwayland|Xorg/ && !/grep/ {for (i=1;i<=NF;i++) if ($i=="-auth" && $(i+1)!="") {print $(i+1); exit}}')}
[ -n "$XAUTH" ] || { echo "error: could not locate the X server auth file (set XAUTH=...)" >&2; exit 1; }
XDG_RUNTIME=${XDG_RUNTIME:-/run/user/1000}
# NVIDIA 32-bit user-space libs, staged by ./fetch-driver.sh (NOT in the image).
DRIVER_DIR=${DRIVER_DIR:-"$(dirname "$0")/driver/usr/lib"}

podman run --rm --name mbii-glx \
  --env DISPLAY=:0 \
  --env XAUTHORITY="$XAUTH" \
  --env __GLX_VENDOR_LIBRARY_NAME=nvidia \
  --env LIBGL_ALWAYS_INDIRECT=0 \
  --env LD_LIBRARY_PATH=/usr/lib/nvidia \
  --env XDG_RUNTIME_DIR="$XDG_RUNTIME" \
  --env HOME=/gamedata \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  --volume "$XDG_RUNTIME":/run/user/1000 \
  --volume "$GAMEDATA":/gamedata \
  --volume "$DRIVER_DIR":/usr/lib/nvidia:ro \
  --workdir /gamedata \
  --device /dev/nvidia0 \
  --device /dev/nvidiactl \
  --device /dev/nvidia-modeset \
  --device /dev/nvidia-uvm \
  --device /dev/nvidia-uvm-tools \
  --device /dev/dri/renderD128 \
  --device /dev/dri/renderD129 \
  --security-opt label=disable \
  localhost/mbii-glx:latest \
  sh -c 'exec ./mbii.i386 +set fs_game MBII +set s_initsound 0 +set r_mode -1 +set r_customwidth 1920 +set r_customheight 1080'
