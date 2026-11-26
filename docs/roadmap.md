# SteamOSXX roadmap

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
- [x] Automation: `sxx` (Steam DevTools + virtual test pad), `tools/smoke.sh`, screenshots, launch tracing.
- [x] First game: Geometry Wars through Proton Experimental (ARM64) + FEX + LSE-Emu (DXVK on llvmpipe).

## 0. Initial release (v0.1.0) checklist
- [x] Image boots from a single card in slot 1 (verified 2026-11-25).
- [x] First start installs the Steam client and the ARMv8.0 Proton itself, with a progress window; Proton is the
      default for new games (`sxx-compat-default`).
- [x] Steam no longer re-extracts its client on every start (`steamwebhelper.sh` patched after the updater's check).
- [x] Real poweroff works with dev mode off (2026-11-25); dev mode is a build option (`DEV_MODE=1`), off in CI.
- [x] Wi-Fi without secrets in the image: `wifi.txt` on the boot partition (`sxx-wifi-import`).
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
- [x] The pad is a native Steam Deck controller (28de:1205 over USB/IP, InputPlumber; own kernel 7.2.0-sxx), verified
      2026-11-26: Deck glyphs, no "External Controller Translation" dialog, game test passes on the CI image.
- [x] `sxx-gametest` cancels an account-in-use dialog (and says so) and dismisses the controller hint. Rumble verified:
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
- [x] State and data kept apart from the root (2026-11-26): `sxxdata` on a third partition after a fixed 3 GiB root,
      mounted at /home; first boot creates it or finds and reuses it, and Wi-Fi/SSH settings are mirrored there, so a
      reflash keeps games, Steam login, Proton and settings. Verified: flash, restore once, flash again, everything
      survived. (Found and fixed on the way: the image must end exactly at the end of the root.)
- [ ] Pre-seed or background-fetch Steam and Proton: ship them on the data partition or fetch them in a `Nice=19`,
      idle-I/O unit with chunked, hash-verified, resumable downloads (their updater pattern), removing the 1.1 GB
      first-start wait. M
- [ ] Mesa trimming: nibOS builds Panfrost-only with no LLVM (libgallium 21 MB instead of 54 MB plus 171 MB libLLVM)
      and carries two Panfrost patches (write-combined index scan, keep BOs mapped). The G31 uses Panfrost too, but we
      rely on llvmpipe for the DXVK CPU path, so test a Panfrost-only build against the cost of losing that. M
- [x] Boot is already short (2026-11-26, `systemd-analyze`: 3.8 s kernel + 7.9 s userspace, Steam session at 7.4 s); the time to Steam's UI is Steam itself, so there is nothing
      worth trimming. Original idea, kept for reference: boot trimming from docs/boot-time.md that transfers to Debian: a systemd generator that reads the launcher's
      files ahead of time (at idle priority), masking unused generators. S
- [x] In-place updater (2026-11-26, v0.4.0): `sxx-update` (check/apply, wired to Steam's Check For Updates through
      `steamos-update`) stages the release's root and boot files on the data partition; the initramfs writes them at the next
      boot (root first, boot files last through rename, `pending` marker makes an interrupted install repeat). Verified from
      Steam's UI on hardware, twice. Rollback added (2026-11-26): the last installed image is kept, a release is on trial until Steam's UI has been up 30 s, three failed boots reinstall the previous one (tested with a deliberately broken release). Still open: A/B root and signed, chunked updates (minisign
      manifest, 16 MiB zstd chunks, `min_from` and state `migrate` numbers): the
      install is ten minutes of SD writes (reading to skip unchanged blocks is no faster on this card). L
- [ ] Read-only root with a writable overlay on the state partition, which makes slot images reproducible. M
- [ ] SPL Falcon boot (skip U-Boot proper) for boot time: needs an Allwinner port, boot time is not our main pain. L
Not copied: Arch as the base, lz4-only zram (our lzo-rle plus idle zstd keeps the capacity), 3 GiB root slots (too big
once Steam and Proton are on the card), the RK3568 SPL and watchdog specifics.

## 1. Reproducibility (do first; many fixes were applied live)
- [ ] Diff the running device against `overlay/` + `rootfs/` and fold in anything missing. S
- [x] Rebuild rootfs and image from scratch, flash slot 2 from muOS, FEL-boot, restore the Steam backup,
      `tools/smoke.sh` and `sxx-gametest` pass (2026-11-24). `tools/reflash-slot2.sh`, `backup-steam.sh`,
      `restore-steam.sh`. `tools/cycle.sh` chains build + flash + restore + test (written 2026-11-25, not yet run end to end).
- [~] Pin the Steam bootstrap: `tools/fetch-steam.sh` installs the arm64 client from the CDN manifest
      (each package SHA256-checked) into a clean seed tar; `STEAM_SEED=` puts it in the image. Still to do:
      pin a manifest version, and check that the first start does not re-download. M
- [ ] CI: GitHub Actions builds U-Boot, rootfs and image (arm64 runners or QEMU). M

## 2. Games
- [x] Renderer choice on this GPU (WineD3D on Panfrost via `PROTON_USE_WINED3D=1`; DXVK per game): compare DXVK-on-llvmpipe vs `PROTON_USE_WINED3D=1` (Panfrost GL 3.1)
      on Geometry Wars (FPS, CPU); pick a default. S
- [x] sunshineinabox/proton-armv8 (ARMv8.0 Proton 11, no LSE) installs itself: `sxx-install-proton` downloads the
      pinned release (SHA256 in `/usr/local/share/sxx/proton-armv8.conf`) into `compatibilitytools.d` before
      Steam's first start, and `sxx-steam-defaults` makes it the global compatibility tool unless one is set.
      LSE-Emu stays for the client only. Verified on a from-scratch image (2026-11-25).
- [~] Native x86 Linux games through FEX (WORKS 2026-11-26: Hotline Miami's title screen and first level run from Steam; open: more titles, pad input, first-launch time, auto-install of the FEX tool and SLR 4.0; started 2026-11-26; DroidDeck does this too, `droiddeck-fex`). Findings: Steam's own
      chain (Steam Linux Runtime 1.0 -> 2.0 -> Valve's `FEX` tool, app 3127680) needs SteamOS's `/usr/share/guestos/fex-mesa`
      guest OS and fails here (it runs pressure-vessel under FEX and cannot import host graphics); FEX itself runs x86 programs
      fine from Steam's runtime platform (`uname` says x86_64) once `vm.overcommit_memory=1` (FEX reserves 4-6 GB, the default
      heuristic refuses it and every fork fails with ENOMEM). Valve's FEX app ships the GL/DRM/ALSA/Vulkan thunks (guest and
      host). Plan: `sxx-fex` (FEX + Steam Linux Runtime 4.0 platform as guest root + thunks) as a Steam compatibility tool
      (`from_oslist linux`) for games with only a Linux build. S/M
- [~] Never livelock on memory: earlyoom (games first), MGLRU `min_ttl_ms`, PSI game kill in the
      memory-locked `reach-guard` (plus a real sshd probe). Verify with a deliberate memory hog. S
- [x] Game windows on top, Steam button menu over games and back: `GAMESCOPE_WAYLAND_DISPLAY` turns on
      Steam's gamescope logic, `sxx-focus` plays gamescope's side (base layer, overlay plane, focus). S
- [x] Steam menu in game opens in ~6-9 s now (measured by `sxx-gametest` on the v0.2.1 image; was 10-20 s).
- [ ] Game mode for 1 GB: suspend or unload steamwebhelper while a game runs, per-game zram/swap
      (Switchdeck's `SD_GAMEMODE`). Measure free RAM in game before/after. M
- [ ] Steam in-game overlay back in the container: LSE-Emu must initialise before the overlay there too
      (container-side wrapper or LD_AUDIT-based early handler). M
- [x] Controller inside games: verified 2026-11-26 on Geometry Wars (pad presses skip the logo and move the menu highlight
      through the container); Steam button menu in game already worked. Analog sticks verified too (a held left stick flew the ship into the corner;
      InputPlumber's `SendEvent` takes stick values only as `ad`, other types are silently ignored; `sxx pad stick:` uses it). S
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

- [ ] Low priority UI glitch: a small gray square with a monitor-and-waves ("cast") glyph appears at the top-left of Steam's launch
      screen controller diagram (the "This game will use the Official Layout" screen), overlapping the D-pad icon; it is not on
      the interstitial screens. Not Chromium's cast button: it is Steam's own element. Hypothesis: Steam's connection-type badge
      for our virtual Deck controller (a USB/IP `vhci_hcd` device, 28de:1205) reads as "remote". Next: catch the element
      (hold the launch screen open, `document.elementsFromPoint` at CSS px = screen px x 1.47) and see what decides the glyph;
      the fix, if any, belongs in how InputPlumber presents the device (its sysfs/HID bus attributes), not in Steam. S

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
      (1) reproducible Mesa 26.3.1+ build in an isolated prefix (`VK_DRIVER_FILES`), record `vulkaninfo` and regress Xorg/Steam/WineD3D. M
      (2) feature audit on the device (robustness2/nullDescriptor, transform feedback, descriptor indexing, geometry emulation),
      then DXVK version audit: D3D9 first, 1.10.3 as a diagnostic, the DXVK inside our Proton, then D3D10/11. M
      (3) read and selectively port ideas from JimVulkan/mali-panvk (Android kbase; reuse NIR lowering and feature code, keep
      the Linux Panfrost kmod and WSI). L, high risk
      (4) Gamescope audit as a separate track (null descriptors, modifiers, dma-buf sync, H700 scanout limits). L
      (5) RK3326/RK3566 as the second hardware target for the shared Bifrost work (RK3566 has LSE atomics). M
- [x] Real gamescope on llvmpipe (2026-11-25): runs with `rootfs/src/vk-fake-drm.c` (`NESTED_GAMESCOPE=1`), but ~90 % of a
      core, black panel and Steam SIGBUS inside it. TABLED: the Xorg + `sxx-focus` path costs ~0 %. Reopen if a GPU Vulkan
      path appears; the open questions are the black screen and the SIGBUS (docs/findings.md). L
- [ ] gamescope on the GPU: make `VK_EXT_robustness2` nullDescriptor optional, handle the split display/GPU devices
      (gamescope #2070), synthesize an EDID for the DSI panel (Armada patches 0002/0003). L, high risk
- [ ] Until then keep Xorg + openbox (works, low overhead).

## 6. Release
- [ ] Release images on GitHub with an install guide (flash, first boot, recovery).
- [ ] Other H700 devices (RG35XX family, RG40XX-V): DTB and DRAM per device.

## Ideas from Handtop (junsulee119/handtop, reviewed 2026-11-26)
Handtop is a Debian desktop (labwc, no Steam) for the sibling RG35XX-H: same H700, ROCKNIX kernel/DTBs unchanged, Debian
trixie userspace. No gaming stack, but several transferable parts:
- [x] `recovery.txt` on the boot partition with `sxx=previous` forces the previous release at the next boot (done; the
      initramfs reads it, renames it to `.used`).
- [x] The updater refuses below 40 % battery without the charger (done in `sxx-update apply`).
- [ ] **Sleep with s2idle** instead of waiting for TF-A suspend: the kernel already offers `s2idle` (default `mem_sleep`).
      First test 2026-11-26: the suspend was refused by `vhci_hcd` ("1 active connection", the virtual Deck controller), so
      InputPlumber must be stopped (or its USB/IP port detached) before and started after; then a wake source: the sun6i RTC
      is `/dev/rtc1` (`/dev/rtc0` is an I2C RTC without wakeup) and holds 1970, so set it from system time first
      (`hwclock` is not installed). A test with the virtual pad stopped left the device unreachable (the wake did not fire):
      find a wake that works (power key `axp20x-pek`, RTC alarm) before any release. Handtop reports ~5-6 %/hour in s2idle. M
- [ ] Battery saver: cap the CPU at 1.0 GHz and dim the screen on low battery; clean shutdown at 5 % (Handtop's policy). S
- [ ] Rumble: Handtop found a deadlock in the ROCKNIX `rocknix-singleadc-joypad` driver (the ff-memless play callback runs in
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

## References
- Prior-art survey: Armada (armada-os/armada), Valve Holo Core aarch64, Steam Frame userspace ports,
  SildurFX/Switchdeck + LSE-Emu, sunshineinabox/proton-armv8, ChimeraOS gamescope-session-steam,
  ROCKNIX H700 (suspend PR #3316). Details in `findings.md`.
