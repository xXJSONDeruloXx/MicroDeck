# MicroDeck roadmap

Goal: an SD-card OS for the RG40XX-H (and later other H700 handhelds) that feels like SteamOS: boots into
Steam's gamepad UI, games launch from it, and display, audio, controls, power and sleep behave like a Deck.
Mirror upstream SteamOS wherever the hardware allows.

Status keys: [x] done, [~] partial, [ ] open. Effort/risk: S/M/L.

## Done (2026-11-24)
- [x] Boots mainline (ROCKNIX 7.2 kernel) with U-Boot using this unit's LPDDR4 timings.
- [x] Remote dev loop with no physical steps: muOS in slot 1 as recovery, our OS in slot 2 through FEL;
      watchdog, panic/oops reboot, reach-guard, dev-mode power handling, `tools/rescue.sh`.
- [x] Steam arm64 client in a logind session: rootless Xorg, PipeWire, `-gamepadui -steamos3 -steampal -steamdeck`.
- [x] Display (KMS, Panfrost GL), audio (speaker), Wi-Fi, battery (upower), built-in pad, on-screen keyboard,
      volume/brightness keys, cursor hidden until motion.
- [x] Automation: `mdeck` (Steam DevTools + virtual test pad), `tools/smoke.sh`, screenshots, launch tracing.
- [x] First game: Geometry Wars through Proton Experimental (ARM64) + FEX + LSE-Emu (DXVK on llvmpipe).

## 0. Initial release (v0.1.0) checklist
- [x] Image boots from a single card in slot 1 (verified 2026-11-25).
- [x] First start installs the Steam client and the ARMv8.0 Proton itself, with a progress window; Proton is the
      default for new games (`mdeck-compat-default`).
- [x] Steam no longer re-extracts its client on every start (`steamwebhelper.sh` patched after the updater's check).
- [x] Real poweroff works with dev mode off (2026-11-25); dev mode is a build option (`DEV_MODE=1`), off in CI.
- [x] Wi-Fi without secrets in the image: `wifi.txt` on the boot partition (`mdeck-wifi-import`).
- [x] CI builds U-Boot, rootfs and image; the rootfs base is published to ghcr.io; tagged builds draft a release.
- [x] CI release image inspected (2026-11-25): 2.7 GiB, dev mode off, no NetworkManager profiles, no SSH keys, no Steam
      seed, `wifi.txt.example` on the boot partition, Wi-Fi import service enabled. adb over USB is a root shell
      (no auth) and SSH accepts only keys: say so in the notes.
- [x] The CI-built release image ran from power-on to a game without a PC (2026-11-25): Wi-Fi from `wifi.txt`, first
      start, QR sign-in, install and launch a game.
- [x] First-start time measured on the release image (2026-11-25): power-on to the sign-in screen 58 min (Wi-Fi joined
      in 10 s; client download and install ~15 min; Proton download ~20 min at 0.3-0.4 MB/s from GitHub; Steam's own
      update and extraction the rest). Mirror or cache Proton if this matters.
- [x] Steam settings JS matches the current client again (the screensaver wallpapers had covered the launch dialog).
- [x] Release image verified end to end (2026-11-25): QR sign-in, install Geometry Wars, launch under the default
      ARMv8 Proton, Steam menu over the game and back, quit to Big Picture.
- [x] The pad is a native Steam Deck controller (28de:1205 over USB/IP, InputPlumber; own kernel 7.2.0-mdeck), verified
      2026-11-26: Deck glyphs, no "External Controller Translation" dialog, game test passes on the CI image.
- [x] `mdeck-gametest` cancels an account-in-use dialog (and says so) and dismisses the controller hint. Rumble verified:
      a Deck rumble report makes InputPlumber upload `FF_RUMBLE` to the pad (2026-11-26).
- [x] Power menu: Restart verified on hardware (2026-11-26: `SteamClient.System.RestartPC()` reboots). Shut down uses
      the same sentinel path, and real poweroff was verified earlier. Sleep is refused (`AllowSuspend=no`) until TF-A
      suspend exists.
- [x] Sleep is refused (`AllowSuspend=no`), so the power menu's Sleep does nothing harmful.
- [x] Release notes and releases: v0.1.0, v0.2.0, v0.2.1 published (docs/release-notes/).

- [x] Compressed-memory experiments (2026-11-26): lz4 and zstd vs lzo-rle, idle recompression (shipped), DAMON_RECLAIM
      (no gain, left off), zram writeback (not worth it on an SD card). Left: tuning the recompress interval. CRAM needs
      hardware this board does not have.

## Ideas from nibOS (reviewed 2026-11-26)
[nibOS](https://github.com/abradburne/nibos) targets the Anbernic RG DS+ (RK3568), runs Arch Linux ARM with native
emulators and has no Steam, Proton or FEX. Not a base for us (different distro and SoC, young project), but its design
notes (docs/design/*.md, docs/boot-time.md) have ideas, ranked by value over effort:
- [x] State and data kept apart from the root (2026-11-26): `microdeck-data` on a third partition after a fixed 3 GiB root,
      mounted at /home; first boot creates it or finds and reuses it, and Wi-Fi/SSH settings are mirrored there, so a
      reflash keeps games, Steam login, Proton and settings. Verified: flash, restore once, flash again, everything
      survived. (Found and fixed on the way: the image must end exactly at the end of the root.)
- [ ] Pre-seed or background-fetch Steam and Proton: ship them on the data partition or fetch them in a `Nice=19`,
      idle-I/O unit with chunked, hash-verified, resumable downloads (their updater pattern), removing the 1.1 GB
      first-start wait. Note (2026-11-26): the slow part is the handheld's Wi-Fi (~1 MB/s), not the source: Valve's client cannot be shipped,
      and shipping Proton would save only about 7 of 58 minutes, so fix the Wi-Fi speed first (see the Wi-Fi speed item). M
- [ ] Mesa trimming: nibOS builds Panfrost-only with no LLVM (libgallium 21 MB instead of 54 MB plus 171 MB libLLVM)
      and carries two Panfrost patches (write-combined index scan, keep BOs mapped). The G31 uses Panfrost too, but we
      rely on llvmpipe for the DXVK CPU path, so test a Panfrost-only build against the cost of losing that. M
- [x] Boot is already short (2026-11-26, `systemd-analyze`: 3.8 s kernel + 7.9 s userspace, Steam session at 7.4 s); the time to Steam's UI is Steam itself, so there is nothing
      worth trimming. Original idea, kept for reference: boot trimming from docs/boot-time.md that transfers to Debian: a systemd generator that reads the launcher's
      files ahead of time (at idle priority), masking unused generators. S
- [x] In-place updater (2026-11-26, v0.4.0): `mdeck-update` (check/apply, wired to Steam's Check For Updates through
      `steamos-update`) stages the release's root and boot files on the data partition; the initramfs writes them at the next
      boot (root first, boot files last through rename, `pending` marker makes an interrupted install repeat). Verified from
      Steam's UI on hardware, twice. Rollback added (2026-11-26): the last installed image is kept, a release is on trial until Steam's UI has been up 30 s, three failed boots reinstall the previous one (tested with a deliberately broken release). Still open: A/B root and signed, chunked updates (minisign
      manifest, 16 MiB zstd chunks, `min_from` and state `migrate` numbers): the
      install writes only the used chunks of the new root (about half of the 3 GiB; reading to skip unchanged blocks is no faster on this card). L
- [ ] Read-only root with a writable overlay on the state partition, which makes slot images reproducible. M
- [ ] SPL Falcon boot (skip U-Boot proper) for boot time: needs an Allwinner port, boot time is not our main pain. L
Not copied: Arch as the base, lz4-only zram (our lzo-rle plus idle zstd keeps the capacity), 3 GiB root slots (too big
once Steam and Proton are on the card), the RK3568 SPL and watchdog specifics.

## 1. Reproducibility (do first; many fixes were applied live)
- [x] Diff the running device against `overlay/` + `rootfs/` (2026-11-27, RG40XX-H on v0.7.0): all 93 overlay files match by SHA-256; the only
      extra files under `/usr/local` and the config directories are package files, the Wi-Fi profile and binaries built from `rootfs/src`. S
- [x] Rebuild rootfs and image from scratch, flash slot 2 from muOS, FEL-boot, restore the Steam backup,
      `tools/smoke.sh` and `mdeck-gametest` pass (2026-11-24). `tools/reflash-slot2.sh`, `backup-steam.sh`,
      `restore-steam.sh`. `tools/cycle.sh` chains build + flash + restore + test (written 2026-11-25, not yet run end to end).
- [~] Pin the Steam bootstrap: `tools/fetch-steam.sh` installs the arm64 client from the CDN manifest
      (each package SHA256-checked) into a clean seed tar; `STEAM_SEED=` puts it in the image. Still to do:
      pin a manifest version, and check that the first start does not re-download. M
- [x] CI: GitHub Actions builds U-Boot, kernel, InputPlumber, rootfs and image, runs the unit tests and boots the image in QEMU. M

- [ ] **Wi-Fi speed** (high value): downloads on the handheld average ~1 MB/s (first start ~58 min, a 340 MB update ~6 min, Proton 435 MB
      ~7 min), though the same network gives a PC many times that. Check on the device: which band it joined (`iw dev wlan0 link`: 2.4 GHz
      or 5 GHz; the RTL8821CS is dual band), power save (`iw dev wlan0 get power_save`, try `set power_save off`; NetworkManager's
      `wifi.powersave=2`), signal and rate (`iw dev wlan0 station dump`), the rtw88 module options (`disable_lps_deep`, `disable_msi`),
      SDIO clock, an `iperf3` run against the PC. If 5 GHz is the fix, prefer it in `wifi.txt` handling (`band=a` for the connection) and in
      NetworkManager's roaming settings. First start would drop from about an hour to minutes. S/M
      Measured 2026-11-27 (v0.7.0): the radio is not the limit. RG40XX-H on 5 GHz (-59 dBm, 390/263 Mbit/s, power save off): a plain
      `curl` download from Cloudflare runs at 10.4 MB/s; the RG28XX over the USB share, 12.2 MB/s. A weak 2.4 GHz or -79 dBm link is the
      likely cause of the old ~1 MB/s. The card is the next limit: slot 1 runs SD high-speed at 3.3 V (`mmc0: new high speed SDXC card`, 50 MHz
      4-bit; the device tree has `no-1-8-v` and no `vqmmc` supply, as on the board), so sequential I/O tops out near 23 MB/s read and 18-22 MB/s
      write with fsync, on both handhelds. Steam's own download pipeline (zstd, SHA, many small files, fsync) is what is left to look at: time a
      real Steam install with `iostat`/`top` before changing anything. S/M

## 2. Games
- [x] Renderer choice on this GPU (WineD3D on Panfrost via `PROTON_USE_WINED3D=1`; DXVK per game): compare DXVK-on-llvmpipe vs `PROTON_USE_WINED3D=1` (Panfrost GL 3.1)
      on Geometry Wars (FPS, CPU); pick a default. S
- [x] sunshineinabox/proton-armv8 (ARMv8.0 Proton 11, no LSE) installs itself: `mdeck-install-proton` downloads the
      pinned release (SHA256 in `/usr/local/share/mdeck/proton-armv8.conf`) into `compatibilitytools.d` before
      Steam's first start, and `mdeck-steam-defaults` makes it the global compatibility tool unless one is set.
      LSE-Emu stays for the client only. Verified on a from-scratch image (2026-11-25).
- [~] Native x86 Linux games through FEX (WORKS 2026-11-26: Hotline Miami's title screen and first level run from Steam; open: more titles, pad input, first-launch time, auto-install of the FEX tool and SLR 4.0; started 2026-11-26; DroidDeck does this too, `droiddeck-fex`). Findings: Steam's own
      chain (Steam Linux Runtime 1.0 -> 2.0 -> Valve's `FEX` tool, app 3127680) needs SteamOS's `/usr/share/guestos/fex-mesa`
      guest OS and fails here (it runs pressure-vessel under FEX and cannot import host graphics); FEX itself runs x86 programs
      fine from Steam's runtime platform (`uname` says x86_64) once `vm.overcommit_memory=1` (FEX reserves 4-6 GB, the default
      heuristic refuses it and every fork fails with ENOMEM). Valve's FEX app ships the GL/DRM/ALSA/Vulkan thunks (guest and
      host). Plan: `mdeck-fex` (FEX + Steam Linux Runtime 4.0 platform as guest root + thunks) as a Steam compatibility tool
      (`from_oslist linux`) for games with only a Linux build. S/M
      Open items for it: (a) DONE 2026-11-27: windows larger than the 640x480 panel (Eets 800x600, Hotline Miami 1280x720) are fitted by
      `mdeck-focus` calling `mdeck-fit W H` (a letterboxed RandR transform on the whole X screen, GPU-scaled through glamor; the game window
      loses its decorations and moves to the origin; `mdeck-fit reset` when focus leaves it); checked on the RG28XX with Hotline Miami, the
      whole 1280x720 title and menu fit; the earlier idea was: X-level scaling for the game's lifetime
      (`xrandr --output DSI-1 --scale-from WxH` or `--transform`, measuring the cost of the software transform on the A53), or have
      `mdeck-focus` resize an oversized window to the root size and see whether the game follows (SDL/FNA windows usually do not); (b) pad
      input in FEX games (Steam Input's virtual pad through FEX; only the keyboard was checked); (c) the launcher windows some games
      show first (Hotline Miami's Qt launcher needs a pointer): a per-game launch option that skips it; (d) Steam installing the FEX tool
      and Linux Runtime 4.0 by itself (`require_tool_appid` in the manifest does NOT work: Steam then wraps our tool in the required tool's whole chain, SLR 4.0 and Valve's FEX app, and that chain fails without SteamOS's `fex-mesa`; so the tool has no dependency). Done another way (2026-11-27): `mdeck-compat-default` asks for both tools whenever a Linux x86 game is installed, presses Install on Steam's dialog itself, and asks again every 2 minutes (6 times) until they appear; checked by removing both from the RG28XX with Steam online: both came back with no input and a FEX game ran. 
- [~] Never livelock on memory: earlyoom (games first), MGLRU `min_ttl_ms`, PSI game kill in the
      memory-locked `reach-guard` (plus a real sshd probe). Verify with a deliberate memory hog. S
- [x] Game windows on top, Steam button menu over games and back: `GAMESCOPE_WAYLAND_DISPLAY` turns on
      Steam's gamescope logic, `mdeck-focus` plays gamescope's side (base layer, overlay plane, focus). S
- [x] Steam menu in game opens in ~6-9 s now (measured by `mdeck-gametest` on the v0.2.1 image; was 10-20 s).
- [ ] Game mode for 1 GB: suspend or unload steamwebhelper while a game runs, per-game zram/swap
      (Switchdeck's `SD_GAMEMODE`). Measure free RAM in game before/after. M
      Measured 2026-11-27 (RG28XX, Geometry Wars via Proton in front): 839 of 975 MB used, 136 MB available, 1031 MB in zram (861 MB of data
      held in 280 MB, 3:1), the game 180 MB resident and all steamwebhelper processes together about 240 MB resident (the rest of Steam's UI is
      already in zram). The kernel already evicts the UI, so a `memory.reclaim` nudge when a game takes focus would free little and cost zstd time;
      it is not worth building until a title runs out of memory with the current guards. Unloading the web helper entirely would break the
      Guide-button menu.
- [ ] Steam in-game overlay back in the container: LSE-Emu must initialise before the overlay there too
      (container-side wrapper or LD_AUDIT-based early handler). M
- [x] Controller inside games: verified 2026-11-26 on Geometry Wars (pad presses skip the logo and move the menu highlight
      through the container); Steam button menu in game already worked. Analog sticks verified too (a held left stick flew the ship into the corner;
      InputPlumber's `SendEvent` takes stick values only as `ad`, other types are silently ignored; `mdeck pad stick:` uses it). S
- [ ] A small compatibility list: which titles run, at what FPS (`docs/games.md`). ongoing

## 3. SteamOS session parity
- [~] Settings pages checked 2026-11-26 (System, Display, Power render and work: update channel, brightness slider, dim/sleep
      timers, scaling); only the performance and charge-limit controls are missing. steamos-manager (with Armada's patch notes: `CpuScaling1`, `LowPowerMode1`, `BatteryChargeLimit1`,
      brightness) so Steam's own settings (brightness, performance, power) work. M/L
- [x] InputPlumber is in (controller as a Steam Deck). `handheld-keys` (volume and brightness keys) still stands; replace it only if needed. S
- [x] Power menu: Restart verified; Shut down uses the same path and real poweroff works (dev mode is off in releases).
- [ ] First-boot experience: Steam's OOBE (Wi-Fi setup via NetworkManager, sign-in QR) on a fresh image. M
- [ ] Boot splash (Plymouth, SteamOS-style) and boot-time budget. S
- [ ] Steam UI speed: CEF on the GPU (`CEF_GPU=1`, Panfrost GLES) vs software; webhelper memory. M
- [ ] Desktop mode via `steamos-session-select desktop` (optional, lightweight). M

- [x] The gray "cast" square over the launch screen's controller diagram (and other videos) is fixed (2026-11-27). It is Chromium's overlay
      cast button, drawn at the top-left of every `<video>` that can cast: the launch screen plays `steamui/movies/steamdeck_*.webm`.
      Found on the RG40XX-H by catching the screen (text "This game will use the Official Layout"; Steam's class names are hashed) and
      grabbing the plane with `kmsgrab`. `--disable-blink-features=RemotePlayback` does not remove it and neither does setting the
      `disableRemotePlayback` property (the button reads the content attribute). `mdeck-ui-fixes.service` (`mdeck ui-fixes`) keeps a DevTools
      connection per Steam UI page and sets `disableremoteplayback` on each `<video>` as it is added (a MutationObserver, registered with
      `Page.addScriptToEvaluateOnNewDocument` and run once on the current document). Checked with Sonic Mania. It needs `CDP_PORT` in
      `/etc/steam-session.conf` (the default). The screen appears for games with an official layout.

## 4. Hardware
- [ ] Sleep/wake: ROCKNIX PR #3316 approach (TF-A `SYSTEM_SUSPEND` + SRAM stub built for this unit's DRAM
      type and timings, `opp-suspend`, axp20x-pek wake, phy/mmc fixes). Test only with `rtcwake` alarms. M/L
- [x] Brightness from Steam's slider (Steam writes the backlight; udev rule for access).
- [x] Bluetooth (2026-11-26): the RTL8821CS controller was already `hci0`; bluez and PipeWire's Bluetooth audio are in the image and
      Steam's Bluetooth page scans (pairing with a real headset or pad not tested yet). S
- [ ] stick RGB LEDs, rumble (FF on the pad),
      headphone-jack switching, HDMI out, Bluetooth (RTL8821CS), charge limit. S each
- [ ] CPU/GPU governors (schedutil, Panfrost devfreq), thermals, battery life measurement. S/M
- [x] Standalone boot from slot 1 (`uboot/build.sh card`): verified 2026-11-25, root on mmcblk0.
- [ ] The slot-2 card as a Steam library. M
- [ ] Detect the DRAM revision at install (read the stock boot0 before overwriting) or ship per-revision
      U-Boots. M

## 5. GPU / gamescope (long shot)
- [x] PanVK on Bifrost v7 (Mesa 26.1, `panvk-run`): works for native Vulkan, Vulkan 1.0, cannot run DXVK or gamescope (no robustness2, geometry shaders). Revisit with Mesa 26.3 (Vulkan 1.3 on v7) once packaged. S
- [ ] Hardware DXVK research plan (docs/research/panvk-vulkan-dxvk.md, from the owner's gist, 2026-11-26), in order:
      (1) [built 2026-11-26: `tools/mesa/build.sh` cross-builds Mesa 26.3.1 PanVK + Panfrost GL/EGL/GBM for arm64 into a `/opt/mesa-mdeck` tarball (7 MB, X11 only, Docker volume cache); `tools/mesa/try-on-device.sh` installs it in isolation and records `vulkaninfo` and the DXVK-relevant features; waiting for the device] reproducible Mesa 26.3.1+ build in an isolated prefix (`VK_DRIVER_FILES`), record `vulkaninfo` and regress Xorg/Steam/WineD3D. M
      (2) [feature audit done 2026-11-27: Mesa 26.3.1 PanVK on the G31 is Vulkan 1.3 but has no geometry/tessellation shaders, clip/cull
      distance, fillModeNonSolid, robustness2 or transform feedback, which DXVK requires; table in docs/research/panvk-vulkan-dxvk.md]
      feature audit on the device (robustness2/nullDescriptor, transform feedback, descriptor indexing, geometry emulation),
      then DXVK version audit: D3D9 first, 1.10.3 as a diagnostic, the DXVK inside our Proton, then D3D10/11. M
      (3) read and selectively port ideas from JimVulkan/mali-panvk (Android kbase; reuse NIR lowering and feature code, keep
      the Linux Panfrost kmod and WSI). L, high risk
      (4) Gamescope audit as a separate track (null descriptors, modifiers, dma-buf sync, H700 scanout limits). L
      (5) RK3326/RK3566 as the second hardware target for the shared Bifrost work (RK3566 has LSE atomics). M
- [x] Real gamescope on llvmpipe (2026-11-25): runs with `rootfs/src/vk-fake-drm.c` (`NESTED_GAMESCOPE=1`), but ~90 % of a
      core, black panel and Steam SIGBUS inside it. TABLED: the Xorg + `mdeck-focus` path costs ~0 %. Reopen if a GPU Vulkan
      path appears; the open questions are the black screen and the SIGBUS (docs/findings.md). L
- [ ] gamescope on the GPU: make `VK_EXT_robustness2` nullDescriptor optional, handle the split display/GPU devices
      (gamescope #2070), synthesize an EDID for the DSI panel (Armada patches 0002/0003). L, high risk
- [ ] Until then keep Xorg + openbox (works, low overhead).

## 6. Release
- [ ] Release images on GitHub with an install guide (flash, first boot, recovery).
- [ ] Other H700 devices (RG35XX family, RG40XX-V): DTB and DRAM per device.
- [x] Ethernet over the USB cable for devices without Wi-Fi (RG28XX): `usb-gadget` adds a CDC-NCM function when the board has no
      `wlan0` (or `/boot/firmware/usbnet` exists); Windows, macOS and Linux bind it without a driver. NetworkManager profile
      `mdeck-usb` (udev override `86-mdeck-usb.rules` because Debian hides gadget interfaces) takes DHCP when the PC shares its
      connection and always keeps 169.254.58.58, which the PC reaches with no setup (verified on the RG40XX-H: ping and SSH).
      Internet: Windows Internet Connection Sharing from the Wi-Fi/Ethernet adapter to the "UsbNcm" adapter.
- [x] RG28XX (2026-11-27): DRAM values from its stock boot0 (`tools/boot0-dram.py`: LPDDR4 672 MHz, only three delay words differ from
      the RG40XX-H; `uboot/rg28xx_lpddr4_defconfig`), ROCKNIX's `sun50i-h700-anbernic-rg28xx.dtb` with our kernel (panel firmware,
      joypad with 17 GPIO keys and rumble, AXP717, USB Ethernet all came up), booted over FEL from its own muOS (`fel-boot.sh` falls back
      to muOS's python for the efex reboot). The panel is 480x640 portrait: `mdeck-rotate` rotates the X output at session start from the
      connector's panel orientation ("Left Side Up" -> `left`, matching the kernel console). Smoke test 0 failures, Geometry Wars
      (Proton) and Hotline Miami (FEX) pass the game test. One image per device from the same rootfs (`DEVICE=rg28xx tools/build-image.sh`,
      CI matrix); `mdeck-update` downloads `microdeck-<device>.img.xz` by `/etc/mdeck-device`. Open: a release with it, the DTB from our own
      kernel build instead of ROCKNIX's, whether one U-Boot could serve both devices (probe at boot, cross-check the DRAM values under stress).
      Not yet tried (needs the card moved by hand): the RG28XX booting from slot 1 with the image's own `card-rg28xx.bin` U-Boot.

## Ideas from Handtop (junsulee119/handtop, reviewed 2026-11-26)
Handtop is a Debian desktop (labwc, no Steam) for the sibling RG35XX-H: same H700, ROCKNIX kernel/DTBs unchanged, Debian
trixie userspace. No gaming stack, but several transferable parts:
- [x] `recovery.txt` on the boot partition with `mdeck=previous` forces the previous release at the next boot (done; the
      initramfs reads it, renames it to `.used`).
- [x] The updater refuses below 40 % battery without the charger (done in `mdeck-update apply`).
- [~] **Sleep with s2idle** (2026-11-27: WORKS on the RG28XX with an RTC wake; the power-button wake is the one part not yet confirmed).
      The kernel offers `s2idle` and needs no TF-A support. What it took: (1) `vhci_hcd` refuses to suspend while a device is attached
      (Steam's virtual Deck controller), so InputPlumber is stopped before and started after (`/usr/lib/systemd/system-sleep/mdeck-sleep`);
      (2) the SoC RTC `rtc1` (sun6i, `7000000.rtc`, GIC IRQ 136, wake enabled) wakes it, `rtc0` is an I2C pcf8563 chip with no wired alarm;
      its clock starts at 1972 and an absolute alarm time then never fires, so use a relative alarm (`echo +30 > /sys/class/rtc/rtc1/wakealarm`).
      Measured with the full stack: `systemctl suspend` with Steam running and with a game in front (Geometry Wars) slept 35-40 s and
      resumed: panel re-initialised, USB network back, Steam UI and virtual pad back, the game still focused, audio sink present. The
      resume came from the RTC alarm each time. Shipped OFF by default (v0.7.1+): an empty file `sleep` on the boot partition (or
      `mdeck-sleep on`) turns it on (`/run/systemd/sleep.conf.d/50-mdeck.conf`: AllowSuspend=yes, freeze; logind: short power press suspends, long
      press powers off; a 3 s power-key hold-off after resume so the waking press does not sleep it again). `mdeck-sleep test [secs]` sleeps
      through the real path with an RTC fallback and prints what woke it (`power-button` or `rtc`). ROOT CAUSE FOUND (2026-11-27 08:00, see the OPEN PROBLEM below for how it showed): s2idle keeps the monotonic clock running, so a
      sleep longer than a service's 3-minute `WatchdogSec` makes systemd kill that service the instant the handheld wakes (the journal shows
      `Watchdog timeout (limit 3min)! ... SIGABRT` for logind, journald, timesyncd right after `PM: suspend exit`, after the 3, 10 and 30 minute
      sleeps). logind restarts without announcing the wake, so NetworkManager stays "asleep" and the network never comes back: the RG28XX
      kept `usb0` down for 90 minutes and the RG40XX-H would have had no Wi-Fi (awake but unreachable). Fix: `WatchdogSec=0` drop-ins for the five
      units that have one (hostnamed, journald, logind, timesyncd, udevd, `10-mdeck-no-watchdog.conf`). Verified on the RG28XX: a 4-minute sleep,
      zero watchdog kills, NetworkManager reconnected 16 s after the wake. Verified on the RG28XX running v0.7.2 (2026-11-27 09:53): the 30-minute case that failed before
      now wakes on the RTC with zero watchdog kills, NetworkManager reconnects in about 5 s and the internet is reachable. Still to do on the
      RG40XX-H: a 30-minute sleep after updating it (its Wi-Fi path differs: SDIO unbind and rebind).
      Seen once (RG28XX, first sleep after the rebrand, 40 s): after the wake the handheld's usb0 was up and the gadget had restarted itself, but
      Windows kept the UsbNcm adapter "Disconnected" (no internet over USB) until `systemctl restart usb-gadget` was run a second time; six
      earlier sleeps reconnected on their own. If it recurs, restart the gadget a second time in the sleep hook a few seconds after the first.
      OPEN PROBLEM (2026-11-27 05:20): a 30-minute test (`mdeck-sleep test 1800`, RTC alarm +1800 s) on the RG40XX-H,
      running standalone from slot 1 on battery over Wi-Fi, never came back: no ping or SSH 25 minutes after the alarm, while 40 s tests on the
      same unit (two) and on the RG28XX (four, including Steam's own Sleep and a game in front) all woke on time and reconnected in about 8 s.
      Candidates: the long RTC alarm did not fire (try +120, +300, +600 on the RG28XX over adb, where a failure is visible), the Wi-Fi chip
      lost power over a long sleep and the 18 s rebind retry gave up (the unit has no USB link to look), or something on resume that a long sleep
      exposes (reach-guard, thermals, the watchdog). Needs the handheld's serial console or a USB cable on the PC, and a power-button press
      to get it back. Until a long sleep wakes reliably the feature stays opt-in. Follow-up the same morning: the RG28XX (USB link, no Wi-Fi chip)
      slept 3 min, 10 min and 30 min and woke at 180.7 s, 600.8 s and 1800.7 s (RTC), so long alarms work and the failure is specific to the
      RG40XX-H: the leading suspect is its Wi-Fi chip not returning after a long sleep (awake but cut off; reach-guard only probes sshd locally).
      `mdeck-sleep-wifi` now retries the rebind 8 times, logs each try (`journalctl -t mdeck-sleep`) and reboots as a last resort. The failed unit's
      previous boot journal (`journalctl -b -1` after a power cycle) says whether it woke and what the hook saw: read it first. Next: someone presses the power button
      during `mdeck-sleep test` on each handheld; if it reports `power-button`, make sleep the default. Then: battery drain while asleep (Handtop
      reports 5-6 %/hour; measure on battery, both handhelds were on USB power), mute the DAC before sleeping and unmute after, Wi-Fi
      reconnect time on the RG40XX-H after resume, what Steam's own idle-sleep timer does, and rtc1's clock (set it from system time at boot). M
- [x] Battery guard (2026-11-26, `mdeck-battery`): on battery, below 15 % the CPU is capped at 1.008 GHz (lifted when charging or above 20 %), at
      5 % it syncs and powers off cleanly. Policy is unit-tested; needs a discharge test on the handheld (screen dimming is Steam's). S
- [x] Rumble (patch carried 2026-11-26, in the next kernel build; verify on hardware): Handtop found a deadlock in the ROCKNIX `rocknix-singleadc-joypad` driver (the ff-memless play callback runs in
      atomic context but takes a mutex the PWM work item holds; freezes the whole handheld) and patches it
      (`build/kernel/rocknix-joypad/0001-rumble-no-mutex-in-atomic-context.patch`). We build the same driver
      (`kernel/build.sh`, hackbar/rocknix-joypad): check our source for the pattern and carry the fix. S
- [ ] Hardware video decode on the H700 (Cedrus): Handtop adds `sunxi-cedrus.ko` with an H616 compatible string and a 64-byte
      output stride patch so Panfrost can import frames, a DTB overlay for the video engine with no `iommus` (the IOMMU made the
      display engine fault), and `cma=256M`. Useful for Steam's video playback and streaming (Moonlight/Remote Play) later. M
- [ ] Boot-partition support knobs: `panel.txt` (force a DTB when the screen is garbled; Handtop picks the DTB at boot from a
      board GPIO), timed boot logs (60 s and 3 min) next to our `bootlog-N.txt`. Relevant to other H700 devices. S
- [ ] A `boot-abi` stamp (platform, kernel release, SHA-256 of `KERNEL`) checked before installing kernel modules, and a
      kernel-deviation list kept in one doc in the same PR as each change (their `docs/kernel.md`). S
- [ ] Pin upstream inputs with checksums and check them for drift weekly (their `build/upstreams.conf`); our kernel and
      InputPlumber pins are similar but not checked automatically. S
- [ ] A controls trial-and-revert pattern (15 s) for risky remaps, if we ever ship a remap UI. S

- [x] Upgrade test in CI (2026-11-27, job `upgrade`): the latest published release boots in the virtual device and is updated in place to the
      build under test, by the old release's own updater and initramfs (`tools/qemu/ci.sh <new> <previous>`, `tests/qemu/update_download.py`;
      first run 17 min including the QEMU kernel build, cached after).
      Since the MicroDeck rename it only runs once a release named `microdeck-<device>.img.xz` exists: a pre-rename release cannot update to a
      renamed build (old updater feed gone, old initramfs looks for the old `steamroot` label and the QEMU test, which boots with a fixed initrd, loops
      forever on it; a real card recovers on its next boot because the install also replaces the initrd).

## Other projects reviewed (2026-11-26)
- **Allium OS** (goweiwen/Allium): a Rust launcher for the Miyoo Mini family, not H700. Useful shape: a small always-on daemon
  (`alliumd`: hotkeys, power, launching) plus short-lived UI binaries, and a desktop simulator so UI work needs no device. Its
  suspend/resume mechanism is not documented in the README; nothing to copy for H700 sleep.
- **Owner's Katamari PortMaster port** (`i-port-katamari`): runs an ARMv5 Android engine through a bionic/JNI loader on armhf, no
  emulator. Reusable habits: probe the SDL video backend at run time (`--sdl-info`) instead of assuming one, a `fit` scaling
  default for 640x480 panels (our Eets window is 800x600 on a 640x480 panel: add a per-game "fit" scale, e.g. an X11 scaling
  wrapper in `mdeck-fex`), bundle only the libraries a port needs with a manifest, and a packaging check that refuses to ship
  game data. PortMaster's `gptokeyb` `.gptk` maps are the analogue of Steam Input templates here.
- **QEMU virtual device** (`tools/qemu/`, `tests/qemu/`): a generic arm64 kernel with virtio built in boots our real initramfs and
  image, so the updater (install, rollback, recovery.txt) is tested without hardware.

## References
- Prior-art survey: Armada (armada-os/armada), Valve Holo Core aarch64, Steam Frame userspace ports,
  SildurFX/Switchdeck + LSE-Emu, sunshineinabox/proton-armv8, ChimeraOS gamescope-session-steam,
  ROCKNIX H700 (suspend PR #3316). Details in `findings.md`.
