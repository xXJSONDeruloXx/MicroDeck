#!/bin/bash
# Builds the arm64 Debian userspace and exports it to out/rootfs.tar.
# Two stages: the slow base (rootfs/Dockerfile: packages, Mesa, kernel modules) and a fast image layer
# (rootfs/Dockerfile.image: overlay, helpers, secrets). The base is tagged by a hash of its inputs. CI publishes
# every base it builds to ghcr.io, so a checkout whose inputs match one pulls it instead of running ~650
# package installs under emulation. Without a match the base is built here (cached by Docker after that).
#   tools/build-rootfs.sh            reuse a local or published base when its hash matches
#   BASE_PULL=0 tools/build-rootfs.sh   always build the base locally
#   PUSH_BASE=1 tools/build-rootfs.sh   after building the base, push it (CI on main; needs a ghcr login)
#   DEV_MODE=1 tools/build-rootfs.sh    development image: poweroff = reboot (to muOS), power key ignored (releases: off)
set -euo pipefail
cd "$(dirname "$0")/.."
REGISTRY=${BASE_REGISTRY:-ghcr.io/xxjsonderuloxx/microdeck-rg40xx-base}
REGISTRY=${REGISTRY,,}
[ -d cache/overlay ] || tools/fetch-rocknix.sh
# A CRLF script or config in the image breaks at boot (`/bin/sh^M`); Windows editors and Python's text mode write them.
crlf=$(find overlay rootfs debug -type f -exec grep -lU "$(printf '\r')" {} + 2>/dev/null || true)
[ -z "$crlf" ] || { echo "CRLF line endings in: $crlf"; exit 1; }
mkdir -p out

# Everything the base layers read: the Dockerfile, LSE-Emu's source and the ROCKNIX download that supplies modules.
hash=$(cat rootfs/Dockerfile rootfs/src/lse_emu.c tools/fetch-rocknix.sh | tr -d '\r' | sha256sum | cut -c1-12)
local_base=microdeck-rg40xx-base:$hash
if docker image inspect "$local_base" >/dev/null 2>&1; then
  echo "== base $hash: local image"
elif [ "${BASE_PULL:-1}" = 1 ] && docker pull --platform linux/arm64 "$REGISTRY:$hash" >/dev/null 2>&1; then
  docker tag "$REGISTRY:$hash" "$local_base"
  echo "== base $hash: pulled from $REGISTRY"
else
  echo "== base $hash: building (slow under emulation; cached by Docker afterwards)"
  docker build --platform linux/arm64 -t "$local_base" -f rootfs/Dockerfile .
  if [ "${PUSH_BASE:-0}" = 1 ]; then
    docker tag "$local_base" "$REGISTRY:$hash"
    docker push "$REGISTRY:$hash"
  fi
fi

docker build --platform linux/arm64 --build-arg BASE="$local_base" --build-arg DEV_MODE="${DEV_MODE:-0}" -t microdeck-rg40xx-rootfs -f rootfs/Dockerfile.image .
id=$(docker create --platform linux/arm64 microdeck-rg40xx-rootfs)
trap 'docker rm -f "$id" >/dev/null' EXIT
docker export "$id" -o out/rootfs.tar
ls -la out/rootfs.tar
