#!/bin/bash
# Cross-builds Mesa (PanVK plus Panfrost GL) for arm64 into an isolated prefix, for testing Vulkan 1.3 on the Mali-G31 without touching
# the system Mesa (docs/research/panvk-vulkan-dxvk.md, stage 1). Runs in an amd64 Debian container: the build-time tools (mesa_clc and
# friends) are built natively first, then the arm64 build uses them. State is kept in the Docker volume `mdeck-mesa-build`.
#   tools/mesa/build.sh [version]       -> out/mesa/mesa-<version>-arm64.tar.xz (a /opt/mesa-mdeck prefix)
set -euo pipefail
cd "$(dirname "$0")/../.."
VER=${1:-26.3.1}
mkdir -p out/mesa
exec env MSYS_NO_PATHCONV=1 docker run --rm --platform linux/amd64 -e VER="$VER" -v mdeck-mesa-build:/build \
  -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w debian:trixie bash /w/tools/mesa/container-build.sh
