#!/bin/sh
# Fetch the 32-bit NVIDIA user-space GL libs needed by the MBII container,
# WITHOUT redistributing them. The libs are pulled from NVIDIA's own download
# servers (or a locally-downloaded .run) and staged into ./driver/usr/lib,
# which run.sh/run-logs.sh bind-mount into the container at /usr/lib/nvidia.
#
# The image itself never contains NVIDIA files, so it stays freely distributable.
#
# Usage:
#   ./fetch-driver.sh                # use host driver version (nvidia-smi)
#   ./fetch-driver.sh 610.57.04      # pin a specific version
#   DRIVER_RUN=/path/to/NVIDIA-Linux-x86-<ver>.run ./fetch-driver.sh
#
# Notes:
#   - The installer is fetched as-is from download.nvidia.com; nothing is
#     redistributed. Only the user-space libraries are extracted.
#   - If the exact driver version is not published (old/new/unreleased),
#     drop the matching NVIDIA-Linux-x86-<ver>.run file into this directory
#     or set DRIVER_RUN, and this script will use it.
set -e
cd "$(dirname "$0")"

DEST="$PWD/driver/usr/lib"
mkdir -p "$DEST"

# 1. Determine the driver version -------------------------------------------------
if [ -n "$1" ]; then
	VER="$1"
elif [ -n "$DRIVER_VERSION" ]; then
	VER="$DRIVER_VERSION"
elif command -v nvidia-smi >/dev/null 2>&1; then
	VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
else
	echo "error: cannot determine driver version (set DRIVER_VERSION or pass it as \$1)" >&2
	exit 1
fi
[ -n "$VER" ] || { echo "error: empty driver version" >&2; exit 1; }

# Idempotence: already staged for this version?
if [ -f "$DEST/libnvidia-glcore.so.$VER" ]; then
	echo "driver $VER already staged in $DEST"
	exit 0
fi

# 2. Locate the installer ----------------------------------------------------------
RUN=""
if [ -n "$DRIVER_RUN" ] && [ -f "$DRIVER_RUN" ]; then
	RUN="$DRIVER_RUN"
elif [ -f "NVIDIA-Linux-x86-$VER.run" ]; then
	RUN="$PWD/NVIDIA-Linux-x86-$VER.run"
else
	# Try NVIDIA's official mirrors. The .run is their own distribution
	# channel, so this does not constitute redistribution on our part.
	for base in \
		"https://download.nvidia.com" \
		"https://us.download.nvidia.com" \
		"https://international.download.nvidia.com"; do
		url="$base/XFree86/Linux-x86/$VER/NVIDIA-Linux-x86-$VER.run"
		echo "trying $url ..."
		if curl -fsSL --retry 2 -o "$PWD/NVIDIA-Linux-x86-$VER.run" "$url"; then
			RUN="$PWD/NVIDIA-Linux-x86-$VER.run"
			break
		fi
	done
fi

if [ -z "$RUN" ]; then
	echo "error: version $VER not found on download.nvidia.com." >&2
	echo "       Download NVIDIA-Linux-x86-$VER.run manually and re-run," >&2
	echo "       or set DRIVER_RUN=/path/to/NVIDIA-Linux-x86-$VER.run" >&2
	exit 1
fi
echo "using installer: $RUN"

# 3. Extract only the user-space libraries ---------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
sh "$RUN" --extract-only --target "$WORK" >/dev/null

# 4. Stage them into driver/usr/lib (with the .so.<major> symlinks glvnd needs) ---
echo "staging into $DEST ..."
for f in "$WORK"/lib*.so.*; do
	[ -f "$f" ] || continue
	cp -a "$f" "$DEST/$(basename "$f")"
done

for f in "$DEST"/lib*.so.[0-9]*; do
	# create the soname symlink, e.g. libGLX_nvidia.so.610.57.04 -> libGLX_nvidia.so.0
	base=${f%.*}
	base=${base%.*}
	if [ ! -e "$base" ]; then
		ln -s "$(basename "$f")" "$base"
	fi
done

echo "done. driver $VER staged. Rebuild not required; run.sh mounts this dir."
echo "installed $(ls "$DEST" | wc -l) files"
