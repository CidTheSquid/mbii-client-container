#!/bin/sh
# Run MBII keeping everything needed for post-mortem log browsing.
#
# Unlike run.sh this does NOT use --rm, so after the game exits you can:
#   1. podman logs mbii-glx                          # container stdout/stderr
#   2. cat logs/mbii-<timestamp>.log                 # identical host-side copy
#   3. In-game logs (persist in the gamedata volume):
#        gamedata/.local/share/openjk/MBII/qconsole.log
#        gamedata/.local/share/openjk/crashlog-*.txt
#
# To reproduce a crash on a specific map, pass the map on the command line:
#   ./run-logs.sh +devmap mb2_cloudcity
# or edit the MAP line below.
set -e

GAMEDATA=${GAMEDATA:-/home/cid/Downloads/mb2/gamedata}
# X auth cookie of the running X server (path changes each session).
XAUTH=${XAUTH:-$(ps -eo args 2>/dev/null | awk '/Xwayland|Xorg/ && !/grep/ {for (i=1;i<=NF;i++) if ($i=="-auth" && $(i+1)!="") {print $(i+1); exit}}')}
[ -n "$XAUTH" ] || { echo "error: could not locate the X server auth file (set XAUTH=...)" >&2; exit 1; }
XDG_RUNTIME=${XDG_RUNTIME:-/run/user/1000}
# NVIDIA 32-bit user-space libs, staged by ./fetch-driver.sh (NOT in the image).
DRIVER_DIR=${DRIVER_DIR:-"$(dirname "$0")/driver/usr/lib"}
MAP=${MAP:-""}

mkdir -p "$(dirname "$0")/logs"
LOGFILE="$(dirname "$0")/logs/mbii-$(date +%Y%m%d-%H%M%S).log"

podman rm -f mbii-glx >/dev/null 2>&1 || true

set +e
podman run --name mbii-glx \
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
  sh -c "exec ./mbii.i386 +set fs_game MBII +set s_initsound 0 +set r_mode -1 +set r_customwidth 1920 +set r_customheight 1080 $MAP" 2>&1 | tee "$LOGFILE"
RC=${PIPESTATUS[0]}
set -e

echo
echo "=== game exited (rc=$RC) ==="
echo "Console copy:      $LOGFILE"
echo "Container logs:    podman logs mbii-glx"
echo "Game console:      $GAMEDATA/.local/share/openjk/MBII/qconsole.log"
echo "Crash logs:        $GAMEDATA/.local/share/openjk/crashlog-*.txt"
echo "Container kept (no --rm) so 'podman logs mbii-glx' still works."
