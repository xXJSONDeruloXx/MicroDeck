# Developing MicroDeck

How the system is put together, how to build it, and how to work on it without risking a handheld. For installing and using it, see the [README](../README.md).

## What works (detail)

| Area | Status | Notes |
|---|---|---|
| Boot | yes | U-Boot with this unit's LPDDR4 timings, ROCKNIX's mainline 7.2 kernel, Debian trixie |
| Display | yes | DSI panel via sun4i-drm/KMS, Xorg modesetting + glamor on Panfrost |
| GPU | partial | Panfrost GL 3.1 / GLES 3.1 (Mesa 26.1); PanVK Vulkan 1.0 for native programs (`panvk-run`), not enough for DXVK |
| Steam | yes | `steamdeck_publicbeta` linuxarm64 client, `-gamepadui -steamos3`, LSE atomics emulated (ARMv8.0) |
| Linux x86 games | works (first tests) | games with only a Linux build run through Valve's FEX with Steam's x86 runtime (`mdeck-fex`, selected automatically); first one: Hotline Miami |
| Games | yes, slow | Proton ARM64 (Valve's, or [proton-armv8](https://github.com/sunshineinabox/proton-armv8)) + FEX; Direct3D on the GPU through WineD3D/Panfrost (D3D10/11 need DXVK on llvmpipe, slow). See [games.md](games.md) |
| SteamOS session | partial | gamescope's focus protocol on Xorg (`mdeck-focus`): games in front, Steam button menu over them; power menu; brightness slider; volume |
| Audio | yes | H616 codec through PipeWire in the session; speaker and headphone jack |
| Controls | yes | the built-in pad appears to Steam as a native Steam Deck controller (28de:1205, via InputPlumber and our kernel's USB/IP and HIDRAW); volume keys, menu+volume brightness |
| Memory (1 GB) | managed | zstd zram at 2x RAM, earlyoom, MGLRU thrash guard, and a guard that ends a game on sustained memory stalls |
| Wi-Fi | yes | RTL8821CS (rtw88), NetworkManager |
| Bluetooth | yes | the same chip, bluez; Steam's Bluetooth page scans (pairing not yet tried), PipeWire audio |
| Sleep / wake | opt-in | s2idle works (wake from the RTC verified, with a game running too); the power-button wake still needs a physical check on each handheld: `mdeck-sleep on`, `mdeck-sleep test` (roadmap.md) |
| gamescope | emulated | real gamescope runs on llvmpipe with a small shim but costs ~90 % of a core and crashes Steam here (findings.md); Steam runs in its gamescope mode against Xorg + `mdeck-focus` |
| Standalone boot from slot 1 | yes | the same image boots from a card in slot 1 with no muOS or PC (2026-11-25); development still uses slot 2 through FEL |
| First start | yes | downloads Valve's arm64 Steam client and the pinned ARMv8.0 Proton, with a progress window, and makes that Proton the default |

## How it boots

```
Boot ROM -> U-Boot SPL (LPDDR4 timings from the unit's own boot0) -> TF-A -> U-Boot
        -> extlinux: ROCKNIX kernel 7.2 + RG40XX-H DTB + logging initramfs
        -> Debian trixie (systemd) -> steam-session.service (logind session, rootless Xorg, PipeWire)
        -> Steam -gamepadui
```

Card layout: U-Boot at 8 KiB, p1 FAT32 `MICRODECK` (kernel, DTBs, initramfs, `extlinux.conf`), p2 ext4
`microdeck-root` (grown to the card on first boot).

## Building

Needs Docker (with arm64 emulation) and bash. Run from the repository root.

```
tools/fetch-rocknix.sh        # ROCKNIX H700 release: kernel, DTBs, modules, firmware -> cache/
uboot/build.sh card           # U-Boot for booting from slot 1 -> out/uboot/card.bin
tools/build-rootfs.sh         # Debian arm64 userspace -> out/rootfs.tar
tools/build-image.sh          # -> out/microdeck-rg40xx.img
```

Before `build-rootfs.sh`, put your own `secrets/authorized_keys` (SSH public key) and Wi-Fi profiles in
`secrets/nm/*.nmconnection`; they are copied into the image and never committed. If
`cache/steam-home.tar` exists (a Steam install from another device), it is seeded into the image;
`tools/fetch-steam.sh` makes a clean, SHA256-checked client seed instead (`STEAM_SEED=`).

GitHub Actions builds U-Boot, the rootfs (on an arm64 runner) and the image on every push; tagged builds
attach the image to a draft release.

**RAM timings differ between hardware revisions.** `rg40xxh_2025_lpddr4_defconfig` matches the unit this
was built on; read yours from its stock firmware first (`tools/boot0-dram.py`, see
[lessons-learned.md](lessons-learned.md)). Wrong timings give a silent, completely dead boot.

## Developing without touching the device

The development setup keeps muOS in slot 1 as a known-good recovery system and this OS in slot 2:

- `tools/fel-boot.sh` reboots muOS into FEL (USB boot mode) and loads a U-Boot that boots slot 2.
- Any reset returns to muOS. The hardware watchdog, panic-on-oops, a reachability guard and dev-mode
  power handling make sure every failure ends in a reset rather than a hang.
- `tools/rescue.sh` finds the device in any state and gets a shell back; `tools/dev.sh` runs commands and
  takes screenshots over adb or SSH; `tools/push-live.sh` applies the overlay to the running device.
- `tools/backup-steam.sh` / `tools/restore-steam.sh` keep the Steam tree (games, Proton, login) across
  reflashes; `tools/cycle.sh` chains build, flash, restore and test; `tools/reflash-slot2.sh` writes `out/microdeck-rg40xx.img` to the slot-2 card and boots it.
- `tools/smoke.sh` checks every area in one go; on the device, `mdeck-gametest <appid>` launches a game from
  Steam and checks it comes to the front, the Steam menu opens over it and closes, and quitting returns
  to Big Picture. `mdeck eval` drives Steam's UI through DevTools; `mdeck pad` presses buttons on a virtual pad.

A virtual device needs no hardware at all: `tools/vm.sh setup <image.img.xz>` once, then `tools/vm.sh start`, `sh`, `push`, `test`.
It boots the real initramfs and image in QEMU on a generic arm64 kernel (systemd, firstboot, the data partition, the updater with its
rollback and `recovery.txt`; no Steam UI, GPU or pad), and CI boots every image the same way. See [agents.md](agents.md). The kernel and how it differs from ROCKNIX's: [kernel.md](kernel.md).

See the recovery playbook in [lessons-learned.md](lessons-learned.md) and the running
[findings.md](findings.md).

See the recovery playbook in [lessons-learned.md](lessons-learned.md), the running [findings.md](findings.md) and the [roadmap](roadmap.md).
