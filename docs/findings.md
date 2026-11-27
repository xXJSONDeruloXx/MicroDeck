# Findings log

Dated observations from bringing up the SteamOS-style image on the RG40XX-H. Newest last. Lessons that
change how we work also go into `lessons-learned.md`.

## 2026-11-24

### Boot
- First boot through FEL from muOS with our U-Boot (muOS LPDDR4 timings) booted: kernel 7.2.0, Tux + console
  on the panel, Xorg, Steam. The earlier attempt with `rdinit=/no-initramfs` (skipping ROCKNIX's built-in
  initramfs) reset within ~30 s and never reached our userspace (no journal, no first-boot marker); the same
  kernel with an external busybox initramfs (`INITRD`) boots. Not isolated further; the image now always uses
  the logging initramfs.
- Docker leaves `/etc/hostname`, `/etc/hosts`, `/etc/resolv.conf` empty in an exported rootfs; the kernel
  default hostname is then `ROCKNIX`. `build-image.sh` writes them after unpacking.
- Overlay files copied from Windows keep executable bits; systemd warns on every unit. The Dockerfile now
  chmods unit/config files 644.
- First boot grew the root partition to the 128 GB card (117 GB ext4). zram swap 975 MB is active.

### Hardware status on mainline (ROCKNIX DT `sun50i-h700-anbernic-rg40xx-h.dtb`)
- Display: DSI panel through sun4i-drm (`card1-DSI-1` connected, 640x480), backlight device present. HDMI
  connector exists (`card1-HDMI-A-1`, disconnected).
- GPU: Panfrost, desktop GL 3.1 / GLES 3.1 accelerated (Mesa 25.0.7, Debian), Xorg modesetting with glamor.
  Vulkan: only llvmpipe; Debian's Mesa does not ship PanVK for Bifrost v7 (needs a newer Mesa and
  `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`; gamescope additionally needs `VK_EXT_robustness2`/nullDescriptor,
  which PanVK only enables for v10+).
- Wi-Fi: RTL8821CS (`rtw88_8821cs`, built in) came up on first boot and joined the network from the profile
  converted out of muOS's wpa_supplicant.conf. `wifi-kick` was not needed this time.
- Input: `H700 Gamepad` (rocknix-singleadc-joypad, 484b:14df) uses standard codes: ABS_X/Y + ABS_RX/RY
  sticks, BTN_* face/shoulder buttons, BTN_DPAD_*; no remapper needed (muOS's `muOS-Keys` needed padmap).
  Volume keys are a separate `gpio-keys-volume` device; power key is `axp20x-pek`.
- Audio: H616 codec, card 0. The speaker works, but defaults are about -42 dB (DAC -21 dB plus Line Out
  -21 dB) under a 40 % PipeWire volume: inaudible. DAC and Line Out at 100 % (0 dB), `Speaker` on, volume
  left to PipeWire. `Line Out Source` stays `Stereo`. `steam-session-prep` sets this at every session start.

### Session
- Running Steam through `runuser` from a root service gave no logind session: no user systemd, so
  PipeWire/WirePlumber failed ("Dependency failed") and Xorg ran as root. Now `steam-session.service` is
  `User=steam` + `PAMName=login` + `TTYPath=/dev/tty7` running `startx`: logind session on seat0/tty7, rootless
  Xorg as steam, PipeWire + WirePlumber + pipewire-pulse active. Needs `kbd` (chvt) and `dbus-x11`.
- RTKit missing makes PipeWire fall back to nice 0; `rtkit` is now in the image.
- Steam's self-update stalled once at 10.7 MB with idle CPU and a working network; restarting the session
  resumed it. Watch for a repeat (possible LSE-Emu patching race in the downloader threads; fallback is
  `LSE_EMU_PATCH=0`, trap-only).
- Update download speed on mainline Wi-Fi: about 1-3 MB/s (muOS 4.9: about 0.45 MB/s).

### ROCKNIX H700 platform quirks worth reusing (from its SYSTEM squashfs, `usr/lib/autostart/quirks/platforms/H700`)
- Suspend mode `mem` by default (their TF-A carries an H616 PSCI system-suspend patch; ours is upstream
  TF-A lts-v2.12.1, which does not, so deep sleep needs that patch).
- Sleep hooks: mute the DAC before suspend and unmute after; LED handling; re-create the USB gadget after
  resume (musb drops the gadget session on suspend).
- CPU governor policy `cpufreq/policy0`; GPU devfreq at `/sys/devices/platform/soc/1800000.gpu/devfreq/...`;
  GPU overclock option; thermal sensor `thermal_zone2`.
- Panfrost GL extension override: `MESA_EXTENSION_OVERRIDE="-GL_OES_copy_image -GL_EXT_copy_image -GL_NV_copy_image -GL_ARB_copy_image"`
  (copy_image is broken/slow on G31 for some apps).
- Wi-Fi probe retry for RTL8821CS (`sdio:*v024CdC821*`), like our `wifi-kick`.
- Audio latency default 64 (RetroArch setting).
- Steam's bootstrapper re-downloads the whole package (~580 MB) when the cached zips in
  `Steam/package/` are missing ("Package file ... missing or incorrect size"), even with a valid
  `.installed` manifest. Seeding a Steam install from another device must include `package/*.zip*`.
- With the logind session, Xorg runs as `steam` with an auth cookie; root needs
  `runuser -u steam -- env DISPLAY=:0 XAUTHORITY=/home/steam/.Xauthority xwd -root` for screenshots.
- Volume keys (`gpio-keys-volume`) and menu+volume (backlight) handled by `handheld-keys.service`
  (backlight max 2499 on this panel).

### Sleep / wake (parked)
- ROCKNIX gets `mem` suspend on H700 from a TF-A patch (`uboot/tfa-patches/001-allwinner-h616-psci-system-suspend.patch`,
  from kailashrs' H700_rocknix_enhancement): BL31 copies a stub into SRAM A1, puts DRAM into self-refresh,
  WFIs, and on wake **re-trains DRAM with the parameters the stub was built with**. TF-A only enables system
  suspend when the running DRAM type and clock match a stub (`SUNXI_SUSPEND_STUB`, optional `..._STUB2`).
- So the stub must be built from this unit's LPDDR4 timings (the muOS values in `rg40xxh_2025_lpddr4_defconfig`);
  ROCKNIX's stub carries the ROCKNIX timings that do not train here and would hang on wake. ROCKNIX builds the
  stub in its u-boot package; that build has to be reproduced with our defconfig before testing.
- Test only with an RTC wake alarm (`rtcwake -m mem -s 20`) and the recovery loop in place: a hang during
  suspend is the one state the watchdog does not cover.

### SteamOS client mode (from ChimeraOS gamescope-session-steam, MIT)
- SteamOS UI features (system settings, power menu, OS update page) need
  `steam -gamepadui -steamos3 -steampal -steamdeck` plus helper commands on PATH: `steamos-session-select`
  (switch session), `steamos-update` (exit 7 = no update; `--supports-duplicate-detection` exits 0),
  `steamos-select-branch`, `jupiter-biosupdate` (exit 0). Stubs are in `overlay/usr/local/bin`.
- Power menu: Steam touches `$STEAMOS_STEAM_REBOOT_SENTINEL` / `$STEAMOS_STEAM_SHUTDOWN_SENTINEL` and exits;
  the session script then reboots or powers off. `STEAM_ENABLE_VOLUME_HANDLER=1` lets Steam handle the
  volume keys itself. The gamescope-specific variables (VRR, HDR, NIS, mangoapp) do not apply without gamescope.
- `upower` provides the battery to Steam (`battery_battery` and `line_power_axp20x_usb` on this device).

### First Big Picture on mainline (2026-11-24 20:56 UTC)
- After the self-update (download ~580 MB; extraction 4.5 min vs ~10 min on muOS), relaunch to web helper
  `BrowserReady` took 25 s (muOS: several minutes) and Big Picture painted about a minute later.
- The Steam login carried over from muOS through the seeded `~/.local/share/Steam` (no new QR scan).
- Big Picture shows battery and Wi-Fi in the status bar (upower, NetworkManager) and controller glyphs
  (the built-in pad is recognised with no remapping).
- Time zone was UTC; set to America/New_York (also in the image).
- adbd (Debian 34.0.5) does not recover its FunctionFS connection after a USB unplug/replug (adb shows
  `offline` until the gadget restarts). `90-usb-gadget-replug.rules` restarts `usb-gadget.service` when
  `axp20x-usb` reports power again. SSH over Wi-Fi was the way back in.
- On-screen keyboard in plain `-gamepadui`: A shows a mouse cursor in the screen centre and clicks there,
  which dismisses the keyboard; focus never leaves the Big Picture window and no new X window appears (the
  keyboard is drawn inside it). Trying SteamOS client mode (`-steamos3 -steampal -steamdeck`).
- **Root cause of the dismissing keyboard:** udev's input_id tags the `H700 Gamepad` as
  `ID_INPUT_TABLET`/`ID_INPUT_TABLET_PAD` (as well as joystick), so Xorg's "libinput tablet catchall" adopts it
  and its buttons become pointer clicks at the cursor, which starts in the screen centre. A press = click
  outside the keyboard. `80-h700-gamepad.rules` clears the tablet tags and sets `LIBINPUT_IGNORE_DEVICE=1`;
  Steam still reads the pad through evdev. Confirmed fixed on device. (SteamOS client mode did not change it.)
- SteamOS client mode works: SteamOS boot splash, then the Deck UI. The client calls
  `jupiter-initial-firmware-update check`, `gpu-trace --get-tracing-status`,
  `/usr/bin/steamos-polkit-helpers/steamos-devkit-mode --disable` and probes for a mangoapp window; stubs are in
  the overlay.

### Automation (no hands on the device)
- `mdeck` (on the device, stdlib Python; DevTools client adapted from DroidDeck's droiddeck-agent):
  `mdeck targets`, `mdeck eval [-t TARGET] JS`, `mdeck pad TOKENS` (virtual "MicroDeck Test Pad", uinput,
  pid.codes 1209:5a5a, standard evdev codes; Steam maps it like the built-in pad).
- Steam DevTools: `-cef-enable-debugging -devtools-port 8080` (from `CDP_PORT`), bound to 127.0.0.1 only.
  Targets in Big Picture: `SharedJSContext` (route, e.g. `/routes/library/home`), `Steam Big Picture Mode`
  (the window: `document.activeElement` is the focused item), `MainMenu_uid2`, `QuickAccess_uid2`,
  `notificationtoasts_uid2`. The Big Picture window asks for `minwidth=853&minheight=534`; the panel is
  640x480.
- `tools/smoke.sh` checks reachability, services, display, GPU, Wi-Fi, audio sink, battery, gamepad
  (and that X ignores it), the Steam route, pad navigation (focus must move) and memory, and saves a
  screenshot.
- Cursor: SteamOS's gamescope-session hides the cursor until pointer motion (`--hide-cursor-delay 3000`);
  Steam's guide + right stick chord moves a pointer and must still show it. `-nocursor` was wrong; the
  session runs `unclutter --start-hidden --timeout 3` instead.
- adbd also dies on host-initiated link drops (USB suspend/reset: `FUNCTIONFS_SUSPEND`, `FUNCTIONFS_DISABLE`),
  not only unplugs. A udev rule on `axp20x-usb` power events was the wrong tool (charging-state changes fire
  it too). `usb-gadget` now watches `/sys/class/udc/*/state` and exits (systemd rebuilds the gadget) when the
  link stays out of `configured` for 3 s after having been up.
- `session-N.scope` units of earlier Steam sessions show as failed after a session restart; the prep script
  runs `systemctl reset-failed "session-*.scope"`.

### First game: Geometry Wars (AppID 8400) through Proton Experimental (ARM64) (2026-11-24)
Launched from Steam, renders its intro. Four separate blockers, in the order they were hit:
1. **bwrap "Unexpected capabilities but not setuid".** systemd 257's pam_systemd gives user sessions an ambient
   `CAP_WAKE_ALARM`; any ambient capability makes pressure-vessel's bwrap refuse to start, so no game ever
   launches. The `default-capability-ambient-set=` pam_systemd option with an empty value did not clear it;
   `steam-session.service` now starts the session through `setpriv --ambient-caps -all --inh-caps -all`.
2. **SIGILL in the shell Steam starts for the game.** Steam builds the game's `LD_PRELOAD` from its overlay
   (`steamrtarm64/gameoverlayrenderer.so`, built with inline LSE) plus whatever the client had. Preloads
   initialise in **reverse load order**, so with LSE-Emu first and the overlay after it, the overlay's
   constructor runs before the SIGILL handler exists (verified: `LD_PRELOAD=lse:overlay /bin/true` -> 132,
   `overlay:lse` -> 0). Fix: a second copy, `liblse_emu_sys.so`, in `/etc/ld.so.preload`; it loads after all
   `LD_PRELOAD` entries and so initialises first. (The same file in both places is loaded once, at the first
   position, which is why it has to be a separate copy.)
3. **SIGBUS (`BUS_ADRERR`) in the overlay.** `/dev/shm` (tmpfs, half of RAM = 488 MB) was 93 % full of Steam
   (`u1000-Shm_*`) and FEX segments leaked by killed sessions; mapping a new segment then faults.
   `steam-session-prep` deletes the steam user's `/dev/shm` leftovers before the client starts.
4. **SIGILL inside the game container.** The host's `/etc/ld.so.preload` does not apply inside
   pressure-vessel; host `LD_PRELOAD` entries are carried in. The session keeps
   `LD_PRELOAD=liblse_emu.so` and sets `PRESSURE_VESSEL_REMOVE_GAME_OVERLAY=1` so no LSE-built overlay runs in
   the container before the handler (cost: no Steam in-game overlay for now).
- LSE-Emu default changed for this ARMv8.0-only image: active for every non-root process unless `LSE_EMU=0`
  (upstream requires `LSE_EMU=1`, which launch environments can drop). In the game container it patched 1,897
  sites in Valve's ARMv8.2 Wine/FEX with nothing unhandled.
- Rendering is DXVK on **llvmpipe** (CPU Vulkan): works, but slow. Next: `PROTON_USE_WINED3D=1` (WineD3D on
  Panfrost GL 3.1) and the ARMv8.0 Proton/FEX rebuilds from sunshineinabox/proton-armv8.
- `steam-launch-wrapper` exports `VK_INSTANCE_LAYERS=VK_LAYER_VALVE_rpo:VK_LAYER_VALVE_fdm_injection` (Steam
  Frame VR layers) for every game on this client channel; harmless here so far.
- Tools: `mdeck-wrap` (launch-option wrapper: env + output to `/tmp/mdeck-wrap-<appid>.log`),
  `mdeck-launch-debug` (run a game's chain by hand with Proton logging), `mdeck eval
  'SteamClient.Apps.RunGame("8400","",-1,100)'` and `SteamClient.Apps.SetAppLaunchOptions(...)` to drive it.

### Geometry Wars performance (640x480, Proton Experimental ARM64, FEX, stock settings)
| Setup | Intro | Main menu (particles) |
|---|---|---|
| DXVK on llvmpipe (CPU Vulkan) | 6.4 FPS | 3.0 FPS (web helper SIGSTOPped), 1.3 FPS (web helper running) |
| WineD3D on Panfrost GL 3.1 (`PROTON_USE_WINED3D=1`) | 4.5 FPS, wrong colours/glow | - |
- During play, zram swap is ~95 % full (926-969 of 974 MB) and `kswapd0` is busy; the game takes ~250-280 MB
  RSS and up to 277 % CPU. Steam's web helper keeps 70-85 % of a core rendering Big Picture behind the game.
- The game's input arrives through Steam Input (`SteamVirtualGamepadInfo_Proton`); at 1-3 FPS a press must be
  held longer than a frame (`mdeck pad hold:a:1500`).
- DXVK stays the default (faster and correct). The real limits are CPU-side: FEX translation and software
  Vulkan. Levers: web helper priority during games, FEX TSO settings, ARMv8.0 Proton/FEX builds (no LSE traps),
  PanVK on the GPU.

### Steam UI on the GPU (`CEF_GPU=1`): works, not stable (reverted)
- Chromium renders through ANGLE on Panfrost (`ANGLE (Mesa, Mali-G31 (Panfrost), OpenGL 3.1)`, GLES 2.0 over
  GL 3.1); gpu_compositing, rasterization, opengl and webgl all enabled; the UI renders correctly. `gbm` logs
  "Failed to export buffer to dma_buf" (display and GPU are separate DRM devices) but it still draws.
- Within a few minutes the GPU process exited (code 512) and the whole client then exited (session restarted).
  The kernel showed `panfrost_gem_shrinker_scan` under memory pressure: GPU buffers come out of the same 1 GB.
- `mdeck-uibench` (12 pad moves over ~15 s): software 156-161 % web helper CPU; GPU 113-191 % (noisy).
  No clear CPU win to justify the instability. Back to `CEF_GPU=0`; revisit with more free RAM (game mode,
  fewer web helper processes).

### Memory livelock: the one strand the recovery loop did not cover (2026-11-24)
- Launching Geometry Wars on the ARMv8.0 Proton 11.0-3 build with Big Picture still up filled zram and the
  device livelocked: ping answered (kernel networking), adb went `offline`, sshd stopped sending its banner,
  and the kernel OOM killer never fired. PID 1 kept feeding the hardware watchdog and the shell `reach-guard`
  saw adbd "running" and :22 "listening", so nothing rebooted. 12 parallel pre-auth SSH connections (to add
  pressure and force an OOM kill) did not break it either.
- Fixes, all in the image:
  - `earlyoom` (`/etc/default/earlyoom`): kills at <6 % RAM and <15 % swap free, preferring Wine/FEX/game
    processes and never the session, Steam client, Xorg or access services.
  - MGLRU thrash protection: `/sys/kernel/mm/lru_gen/min_ttl_ms = 1000` (tmpfiles.d) makes the kernel OOM
    kill instead of evicting a working set younger than 1 s (`CONFIG_LRU_GEN_ENABLED=y` in the ROCKNIX kernel).
  - `reach-guard` is now C, `mlockall()`ed, probes sshd with a real banner read on 127.0.0.1:22 and calls
    `reboot(2)` itself after 4 minutes: a shell script or `systemctl` would need paging in and stall too.
  - `MemoryMin=24M` + `OOMScoreAdjust=-900` for ssh, usb-gadget (adbd), reach-guard and earlyoom.
  - Tried and dropped: a 2 GB `/swapfile` behind zram, as SteamOS keeps one. On this device it shares the SD
    card with the root filesystem, so while it swapped every exec and file read queued behind swap I/O.
    `mdeck-memhog` (incompressible allocations) then held sshd's banner back for up to 50 s, and the extra 2 GB
    of swap kept earlyoom's swap-free threshold out of reach. With zram alone the kernel OOM killer (MGLRU
    `min_ttl_ms`) or earlyoom ends the hog.
  - `reach-guard` also watches PSI (`/proc/pressure/memory`, `full avg10` >= 30 % for 30 s) and then kills
    the processes under `reaper SteamLaunch` (the running game, never Steam). A game larger than RAM makes the
    system crawl long before memory or swap runs out, so neither earlyoom nor the kernel acts. That is what
    happened here: the screen still updated, but SSH handshakes took longer than any client timeout for
    about 35 minutes (sshd logged them as `Connection closed ... [preauth]`).
### Game windows under Big Picture: gamescope's focus protocol
- With `-steamos3` Steam believes it runs under gamescope: it writes `GAMESCOPECTRL_BASELAYER_APPID` on the
  root window (seen: `413091, 769`; 769 is Steam itself) and never raises game windows on a plain X server, so
  a launched game stays hidden behind Big Picture.
- Steam's own windows carry `STEAM_GAME=769`; Proton game windows had no `STEAM_GAME`, only
  `WM_CLASS steam_app_8400`.
- Gamescope's own rules (src/steamcompmgr.cpp, read at master 7d957c5): a window's app is `STEAM_GAME` if set,
  else `STEAM_BIGPICTURE` -> 769, else from its PID: the `app-steam-app<N>-*.scope` cgroup or the nearest
  `reaper SteamLaunch AppId=<N>` ancestor. Gamescope never writes `STEAM_GAME` and has no `WM_CLASS` rule.
  Focus: `GAMESCOPECTRL_BASELAYER_WINDOW` if it names a candidate, else the first appid in
  `GAMESCOPECTRL_BASELAYER_APPID` that has a window (most recently mapped wins); no match keeps the old focus.
  `STEAM_OVERLAY` windows are never base-layer candidates (they are composited on top). It publishes
  `GAMESCOPE_FOCUSABLE_APPS`, `GAMESCOPE_FOCUSABLE_WINDOWS` (`[xid, appid, pid]` triplets),
  `GAMESCOPE_FOCUSED_APP`, `_APP_GFX` and `_WINDOW` on the root. 413091 does not appear in its source.
- `mdeck-focus` does the same on Xorg, using `_NET_WM_PID` and activating the chosen window through openbox
  (`_NET_ACTIVE_WINDOW` with the pager source, so focus-stealing prevention does not apply).

### Games in front of Big Picture, the SteamOS way (2026-11-24)
- Steam's UI only runs its gamescope logic when `IN_GAMESCOPE` is true, which the client derives from
  `GAMESCOPE_WAYLAND_DISPLAY`. Without it the UI never hides itself for a game and keeps
  `GAMESCOPECTRL_BASELAYER_APPID` at `[413091, 769]`. The session now sets
  `GAMESCOPE_WAYLAND_DISPLAY=gamescope-0` (`GAMESCOPE_COMPAT=1` in `steam-session.conf`). Nothing listens
  on that socket, and Steam starts and runs normally.
- With it, Steam builds the queue itself (sp.js `EnsureCorrectComposition`): Opaque gives `[769, game]`,
  otherwise `[game, 769]`, and the webhelper prefixes 413091. On launch the queue went
  `[413091, 769, 8400]` -> `[413091, 8400, 769]` once the game window was focusable, and `mdeck-focus` put the
  game in front with nothing pressed.
- The webhelper turns the UI composition mode (`SteamClient.Window.SetComposition(mode, appids, window)`)
  into `STEAM_OVERLAY`, `STEAM_NOTIFICATION`, `STEAM_INPUT_FOCUS` on its window and the base-layer root
  properties.
- Wine minimizes a fullscreen game that loses focus, and Geometry Wars stops (0 CPU) while minimized, so
  `mdeck-focus` treats iconified clients as focusable (gamescope never iconifies).
- Steam's screensaver (a slideshow of the account's screenshots, `system_idle_screensaver_ac_sec=300`,
  `screensaver_while_ingame=true`) started during the slow launch. Its popup requests Opaque composition and
  pinned Big Picture over the game. Turned off through the client settings protobuf
  (`SteamClient.Settings.SetSetting`, see `mdeck-steam-defaults`).
- Hidden this way, the web helper uses about 4 % of one core behind a game (it was 70-85 % while Big Picture
  kept rendering on top). `game-mode` (SCHED_IDLE web helper) is removed: it starved the Steam button
  in game, and SteamOS has nothing like it.
- Memory: zstd zram compresses Steam's memory about 3.5:1, so zram's 975 MB disk size, not RAM, was what ran
  out. Now zram = 2x RAM, `vm.swappiness=180`, `page-cluster=0`, `watermark_boost_factor=0`,
  `watermark_scale_factor=125`. `PROTON_USE_XALIA=0` (xalia took ~14 % CPU per game).
- Geometry Wars main menu on proton-armv8 11.0-3 (ARMv8.0 build, no LSE traps): 1.4-3.8 FPS.
- In-game Steam button: Steam switches its window to `STEAM_OVERLAY=1`, `STEAM_INPUT_FOCUS=1` (gamescope's
  overlay plane) and keeps the base layer on the game. `mdeck-focus` raises an overlay window above the base
  window and gives it input focus while `STEAM_INPUT_FOCUS` is set. B returns to the game: Steam clears both
  properties and the game is activated again. Without a compositor the overlay's transparent parts are black.
- The Steam menu takes 10-20 s to appear in game: the web helper's memory sits compressed in zram while it
  is hidden. Memory census in game (`mdeck-mem`, PSS + swap): Geometry Wars 441 MB, web helper 388 MB,
  Steam client 123 MB, Xorg 39 MB, Wine services ~90 MB. zram held 700 MB in 173 MB.
- `mdeck-gametest <appid>` runs the whole flow on the device. Geometry Wars: in front 88 s after launch,
  Steam menu +7 s, back in game +5 s, quit and Big Picture back +4 s. A second `RunGame` while the game runs
  leaves a "Game already running" dialog that holds Steam in Overlay composition (the test quits a running
  copy first).

### Brightness and PanVK (2026-11-24)
- Steam's brightness slider works: `SteamClient.System.Display.SetBrightness(x)` writes
  `/sys/class/backlight/*/brightness` itself, on a perceptual curve (0.4 -> 376/2499), and
  `RegisterForBrightnessChanges` reports it back. `70-backlight.rules` lets the `video` group write it.
- PanVK in Debian's Mesa 25.0.7 lists no device for the Mali-G31 (Bifrost v7), even with
  `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`. GPU Vulkan needs a newer Mesa build; DXVK stays on llvmpipe.

### Direct3D 9 on the GPU: WineD3D on Panfrost is the faster path (2026-11-24)
- Screenshots of GL windows via `xwd` are wrong on this setup: the content reads as packed 24-bit pixels in a
  32-bit image (480 of 640 columns, grey stripes). The "wrong colours" noted for WineD3D earlier were this
  artifact. `tools/dev.sh shot` now grabs the KMS plane (`ffmpeg -f kmsgrab`), which is what the panel shows.
- Geometry Wars on proton-armv8 11.0-3, title screen: WineD3D on Panfrost GL 3.1 **8.6 FPS**, correct
  rendering. DXVK on llvmpipe: 1.4-3.8 FPS. With WineD3D the game process uses ~25 % CPU (it was CPU-bound
  at ~180-280 % with llvmpipe).
- Correction (found later the same day): `WINEDLLOVERRIDES=d3d8,d3d9=b` does nothing, because Proton appends
  `d3d9=n;d3d11=n;...` after whatever the session sets, so DXVK stayed in use and the 6 FPS runs in between
  were DXVK on llvmpipe (their FPS lines say `win32u_vkQueuePresentKHR`; WineD3D's say `wglSwapBuffers` or
  `wined3d_cs_exec_present`). The switch that works is `PROTON_USE_WINED3D=1`, now exported by the session.
  Per game, `PROTON_USE_WINED3D=0` in the launch options brings DXVK back for D3D10/11 titles.

### GPU Vulkan: PanVK works on the Mali-G31, but cannot run DXVK or gamescope (2026-11-24)
- Mesa 26.1.6 from trixie-backports (the image now uses it) enumerates `Mali-G31 MC1` (gpu id 0x7093, one
  shader core) through PanVK with `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`. Debian's 25.0.7 listed no device.
  `vkcube` draws the lit, textured cube correctly (about 55 FPS vsynced), so command submission, WSI (xcb)
  and the kernel side (panfrost uAPI) are fine.
- Vulkan 1.0 only: PanVK gates 1.1+ on Valhall (v10); Mesa 26.3.0 (released 2026-11-09, not in Debian yet)
  adds 1.1-1.3 on Bifrost v6/v7. Per the source it still has no `VK_EXT_robustness2`, no transform
  feedback, no descriptor indexing, and `geometryShader`, `fillModeNonSolid`, `shaderClipDistance` stay false
  (the hardware has no geometry shaders).
- Consequences: DXVK (needs Vulkan 1.3, robustness2 nullDescriptor and, for D3D11, geometry shaders) cannot
  run on it; gamescope needs `nullDescriptor` too. Launching Geometry Wars with PanVK visible to DXVK hung at
  startup (no DXVK log, game idle). Native Vulkan programs work: `panvk-run <program>`. PanVK stays off by
  default so Steam, Proton and DXVK keep seeing only llvmpipe.
- Mesa 26.1.6 vs 25.0.7 for the GL path (Geometry Wars under WineD3D, title screen): ~6-8 FPS vs 8.6, within
  run-to-run noise. Kept for PanVK.
- Sources: Mesa source at `src/panfrost/vulkan` (`panvk_physical_device.c`, `panvk_vX_physical_device.c`,
  tag 26.3.1) and the 26.3.0 release notes.

### Backups
- `tools/backup-steam.sh` writes the Steam tree (client, Proton, FEX, runtimes, games, prefixes, login;
  not logs or shader caches) to `cache/steam-backup.tar` (10.9 GB): tar on the device, pulled over adb at
  ~17 MB/s. Streaming it over SSH (Wi-Fi) ran at ~150 KB/s, and an adb shell pipe corrupts binary data.
  `tools/restore-steam.sh` puts it back; `STEAM_SEED=cache/steam-backup.tar tools/build-image.sh` bakes it in.

### Reflash from scratch, and moving 11 GB onto the device (2026-11-24)
- `tools/build-rootfs.sh` + `tools/build-image.sh` (lean, no Steam seed: 2.7 GiB) + `tools/reflash-slot2.sh`
  (muOS copies the gzipped image, `dd` to `/dev/mmcblk1`, FEL boot) produced a working system on the first
  try: first boot grew root to 117 GB, Wi-Fi joined, adb up 15 s after U-Boot, Mesa 26.1.6, earlyoom and
  reach-guard active, a fresh Steam bootstrap started by itself. Total ~6 min after the image existed
  (gzip 14 s, adb push 558 MB 157 s, dd 173 s).
- `adb push` of a multi-GB file does not work on this device: the Debian adbd buffers it (800 MB swapped,
  OOM killer took pipewire and wireplumber) and the transfer died at 4 GB. 558 MB is fine. Large transfers go
  through a raw TCP stream over `adb forward` into `tar -x` (`tools/restore-steam.sh`): constant memory,
  ~7 MB/s, limited by SD writes. Pulling a large file with `adb pull` is fine (17 MB/s).
- Gotcha: `pkill -f <pattern>` inside an ssh/adb command line kills the shell running it (the pattern is in
  its own command line). Use exact names (`pkill -x`) or `pgrep` into a variable first.

### Real gamescope on llvmpipe (2026-11-25)
- gamescope 3.16.22 is in trixie-backports (`contrib`, arm64). It picks llvmpipe, the only conformant Vulkan device
  here, and stops with "physical device doesn't support VK_EXT_physical_device_drm". Everything else it needs is
  there: Vulkan 1.4, `robustness2`, `geometryShader`, DRM format modifiers, dma-buf and fd external memory.
  PanVK (Mali-G31) stays out of reach for the reasons above.
- The missing extension only names the device's DRM nodes. `rootfs/src/vk-fake-drm.c` (LD_PRELOAD) adds it to the
  device extension list, strips it from `vkCreateDevice` and fills `VkPhysicalDeviceDrmPropertiesEXT`. With it
  `gamescope --backend headless` starts, creates `gamescope-0`, starts Xwayland and runs a client:
  glxgears (Panfrost GL through gamescope's Xwayland) holds 30 FPS at `-r 30`, with gamescope at ~85 % of one
  core compositing 640x480 on llvmpipe (the Steam login QR page was using 170 % at the same time).
- gamescope also needs `/usr/games` on PATH (`gamescopereaper`).
- `--backend sdl` nested in Xorg needs two more fixes in the shim: it asks for `VK_KHR_present_id`,
  `VK_KHR_present_wait` and `VK_EXT_hdr_metadata`, which llvmpipe lacks and which fail `vkCreateDevice` with
  `VK_ERROR_EXTENSION_NOT_PRESENT`, so the shim drops every requested extension the device does not list. After
  that gamescope opens its window, swapchain and Xwayland, and `NESTED_GAMESCOPE=1` in `/etc/steam-session.conf`
  runs Steam inside it.
- Result with Steam inside it (2026-11-25): not usable here. The panel stays black while gamescope sits at ~90 % of
  a core (200-500 MB resident, swap climbing on 1 GB of RAM), even with nothing to composite, and Steam
  crashes with SIGBUS (exit 135) about every 90 s. The switch stays in the tree, off by default, for revisiting
  with a GPU Vulkan driver. The DRM backend cannot work: llvmpipe's exportable buffers are not physically
  contiguous and the H700 display engine has no IOMMU.

### Steam re-extracted its whole client on every start (2026-11-25)
- After an unclean shutdown Steam's updater runs "Verifying all executable checksums" instead of "file sizes only".
  `steamrtarm64/steamwebhelper.sh` is patched on every start (no `taskset 0x7c`, `--disable-hang-monitor`) and
  fails that CRC check, so Steam downloaded the manifest, called the package "uninstalled" and re-extracted ~1.4 GB
  (4-5 minutes, then the same again on the next start). Restarting a session through systemd (the 90 s stop timeout
  kills Steam) triggers it every time.
- Fix: `run-steam.sh` restores the stock file (`patch-webhelper.py --restore`, from `~/.cache/mdeck`) before Steam
  starts and patches it again when the updater logs "Verification complete" / "Update complete", before the client
  launches the web helper. A restart after an unclean stop now verifies for ~3 min and does not extract.
- `steam-session.service` has `TimeoutStopSec=20`: Steam needs minutes to exit here and the 90 s default only delayed
  the kill.

### First-install Proton default (2026-11-25)
- The global default (`CompatToolMapping` entry "0") is not enough: when a game installs, Steam writes that game's own
  mapping to Valve's pick, which wins, and Valve's Proton uses LSE atomics (dies on the A53). `mdeck-compat-default`
  (started by `mdeck-steam-defaults`) watches config.vdf and moves any app Steam points at a Valve Proton to the ARMv8
  build through `SteamClient.Apps.SpecifyCompatTool`, once per app (`~/.config/mdeck/compat-handled.json`), so a tool
  chosen by hand afterwards sticks. Verified: Geometry Wars set to `proton-experimental` is back on
  `proton-armv8-proton-11.0-3` within 10 s. DroidDeck's `steam-compatibility` does the same job by rewriting
  config.vdf while Steam is stopped (its `valve_picks` and `plan_mapping`).

### Compressed RAM (CRAM) and what applies to a 1 GB handheld (2026-11-26)
- CRAM is Gregory Price's (Meta) RFC for a compressed-RAM service on a private NUMA node (`N_MEMORY_PRIVATE`,
  `mm/cram.c`), posted as RFC v4 (Feb 2026) and v5 (Jul 2026); not merged. It assumes a device that over-reports its
  capacity with byte-addressable compressed memory (first driver: CXL). Pages stay mapped read-only so reads need no
  fault or decompression; a write faults and promotes the page to DRAM. Reported: ~98 % of plain-DRAM throughput on
  read-only emulation, 5.4-37x zram at 2-20 % writes. Kairui Song's per-page costs: fault 1.92 us, swap management
  1.04 us, LZO decompression 0.32 us, so the fault, not the decompression, is what it removes.
- Verdict: not usable on the H700. There is no compressing device, and a CPU-side software version has no way to
  keep compressed pages readable in place, so it would reduce to zswap-style fault-and-decompress. Revisit if the
  kernel grows a software backend.
- What applies today, with what our kernel (7.2.0-mdeck) already has: zram with lz4/zstd/lzo and `ZRAM_MULTI_COMP`
  (recompress idle pages with a stronger algorithm), `ZRAM_WRITEBACK`, MGLRU (`min_ttl_ms=1000` is set), PSI. Missing:
  `ZRAM_TRACK_ENTRY_ACTIME` (age-based idle marking) and `DAMON` / `DAMON_RECLAIM`, both cheap to add in `kernel/build.sh`.
- Test plan (fixed workload, compare PSI `memory full`, swap-in rate, OOM events, `mm_stat` ratio): current zstd zram;
  lz4 primary with zstd recompression of idle pages; DAMON_RECLAIM with a low `min_age`; zram writeback of idle pages
  to the SD card with a `writeback_limit` to bound flash wear.

### zram algorithm and idle-page recompression (2026-11-26)
`tools/membench.sh` reboots for each setting and runs `mdeck-membench`: a synthetic load (`rootfs/src/memload.c`: 480 MB,
35 % random pages, 30 % hot, 200 s, beside idle Steam) or a real game. Steam refuses a launch while the account plays
on another computer, so game runs need the account free.

| setting | workload | result | PSI full | swap out (pages) | zram ratio | kswapd CPU |
|---|---|---|---|---|---|---|
| zstd | synthetic | 2.26 M touches/s | 3.6 s | 85 k | 4.6 | 11.0 s |
| lz4 | synthetic | 2.22 M | 2.4 s | 189 k | 3.4 | 6.6 s |
| lzo-rle | synthetic | 2.26 M | 1.3 s | 131 k | 3.3 | 4.1 s |
| lzo-rle + zstd recompress | synthetic (2 runs) | 2.27 M, 2.25 M | 1.1 s, 1.6 s | 94 k, 126 k | 4.6, 4.7 | 4.1 s, 4.7 s |
| zstd | Geometry Wars | front in 64 s | 8.1 s | 132 k | 4.9 | 19.1 s |
| lzo-rle + zstd recompress | Geometry Wars | front in 67 s | 4.5 s | 160 k | 4.8 | 10.2 s |

- Throughput is unchanged (the hot set stays resident); the settings differ in stalls, CPU and capacity. zstd alone fits
  ~40 % more than lzo-rle/lz4 but stalls ~3x as long and spends ~2.7x the reclaim CPU.
- lzo-rle live plus zstd recompression of idle pages (`mdeck-zram-recompress`: mark all idle, wait 60 s, recompress what
  stayed idle, niced at low CPU weight) keeps zstd's ratio with lzo-rle's stalls: -45 % stall time and -47 % kswapd CPU
  on the real game for the same start time. The service itself used ~4 % of one core on average during heavy swapping.
  Now the default (`zram-generator.conf`: `compression-algorithm = lzo-rle zstd`).
- DAMON_RECLAIM (2026-11-26; kernel now has DAMON and `ZRAM_TRACK_ENTRY_ACTIME`; `mdeck-damon-reclaim` sets cold pages at
  30 s, 16 MB/s, watermarks widened because the defaults switch it off below 20 % free memory, which is always on 1 GB).
  Synthetic benchmark, same boot procedure, memory stall (PSI some) in ms: baseline `lzo-rle zstd` 1404, 1417 (and 1062
  in a run where DAMON failed to enable); DAMON on 1188 and 3238, with workload rate -3 % and -11 % in the two runs and
  kswapd CPU 4.1 and 8.5 s against 3.5-4.6. Run-to-run noise is about 30 %, and the one clearly different result is worse,
  so there is no evidence DAMON helps: proactively paging out cold memory just adds compression work that competes with
  the game. Left off (the service is there to enable by hand).
- zram writeback to the SD card is not worth testing on this hardware: the card is also the root and Steam's disk, reads
  at about 12 MB/s cold and wears with writes.
- Not yet tried: tuning the recompress interval and threshold (`idle <seconds>` now works with access-time tracking).

### Where a game launch spends its time (2026-11-26, Geometry Wars, ~55-65 s)
- Per-process CPU deltas (not `ps`, which averages over a process's life): `steamwebhelper` uses 7-17 CPU-seconds per
  10 s for the whole launch (the Big Picture UI animating), `steam` ~2, the game itself 3-4 once it runs. The machine is
  not CPU-saturated (about 30 % of four cores mid-launch), and the Wine services (`plugplay`, `winedevice`) start 20-40 s
  in, the game process at ~40 s, its window at ~55 s: mostly serial startup (pressure-vessel, Wine, FEX).
- With a cold page cache a launch reads ~740 MB from the SD card at ~12 MB/s (disk busy almost throughout, tasks
  stalled on I/O 15-23 % of the time); a warm launch is ~10 s faster. Raising the card's `read_ahead_kb` from 128 to 1024 did not help
  (75 s vs 64 s). A faster card is the I/O lever. Untried: pausing or lowering the priority of the web helper during
  launches, FEX code-cache settings, a smaller or pre-warmed Wine prefix.
- Web-helper priority (2026-11-26): `renice 19` on every `steamwebhelper` before launching Geometry Wars gave 63 s and 72 s
  to the game in front against 68 s unmodified. Launch time is serial startup, not CPU contention, so priority does not help.

### First-start downloads are Wi-Fi bound (2026-11-26)
- On a weak link (-59 dBm, 26 Mbit/s receive rate) one connection to GitHub's CDN gets ~1.35 MB/s; four parallel ranged
  connections add only ~25 % (~1.7 MB/s combined). Yesterday's first start saw ~0.4 MB/s for Proton. The roughly
  1.1 GB first-start download (Steam client plus Proton) is therefore link-limited: parallel downloads or a mirror
  would not change much. Levers: a better link (5 GHz), less to download (see the nibOS ideas in the roadmap:
  pre-seeding Steam/Proton on a data partition), or both.

### Linux x86 games under FEX (2026-11-26)
- Steam's own chain (Steam Linux Runtime 1.0 -> 2.0 -> Valve's `FEX` tool) needs SteamOS's `/usr/share/guestos/fex-mesa` guest OS
  and runs pressure-vessel itself under FEX, which cannot import the host's graphics here. We run FEX directly instead
  (`mdeck-fex`, a Steam compatibility tool): Steam Linux Runtime 4.0's x86 platform as the guest root, Valve's FEX GL/DRM/ALSA
  thunks to the host Panfrost, and the old Steam Runtime ("scout") libraries only for what the root lacks (libvorbisfile.so.3,
  libopenal 1.16, libGLU ...).
- `vm.overcommit_memory=1` is required: FEX reserves 4-6 GB per process and the default heuristic refuses any single mapping
  larger than RAM plus swap (`__vm_enough_memory` in dmesg), which made every fork inside FEX fail with ENOMEM.
- SDL 1.2 games never set `_NET_WM_PID`, so `mdeck-focus` could not tell whose window it was and Steam's UI stayed on top of a game
  that was running (sound, no window). It now asks the X server (XRes) for the owning process.
- Steam applies a per-app compatibility-tool request from DevTools a minute or more later, and sometimes not at all; mappings for
  Linux-only games are written into `config.vdf` before Steam starts (`mdeck-compat-default --seed`), with the DevTools request as a
  second path.
- Results: Hotline Miami (32-bit, Qt launcher + GameMaker GL) and Eets (64-bit, FNA GL on the Mali-G31) run; Hotline's window is
  up 22 s after launch, Eets in front in about 30 s.
- Steam side, not ours: with the account shared by several devices, a launch can stall at "Synchronizing cloud" or
  "SynchronizingControllerConfig" (cloud sync failing, "Roaming Config ... Failure"), and Steam ends a running game when another
  device starts one. Steam's offline mode (`SteamClient.User.GoOffline()`) avoids both for testing.

### The QEMU virtual device (2026-11-26)
- `tools/vm.sh` boots our real initramfs and image on a generic arm64 kernel (kernel.org 7.2 defconfig plus virtio, ext4 and FAT built
  in; `tools/qemu/build-kernel.sh`), with a stable SSH, serial log, display and monitor. CI boots every image the same way
  (`vm-boot` job, `tools/qemu/ci.sh`). The device-only units are masked in the VM (wifi-kick, zram, usb-gadget, reach-guard).
- Bugs it found that the handheld could not show: `firstboot` built the data partition path as `<disk>p3` (wrong for `vda`), and
  `mdeck-ssh-import` skipped re-importing keys whenever its stored checksum matched, even if the installed key file was empty (a root
  copied from a live filesystem). Also `reach-guard` reboots a VM that has no network after five minutes.
- Passing: staged update install with trial (`tools/vm.sh test updater 1`), a release that does not boot is rolled back after three
  boots with the failed tag recorded (2), `recovery.txt` with `mdeck=previous` returns to the kept release (3). Not testable there:
  anything that needs the H700, the Mali, Steam's UI, the pad, Wi-Fi or sleep.
- Install speed: the install used to write the whole 3 GiB root (about ten minutes on the card). The updater now lists the 1 MiB chunks
  that hold anything the new filesystem uses (`mdeck-used-chunks`, from `dumpe2fs`' free-block map) and the initramfs writes only those:
  1548 of 3072 MiB for a v0.5-era image, with the pruned image fewer. A block the new filesystem calls free is never read, so stale data
  there is harmless; metadata is never free. `tools/qemu/verify-chunks.sh` proves it on a real image by installing onto a random-filled
  target and requiring a clean `e2fsck -fn` and `diff -r` equal trees. The first version of the parser fell back to the whole image on an
  unexpected line, which is the intended failure mode.

### Mesa 26.3.1 PanVK cross-build (2026-11-26)
`tools/mesa/build.sh` builds Mesa 26.3.1 for arm64 in an amd64 container: the build-time tools (`mesa_clc`, `panfrost_compile`) are built
natively with LLVM 19 first, then a cross build with `-Dvulkan-drivers=panfrost -Dgallium-drivers=panfrost -Dllvm=disabled
-Dplatforms=x11` into `/opt/mesa-mdeck` (7 MB). Gotchas met: Debian 13's `wayland-scanner` is too old for Mesa's wayland-protocols 1.49 (so
X11 only, which is all the session uses), and the cross build needs `panfrost_compile` from a native Panfrost build. A Vulkan loader on a
Debian arm64 userland finds the ICD (`panfrost_icd.cortex-a53.json`) and loads `libvulkan_panfrost.so` with no unresolved symbols; the
only complaint is "no valid GPUs", as expected without a Mali. The test on the Mali-G31 itself is `tools/mesa/try-on-device.sh`.
