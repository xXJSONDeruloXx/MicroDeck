#!/bin/bash
# Runs tests/focus/run.sh in a Debian container (no X server needed on the host).
set -euo pipefail
cd "$(dirname "$0")/../.."
env MSYS_NO_PATHCONV=1 docker run --rm --platform linux/amd64 -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w debian:trixie bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq gcc libc6-dev libx11-dev libxres-dev xvfb openbox x11-utils x11-apps xdotool procps >/dev/null 2>&1
  bash tests/focus/run.sh'
