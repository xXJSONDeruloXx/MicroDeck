#!/bin/bash
# Downloads Valve's arm64 Steam client (every package verified against the CDN manifest's SHA256) into
# cache/steam-client-<channel>.tar, with no account data, for seeding release images.
#   tools/fetch-steam.sh [channel]      default steamdeck_publicbeta
#   STEAM_SEED=cache/steam-client-<channel>.tar tools/build-image.sh
set -euo pipefail
cd "$(dirname "$0")/.."
channel=${1:-steamdeck_publicbeta}
MSYS_NO_PATHCONV=1 docker run --rm --platform linux/arm64 -v "$(pwd -W 2>/dev/null || pwd)/cache:/out" microdeck-rg40xx-rootfs \
  bash -c "set -e; export HOME=/tmp/h; mkdir -p \$HOME
    bash /usr/local/bin/steam-install.sh $channel
    rm -rf \$HOME/.local/share/Steam/package/dl
    tar -C \$HOME --owner=1000 --group=1000 -cf /out/steam-client-$channel.tar .local/share/Steam .steam"
ls -la "cache/steam-client-$channel.tar"
