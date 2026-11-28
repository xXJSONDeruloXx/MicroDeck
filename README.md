# MicroDeck

Steam on cheap handhelds. MicroDeck is a flashable SD-card OS that boots straight into Steam's Big Picture mode, SteamOS-style,
on Allwinner H700 handhelds. It runs Valve's native arm64 Steam client, and plays Windows games through Proton and Linux x86 games
through FEX.

| Handheld | Wi-Fi | Image |
|---|---|---|
| Anbernic RG40XX-H | yes | `microdeck-rg40xx.img.xz` |
| Anbernic RG28XX | no, USB network only | `microdeck-rg28xx.img.xz` |

More H700 devices are planned. Both images share the same OS; they differ in the unit's RAM timings and screen setup. RAM timings
vary between hardware revisions: a wrong one gives a black screen and no harm, so keep your stock card.

> **Early but working.** Expect it to be slow: Steam's interface is Chromium on four Cortex-A53 cores with 1 GB of RAM, and games
> run through translation layers. Simple and older games are playable; most modern ones are not.

## Install

1. Download the image for your handheld and its `.sha256` from the [latest release](https://github.com/xXJSONDeruloXx/MicroDeck/releases/latest) and check the hash.
2. Write it to a microSD card of 16 GB or more (balenaEtcher, or `xzcat microdeck-rg40xx.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync`).
3. **Wi-Fi** (RG40XX-H): on the card's small `MICRODECK` partition copy `wifi.txt.example` to `wifi.txt` and fill in `ssid=` and `psk=`
   (add `band=a` for 5 GHz only, usually much faster).
   **RG28XX** has no Wi-Fi: plug it into a PC, which sees a USB network adapter, and share the PC's internet with it. On Windows run
   `tools/win-share-usb.ps1` from an elevated PowerShell.
4. Put the card in **slot 1** (TF1, the boot slot) and power on. The first start sets up the card and downloads about 1 GB (Valve's
   Steam client and Proton). Allow up to an hour.
5. Sign in to Steam with the QR code.

If the card does not boot, hold the power button for 10-15 seconds to force an off. Optional SSH: copy `authorized_keys.example` to
`authorized_keys` on the `MICRODECK` partition and paste your public key (`ssh root@microdeck-<device>.local`).

## Updating

In Steam: **Settings > System > Check For Updates**. It downloads the newest release (about 340 MB) and installs it at the next
restart, which takes a few minutes: do not power off. Games, Steam login and settings are kept, and a release that fails to start
three times is replaced by the previous one automatically.

You can also write the new image to the same card. The data partition (Steam, games, login) starts after the system partitions, so
flashing with Etcher or `dd` keeps it. A tool that erases the whole card does not. Releases that change U-Boot need a reflash.

Installed v0.7.x updaters cannot see v0.8.0 or later (the project moved): write that release to the card once.

## What to expect

- **Works:** Big Picture, the built-in pad as a Steam Deck controller, Wi-Fi, Bluetooth, audio, brightness and volume, games in front
  with the Steam button menu over them, in-place updates with rollback.
- **Desktop mode:** in Steam, Power > Switch to Desktop gives a small desktop with Firefox, AbiWord, Gnumeric, a text editor, files and a
  terminal, all driven from the pad (the d-pad or sticks move the pointer, A and B click, Start opens the menu, X opens an on-screen
  keyboard). The Steam button on the panel, or holding Start, returns to Steam. One browser tab at a time fits in 1 GB.
- **Sleep** is on: a short press of the power button sleeps, a long press powers off, and the next press wakes. If a unit does not wake from
  it, hold the power button 10-15 seconds, then turn sleep off with an empty file named `nosleep` on the `MICRODECK` partition (or `mdeck-sleep off`).
- **Games fill the screen.** A game window that does not match the panel (a Windows game's small windowed mode, an old game with a big window) is
  scaled to fit by the GPU, with Steam's menu on top. Steam's own UI runs without its blur effects, which a handheld this size cannot draw
  quickly (`UI_BLUR=1` in `/etc/steam-session.conf` brings them back).
- **Slow:** Direct3D 9 runs on the GPU, Direct3D 10/11 on the CPU. See [docs/games.md](docs/games.md) for what runs.

## More

- [Building and developing](docs/development.md): build it yourself, the boot chain, working on a handheld safely.
- [Roadmap](docs/roadmap.md), [findings](docs/findings.md), [games](docs/games.md), [kernel](docs/kernel.md).

## Credits and licenses

- Kernel, DTBs, modules and firmware: [ROCKNIX](https://github.com/ROCKNIX/distribution) H700 builds (GPL-2.0).
- U-Boot defconfigs and DRAM patch derived from ROCKNIX's H700 U-Boot package; U-Boot and TF-A upstream.
- `rootfs/src/lse_emu.c`: [SildurFX/LSE-Emu](https://github.com/SildurFX/LSE-Emu) (GPL-3.0).
- Steam is Valve's; this project downloads the client from Valve's CDN and ships none of it.

Everything else is GPL-3.0-or-later (see `LICENSE`).
