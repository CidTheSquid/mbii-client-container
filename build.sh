#!/bin/sh
# Build the MBII GPU container image.
set -e
cd "$(dirname "$0")"
podman build --platform linux/386 -t localhost/mbii-glx -t localhost/mbii-gpu .
podman tag localhost/mbii-glx:latest localhost/mbii-gpu:latest
