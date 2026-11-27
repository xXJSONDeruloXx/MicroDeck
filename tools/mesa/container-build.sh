#!/bin/bash
# Runs inside the amd64 Debian container started by tools/mesa/build.sh. Build state lives in /build (a Docker volume), so a retry
# after a failure resumes instead of starting over.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
VER=${VER:-26.3.1}
dpkg --add-architecture arm64
apt-get update -qq
apt-get install -y -qq build-essential meson ninja-build pkgconf curl xz-utils python3-mako python3-yaml python3-ply python3-packaging \
  bison flex glslang-tools spirv-tools cmake zlib1g-dev libzstd-dev libexpat1-dev libdrm-dev \
  llvm-19-dev libclang-19-dev libclang-cpp19-dev libllvmspirvlib-19-dev libclc-19-dev clang-19 \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  zlib1g-dev:arm64 libzstd-dev:arm64 libexpat1-dev:arm64 libdrm-dev:arm64 libx11-dev:arm64 libxcb1-dev:arm64 \
  libxcb-dri3-dev:arm64 libxcb-present-dev:arm64 libxcb-sync-dev:arm64 libxshmfence-dev:arm64 libxcb-randr0-dev:arm64 \
  libxcb-xfixes0-dev:arm64 libxcb-shm0-dev:arm64 libx11-xcb-dev:arm64 libxcb-glx0-dev:arm64 libxext-dev:arm64 libxfixes-dev:arm64 \
  libxxf86vm-dev:arm64 libxrandr-dev:arm64 libxdamage-dev:arm64 libxcb-keysyms1-dev:arm64 libxcb-dri2-0-dev:arm64 libxcb-xinerama0-dev:arm64 libxcb-randr0-dev:arm64 libwayland-dev:arm64 libwayland-egl-backend-dev:arm64 wayland-protocols libwayland-bin >/dev/null

SRC=/build/mesa-$VER
if [ ! -d $SRC ]; then
  [ -f /build/mesa-$VER.tar.xz ] || curl -fL -o /build/mesa-$VER.tar.xz https://archive.mesa3d.org/mesa-$VER.tar.xz
  mkdir -p $SRC && tar -xf /build/mesa-$VER.tar.xz -C $SRC --strip-components=1
fi
cd $SRC

echo "== native build of the build-time compilers (mesa_clc, precompiled kernels)"
if [ ! -x /build/native-tools/bin/panfrost_compile ]; then
  rm -rf build-native
  meson setup build-native -Dprefix=/opt/native-tools -Dvulkan-drivers=panfrost -Dgallium-drivers=panfrost -Dglx=disabled -Degl=disabled -Dgbm=disabled \
    -Dllvm=enabled -Dmesa-clc=enabled -Dinstall-mesa-clc=true -Dprecomp-compiler=enabled -Dinstall-precomp-compiler=true \
    -Dplatforms= -Dbuildtype=release
  ninja -C build-native -j"$(nproc)" install
  mkdir -p /build/native-tools && cp -a /opt/native-tools/. /build/native-tools/
else
  echo "(already installed)"
fi
[ -x /opt/native-tools/bin/panfrost_compile ] || { mkdir -p /opt/native-tools && cp -a /build/native-tools/. /opt/native-tools/; }

echo "== cross build for arm64"
cat > /tmp/cross.ini <<'EOF'
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'
[properties]
pkg_config_libdir = ['/usr/lib/aarch64-linux-gnu/pkgconfig', '/usr/share/pkgconfig']
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'cortex-a53'
endian = 'little'
EOF
export PATH=/opt/native-tools/bin:$PATH
rm -rf build-arm64
meson setup build-arm64 --cross-file /tmp/cross.ini -Dprefix=/opt/mesa-mdeck -Dbuildtype=release -Db_ndebug=true \
  -Dvulkan-drivers=panfrost -Dgallium-drivers=panfrost -Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system \
  -Dplatforms=x11 -Dglx=dri -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dvideo-codecs= \
  -Dvulkan-layers= -Dlibunwind=disabled -Dlmsensors=disabled
ninja -C build-arm64 -j"$(nproc)"
rm -rf /tmp/dest
DESTDIR=/tmp/dest ninja -C build-arm64 install >/dev/null
mkdir -p /w/out/mesa
tar -C /tmp/dest -cJf /w/out/mesa/mesa-$VER-arm64.tar.xz opt/mesa-mdeck
ls -la /w/out/mesa/
