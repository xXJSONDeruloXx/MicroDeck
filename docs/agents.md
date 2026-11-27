# Working on SteamOSXX as an agent

Short, practical, and learned the hard way. Humans may not be around: leave the device and the repo in a state the next agent can use.

## Two targets
| | Real device (RG40XX-H) | Virtual device (QEMU) |
|---|---|---|
| Reach it | `tools/dev.sh sh 'cmd'` (adb, then SSH) | `tools/vm.sh sh 'cmd'` (SSH to 127.0.0.1:2222) |
| Boot it | muOS in slot 1, then `tools/fel-boot.sh` (any reset lands in muOS) | `tools/vm.sh start` |
| Apply repo changes | `tools/push-live.sh` | `tools/vm.sh push` |
| Look at it | `tools/dev.sh shot out/x.png` | `tools/vm.sh shot out/x.ppm` |
| Has | Mali GPU, Steam, real pad, Wi-Fi, sleep | the real initramfs, systemd, firstboot, updater, services; no Steam UI, GPU or pad |

Use the VM first for anything that is not hardware: updater install/rollback/recovery (`tools/vm.sh test`), firstboot and the data
partition, systemd units, scripts. One-time setup: `tools/vm.sh setup <image.img.xz>` (a CI image from the `image` artifact). The
unit tests and syntax checks run anywhere: `tools/ci-checks.sh`. Docker and QEMU are installed on the dev PC.

## Device rules
- The Steam account is shared with other agents and devices. A game started elsewhere ends yours, and online launches can stall at
  "Synchronizing cloud" or "SynchronizingControllerConfig". Use Steam's offline mode for tests:
  `tools/dev.sh sh 'sxx eval "SteamClient.User.GoOffline()"'` (back with `GoOnline`). Never press Continue on "already playing on
  another computer": it ends the other session.
- Leave the Retroid Duo alone. Never `rmmod` the joypad module while InputPlumber runs (kernel oops).
- Do not suspend the device (s2idle) from a script: the wake source is not working yet and it needs a physical power-button press.
- Dev loop: any reset returns to muOS (slot 1); `tools/rescue.sh` finds the device in any state; flashing slot 2 is
  `tools/reflash-slot2.sh` (it keeps the data partition, so games and the Steam login survive).

## Pitfalls that cost hours
- `pkill -f 'pattern'` or `pgrep -f` inside `tools/dev.sh sh '...'` matches the shell running your own command and kills it. Build the
  pattern at run time: `pat=$(printf 'python3 /usr/local/bin/sxx-compat-%s' default); pkill -f "$pat"`.
- Heredocs and `python - <<EOF` mangle backslashes in the shell tool: `\n` becomes a real newline in code you write. Create files
  with the editor tools, not with shell heredocs, when the text contains backslashes or long multi-line strings.
- `SteamClient.Apps.SpecifyCompatTool` is applied lazily (a minute or more) and sometimes not at all; mappings are seeded into
  `config.vdf` before Steam starts (`sxx-compat-default --seed`, called from `run-steam.sh`). Steam rewrites config.vdf while it runs.
- InputPlumber's `SendEvent` takes stick values only as variant `ad`; other types return success and do nothing. A stick stays at its value
  until you send 0,0.
- Every push to `main` cancels the running CI build (concurrency group): batch commits, then push once.
- A tag push builds a draft release; move or delete the tag before publishing if you pushed it too early (nothing is public until the
  draft is published with `gh release edit <tag> --draft=false --latest`).
- Commits are short semantic one-liners with no co-author or tool trailers; branches never carry a tool prefix.

## Where things are
`overlay/` is the root filesystem overlay (scripts under `usr/local/bin` and `usr/local/sbin`); `debug/initramfs/init` is the boot
step that installs updates; `kernel/` rebuilds the kernel; `rootfs/` the image layers; `docs/findings.md` is the lab notebook,
`docs/roadmap.md` the plan with statuses, `docs/games.md` the compatibility table.

## Hardware checks before a release
Run these on the handheld after flashing the CI image (`xz -dc out/latest/steamos-rg40xx.img.xz > out/steamos-rg40xx.img`, then
`tools/reflash-slot2.sh`; the data partition keeps Steam, games and the login). Put Steam in offline mode first if other devices use the
account. Anything that fails is a release blocker; the VM already covers boot, firstboot, updater and rollback.
1. `tools/smoke.sh`; `uname -r` shows `7.2.0-sxx`; `cat /etc/sxx-release`.
2. `sxx-gametest 8400` (Geometry Wars, Proton) passes: game in front, Steam menu over it, back, quit.
3. A Linux x86 game under FEX (`sxx-gametest 219150` or 6100): window in front, picture painting. `vm.overcommit_memory` is 1.
4. Controller: glyphs in Steam are Deck ones, D-pad and sticks work in a game, rumble works (the joypad driver patch), no `BUG:`
   or `scheduling while atomic` in `dmesg` while rumbling.
5. Steam Settings > Bluetooth scans; Settings > System > Check For Updates works against the real GitHub release.
6. Wi-Fi: `iw dev wlan0 link` (band, rate) and a 100 MB download timing; `band=a` in `wifi.txt` if 5 GHz is available.
7. Battery: `systemctl status sxx-battery` is active; `cat /sys/class/power_supply/battery/{status,capacity}`.
8. Optional: `tools/mesa/try-on-device.sh` for the Mesa 26.3 PanVK report.
