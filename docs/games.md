# Game compatibility

Device: RG40XX-H (H700, 4x Cortex-A53 ARMv8.0, Mali-G31, 1 GB RAM), 640x480. Steam arm64 client in
Big Picture; Windows games through Proton ARM64 + FEX. Direct3D defaults to WineD3D on the GPU (`PROTON_USE_WINED3D=1`); D3D10/11 titles need `PROTON_USE_WINED3D=0` (DXVK on llvmpipe, slow). DXVK cannot use the GPU: PanVK on this Mali lacks what it needs.

| Game (appid) | Compat tool | Renderer | Result | FPS | Notes |
|---|---|---|---|---|---|
| Geometry Wars: Retro Evolved (8400) | Proton Experimental (ARM64) | DXVK / llvmpipe | Runs, playable input | 6.4 intro, 1.3-3.0 menu | menu 3.0 with the web helper stopped |
| Geometry Wars: Retro Evolved (8400) | Proton Experimental (ARM64) | WineD3D / Panfrost GL 3.1 | Runs | 4.5 intro | the colour problem was a screenshot artifact |
| Geometry Wars: Retro Evolved (8400) | proton-armv8 11.0-3 (sunshineinabox) | WineD3D / Panfrost (`PROTON_USE_WINED3D=1`, the default) | Runs, correct, full Steam menu round trip | 6-8.6 title | ~1.5-2.5 min to the title screen |
| Geometry Wars: Retro Evolved (8400) | proton-armv8 11.0-3 (sunshineinabox) | DXVK / llvmpipe (`PROTON_USE_WINED3D=0`) | Runs; comes to the front on launch, Steam button menu and back work | 1.4-3.8 menu | ~2 min to the title screen; 441 MB |
| Hotline Miami (219150) | Linux x86 build under FEX (`mdeck-fex`) | OpenGL through FEX's GL thunk to Panfrost | Runs: title screen, menu, first level (the Qt launcher is skipped; its 1280x720 window is scaled to fit the panel) | 10+ (every sampled frame differed at 10 samples/s) | native 32-bit x86 game; ~3 min to the title screen the first time (FEX translating); keyboard works, pad mapping not checked |
| Eets (6100) | Linux x86-64 build under FEX (`mdeck-fex`) | FNA OpenGL through FEX's GL thunk, Mali-G31 (Panfrost) | Runs, in front ~30 s after launch; menu renders | not measured | needs one A press for Steam's on-screen-keyboard hint; its 1024x768 window is scaled to fit the 640x480 panel by `mdeck-focus`/`mdeck-fit` (whole title screen visible, checked on the RG28XX) |

How to test a title: install it from Big Picture, then
`mdeck eval 'SteamClient.Apps.SetAppLaunchOptions(<appid>, "DXVK_HUD=fps /usr/local/bin/mdeck-wrap %command%")'`
and `mdeck eval 'SteamClient.Apps.RunGame("<appid>","",-1,100)'`; the wrapper log is `/tmp/mdeck-wrap-<appid>.log`.

## Direct3D 11 games (Unity and others), 2026-11-28
- A tester reported "error initializing player" on most Direct3D 11 games and a desktop mode that looked empty. The first is the session's default:
  Proton runs with WineD3D (`PROTON_USE_WINED3D=1`, Direct3D 9 on the GPU through Panfrost's OpenGL 3.1), which cannot create a Direct3D 11 device.
  Unity logs `d3d11: failed to create D3D11 device (0x80004005)`; an old Unity (8-Bit Bayonetta, 5.5) then falls back to Direct3D 9, a newer one has no fallback.
- `mdeck-compat-default` now looks for `D3D11CreateDevice` / `d3d11.dll` in a game's programs (top two folder levels) and sets the launch options
  `PROTON_USE_WINED3D=0 %command%` (DXVK on llvmpipe) once, unless the game already has launch options. Over DevTools the call is
  `SteamClient.Apps.SetAppLaunchOptions(<appid as a NUMBER>, "...")`; with the app id as a string it silently does nothing.
- Measured on the RG40XX-H: Vampire Survivors (Unity 6000.0.62) creates `Direct3D 11.0 [level 11.1]` on llvmpipe and goes on to start its engine;
  8-Bit Bayonetta creates `Direct3D 11.0 [level 11.0]` and runs its splash screens. Both are slow (the game uses all four cores for the software
  renderer): Bayonetta's PlatinumGames logo alternated between the logo and black about six times a second and the game did not reach its title in
  five minutes. This works, it is not fast; a Vulkan driver on the Mali GPU (docs/research/panvk-vulkan-dxvk.md) is what would make it playable.
- Unity games of the Windows kind open a launcher dialog first ("<game> Configuration": resolution, quality, Play!). A pad cannot click it, so the game
  never started. `mdeck-focus` now presses Enter on it once (`MDECK_UNITY_DIALOG=0` turns that off); Bayonetta then starts.
- The scaler showed such a dialog black: a window that was already mapped gets a new, empty backing pixmap when it is redirected, and a static Wine dialog
  never repaints on its own. `mdeck-scale` now asks a window to repaint (`XClearArea` with exposures) right after redirecting it.

