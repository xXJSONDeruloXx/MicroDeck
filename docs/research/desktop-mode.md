# Desktop mode

Goal: from Steam's power menu ("Switch to Desktop"), a controller-driven desktop for desktop-class apps (browser, word processor,
text editor, file manager, terminal), and a way back to Steam. These handhelds have no touchscreen, 1 GB of RAM and four Cortex-A53 cores,
so the desktop has to be small, and every control has to work from the built-in pad.

## Options

| Option | RAM at idle (estimate) | Fits here? |
|---|---|---|
| KDE Plasma (what SteamOS ships) | 500-800 MB | No. It would leave almost nothing for a browser, and its Wayland session needs the GPU features PanVK lacks (kwin wants Vulkan or full GLES 3 paths we have not proven). Plasma's upstream alignment is not worth it on 1 GB. |
| Wayland: labwc + Waybar (Handtop's choice) | 60-90 MB | Proven on the same H700 (Handtop, RG35XX-H). Needs a second graphics stack next to our Xorg session (wlroots on Panfrost), a second path for rotation, fit and focus. |
| X11: the existing Xorg + openbox, plus a small panel and launcher | 30-50 MB | Reuses what the Steam session already runs (Xorg with glamor on Panfrost, `mdeck-rotate`, `mdeck-fit`, openbox). Same session service, only the client script differs. Chosen. |

Desktop mode replaces the Steam session rather than running beside it: Steam is stopped, which frees about 300-400 MB for the apps.

## Design

- **Switching.** Steam's power menu calls `steamos-session-select plasma` (or `desktop`). It records `desktop` in `~/.config/mdeck/session` and
  ends Steam; `steam-session-x` reads the file at the next start and runs `mdeck-desktop` instead of Steam, resetting the file so a crash or
  logout returns to Steam. A "Return to Gaming Mode" entry runs `steamos-session-select gamescope`, which ends the desktop.
- **Controller.** Without Steam running there is no Steam Input desktop layout, so a small daemon (`mdeck-desktop-pad`) grabs the built-in pad
  and writes a virtual mouse and keyboard through uinput: left stick moves the pointer (power curve, dead zone), right stick scrolls, A/B click,
  d-pad moves keyboard focus, and one button toggles an on-screen keyboard. Handtop's mapping is a good starting point (D-pad pointer, stick scroll,
  A left click, B right click, L1 Esc, R1 Enter, X keyboard). Lessons from Handtop to keep: the grab must release cleanly on exit (a killed daemon froze its
  unit), a watchdog restarts the daemon if it hangs, and the power key must still reach logind.
- **On-screen keyboard.** Controller-navigable (d-pad moves between keys, A types), drawn with Xlib and sent with XTest so it adds no toolkit.
- **Panel and launcher.** A launcher grid navigable with the d-pad and a clock/battery/volume strip; openbox for window management with maximized windows by default.
- **Apps** (kept to what fits in 1 GB): a browser (Firefox ESR, or a lighter WebKitGTK one if Firefox is too heavy; to be measured), AbiWord and Gnumeric
  for documents and spreadsheets (LibreOffice is far heavier), a text editor, a file manager, a terminal.
- **Image size.** The root partition is fixed at 3 GiB and the root is about 1.4 GB, so the desktop packages must stay near 500 MB or they go in a
  separate add-on installed on demand.

## Prototype results (RG28XX, 2026-11-27)

Built and run on a real RG28XX (v0.8.0 plus the desktop files; apps installed with apt):

- Steam's Power menu has "Switch to Desktop" (with an "Are you sure?" step); it runs `steamos-session-select plasma`. The desktop was up 20 s
  after confirming, InputPlumber stopped, the pad daemon running. `steamos-session-select gamescope` (also: Start held 2 s) went back to Steam
  in under 20 s with InputPlumber running again.
- Driven through the virtual test pad (`mdeck pad`): the d-pad moves the pointer (a 600 ms press travels about 190 px, speeding up while held),
  Start opens the openbox menu, the d-pad and A pick an entry (Text editor started maximized with a taskbar button), X opens the on-screen
  keyboard, A types, LB toggles Shift. Not yet checked with the real buttons: which physical button is which, and the stick feel on an RG40XX-H.
- Memory: desktop idle with panel and pad daemon uses about 270 MB of 975 MB (Steam's session about 530 MB). Firefox ESR 153 on a Wikipedia
  article with two sidebars added about 410 MB (717 MB used, 258 MB available, zram 283 MB, memory pressure `some` 5 %): usable for one
  tab. Mousepad adds about 40 MB. `/etc/firefox-esr/mdeck.js` limits it to two content processes.
- Disk: the apps are 430 MB installed (Firefox 275 MB, AbiWord + Gnumeric 70 MB), so the root goes from 1.3 GB to 1.7 GB of its 3 GiB, and the
  release image grows accordingly. The packages are in the image rather than installed on demand because an in-place update replaces the root
  and would drop anything installed later.
- Wayland would not have been faster to build: the existing Xorg session already gave rotation, scaling and the cursor.

## Still to do

- Check the real buttons and sticks on both handhelds; tune pointer speed.
- A visible hint for keys mode versus pointer mode (a small panel indicator), and a gaming-mode shortcut in the panel.
- Screen scale: Firefox and GTK apps are large on the 480x640 portrait panel; an RG40XX-H pass.
- Decide whether to keep Gnumeric and AbiWord (70 MB), and whether LibreOffice is wanted despite its size.

## Open questions

- Firefox ESR versus a WebKitGTK browser: Firefox is usable for one tab; a lighter browser would leave room for more.
- 480x640 portrait on the RG28XX versus 640x480 on the RG40XX-H: font and widget scale.

## Reference

- Handtop (junsulee119/handtop): labwc desktop for the RG35XX-H, a Python input daemon with uinput mouse/keyboard output and a custom on-screen keyboard.
