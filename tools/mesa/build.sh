#!/bin/bash
# Cross-builds Mesa (PanVK plus Panfrost GL) for arm64 into an isolated prefix, for testing Vulkan 1.3 on the Mali-G31 without touching
# the system Mesa (docs/research/panvk-vulkan-dxvk.md, stage 1). Runs in an amd64 Debian container: the build-time tools (mesa_clc and
# friends) are built natively first, then the arm64 build uses them.
#   tools/mesa/build.sh [version]       -> out/mesa/mesa-<version>-arm64.tar.xz (a /opt/mesa-sxx prefix)
set -euo pipefail
cd "$(dirname "$0")/../.."
VER=${1:-26.3.1}
mkdir -p out/mesa cache/mesa
exec env MSYS_NO_PATHCONV=1 docker run --rm --platform linux/amd64 -e VER="$VER" -v "$(pwd -W 2>/dev/null || pwd):/w" -w /w debian:trixie bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture arm64
apt-get update -qq
apt-get install -y -qq build-essential meson ninja-build pkgconf curl xz-utils python3-mako python3-yaml python3-ply python3-packaging \
  bison flex glslang-tools spirv-tools cmake zlib1g-dev libzstd-dev libexpat1-dev libdrm-dev \
  llvm-19-dev libclang-19-dev libclang-cpp19-dev libllvmspirvlib-19-dev libclc-19-dev clang-19 \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  zlib1g-dev:arm64 libzstd-dev:arm64 libexpat1-dev:arm64 libdrm-dev:arm64 libx11-dev:arm64 libxcb1-dev:arm64 \
  libxcb-dri3-dev:arm64 libxcb-present-dev:arm64 libxcb-sync-dev:arm64 libxshmfence-dev:arm64 libxcb-randr0-dev:arm64 \
  libxcb-xfixes0-dev:arm64 libxcb-shm0-dev:arm64 libx11-xcb-dev:arm64 libxcb-glx0-dev:arm64 libxext-dev:arm64 libxfixes-dev:arm64 \
  libwayland-dev:arm64 wayland-protocols libwayland-bin >/dev/null
SRC=/tmp/mesa-$VER
if [ ! -d $SRC ]; then
  [ -f cache/mesa/mesa-$VER.tar.xz ] || curl -fL -o cache/mesa/mesa-$VER.tar.xz https://archive.mesa3d.org/mesa-$VER.tar.xz
  mkdir -p $SRC && tar -xf cache/mesa/mesa-$VER.tar.xz -C $SRC --strip-components=1
fi
cd $SRC
echo "== native build of the build-time compilers (mesa_clc, precompiled kernels)"
meson setup build-native -Dprefix=/opt/native-tools -Dvulkan-drivers= -Dgallium-drivers= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
  -Dllvm=enabled -Dmesa-clc=enabled -Dinstall-mesa-clc=true -Dprecomp-compiler=enabled -Dinstall-precomp-compiler=true \
  -Dplatforms= -Dbuildtype=release >/dev/null
ninja -C build-native -j"$(nproc)" install >/dev/null
echo "== cross build for arm64"
cat > /tmp/cross.ini <<EOF
[binaries]
c = '"'"'aarch64-linux-gnu-gcc'"'"'
cpp = '"'"'aarch64-linux-gnu-g++'"'"'
ar = '"'"'aarch64-linux-gnu-ar'"'"'
strip = '"'"'aarch64-linux-gnu-strip'"'"'
pkg-config = '"'"'pkg-config'"'"'
[properties]
pkg_config_libdir = ['"'"'/usr/lib/aarch64-linux-gnu/pkgconfig'"'"', '"'"'/usr/share/pkgconfig'"'"']
[host_machine]
system = '"'"'linux'"'"'
cpu_family = '"'"'aarch64'"'"'
cpu = '"'"'cortex-a53'"'"'
endian = '"'"'little'"'"'
EOF
export PATH=/opt/native-tools/bin:$PATH
meson setup build-arm64 --cross-file /tmp/cross.ini -Dprefix=/opt/mesa-sxx -Dbuildtype=release -Db_ndebug=true \
  -Dvulkan-drivers=panfrost -Dgallium-drivers=panfrost -Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system \
  -Dplatforms=x11,wayland -Dglx=dri -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dvideo-codecs= \
  -Dvulkan-layers= -Dlibunwind=disabled -Dlmsensors=disabled >/dev/null
ninja -C build-arm64 -j"$(nproc)" >/dev/null
DESTDIR=/tmp/dest ninja -C build-arm64 install >/dev/null
tar -C /tmp/dest -cJf out/mesa/mesa-$VER-arm64.tar.xz opt/mesa-sxx
ls -la out/mesa/
'
