# Debian trixie arm64 userspace for the RG40XX-H, booted by ROCKNIX's mainline kernel.
# This is the slow, rarely changing base (packages, Mesa, kernel modules); rootfs/Dockerfile.image adds the
# repository's overlay, helpers and secrets on top. tools/build-rootfs.sh pulls CI's prebuilt base when its inputs match.
# Build context is the repository root: docker build --platform linux/arm64 -f rootfs/Dockerfile .
FROM debian:trixie
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv systemd-timesyncd udev dbus dbus-user-session dbus-x11 iproute2 kbd libpam-systemd kmod sudo \
    openssh-server openssh-client earlyoom adbd network-manager wpasupplicant iw wireless-regdb rfkill \
    systemd-zram-generator cloud-guest-utils e2fsprogs dosfstools fdisk \
    ca-certificates curl unzip xz-utils file procps psmisc strace gdb binutils less nano lsof pciutils \
    usbutils evtest htop python3 gcc libc6-dev libx11-dev \
    xserver-xorg-core xserver-xorg-input-libinput xinit xauth x11-xserver-utils x11-utils x11-apps \
    xdotool openbox unclutter-xfixes ffmpeg \
    libgl1-mesa-dri libglx-mesa0 libegl1 libgles2 libgbm1 mesa-vulkan-drivers libvulkan1 vulkan-tools mesa-utils \
    pipewire pipewire-pulse pipewire-alsa wireplumber rtkit alsa-utils upower \
    libnss3 libnspr4 libdrm2 libgl1 libgtk-3-0t64 libgtk2.0-0t64 libxss1 libxtst6 libxrandr2 libxcomposite1 \
    libxdamage1 libxkbcommon0 libxkbcommon-x11-0 libasound2t64 libpulse0 libcups2t64 \
    libatk-bridge2.0-0t64 libatspi2.0-0t64 libudev1 libusb-1.0-0 libsdl2-2.0-0 libfontconfig1 \
    libfreetype6 fonts-dejavu-core fonts-liberation libxcursor1 libxi6 libxinerama1 libxshmfence1 \
    libxxf86vm1 libcurl4t64 libdbus-1-3 libopenal1 libva2 libibus-1.0-5 libpipewire-0.3-0t64 \
    libxcb-res0 libxcb-xinput0 libxcb-xfixes0 libxcb-shape0 libxcb-randr0 libxcb-dri3-0 \
    libnm0 libsecret-1-0 libgdk-pixbuf-2.0-0 libpango-1.0-0 libcairo2 libpng16-16t64 libjpeg62-turbo \
    zenity locales \
 && sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends avahi-daemon libnss-mdns \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Keep earlier layers byte-identical: the arm64 build runs under emulation here, and a change to the big apt
# layer re-runs every layer after it (15+ minutes). New packages go in late layers like this one.
RUN apt-get update && apt-get install -y --no-install-recommends zstd  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Mesa 26.1 from trixie-backports: its PanVK (Vulkan) enumerates the Mali-G31; trixie's 25.0 does not.
RUN printf 'Types: deb\nURIs: http://deb.debian.org/debian\nSuites: trixie-backports\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n' \
      > /etc/apt/sources.list.d/trixie-backports.sources \
 && apt-get update && apt-get install -y --no-install-recommends -t trixie-backports \
      mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgbm1 mesa-libgallium \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cortex-A53 is ARMv8.0: no LSE atomics, which the arm64 Steam client uses inline.
COPY rootfs/src/lse_emu.c /usr/local/src/lse_emu.c
RUN mkdir -p /usr/local/lib/lse && gcc -shared -fPIC -O2 -march=armv8-a -mno-outline-atomics \
      -Wl,-z,now -o /usr/local/lib/lse/liblse_emu.so /usr/local/src/lse_emu.c -ldl \
 && strip --strip-unneeded /usr/local/lib/lse/liblse_emu.so \
 && ! objdump -d /usr/local/lib/lse/liblse_emu.so | grep -qE $'\t((ld|st)(add|clr|eor|set|smax|smin|umax|umin)|swp|cas)[a-z]*\t' \
 && cp /usr/local/lib/lse/liblse_emu.so /usr/local/lib/lse/liblse_emu_sys.so
# ROCKNIX kernel 7.2.0 modules (joypad, zram, ...) and Wi-Fi/BT firmware.
COPY cache/overlay/usr/lib/kernel-overlays/base/lib/modules/ /usr/lib/modules/
COPY cache/overlay/usr/lib/kernel-overlays/base/lib/firmware/ /usr/lib/firmware/
COPY cache/overlay/usr/lib/udev/hwdb.d/20-joypad.hwdb /usr/lib/udev/hwdb.d/20-joypad.hwdb

RUN useradd -m -s /bin/bash -G sudo,video,input,audio,render,netdev steam \
 && echo 'steam ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/steam && chmod 440 /etc/sudoers.d/steam \
 && passwd -d root && passwd -d steam \
 && rm -f /etc/ssh/ssh_host_* \
 && systemctl disable adbd.service ssh.service 2>/dev/null; true

# InputPlumber (built by CI, see the image layer) links these; acl lets it hide the raw pad from other readers.
RUN apt-get update && apt-get install -y --no-install-recommends libevdev2 libiio0 acl \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Bluetooth (the RTL8821CS controller shows up as hci0): bluez, and PipeWire's Bluetooth audio for headphones.
RUN apt-get update && apt-get install -y --no-install-recommends bluez libspa-0.2-bluetooth libxres-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*


# Desktop mode (Steam's "Switch to Desktop"): openbox is already in the image; a panel, a browser, documents, a text editor, files, a terminal.
# libxft-dev builds the on-screen keyboard (mdeck-osk). About 430 MB installed, 275 MB of it Firefox.
RUN apt-get update && apt-get install -y --no-install-recommends firefox-esr abiword gnumeric mousepad pcmanfm xterm tint2 \
      fonts-dejavu-core libxft-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
