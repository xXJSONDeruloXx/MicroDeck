# Game compatibility

Device: RG40XX-H (H700, 4x Cortex-A53 ARMv8.0, Mali-G31, 1 GB RAM), 640x480. Steam arm64 client in
Big Picture; Windows games through Proton ARM64 + FEX. Direct3D defaults to WineD3D on the GPU (`PROTON_USE_WINED3D=1`); D3D10/11 titles need `PROTON_USE_WINED3D=0` (DXVK on llvmpipe, slow). DXVK cannot use the GPU: PanVK on this Mali lacks what it needs.

| Game (appid) | Compat tool | Renderer | Result | FPS | Notes |
|---|---|---|---|---|---|
| Geometry Wars: Retro Evolved (8400) | Proton Experimental (ARM64) | DXVK / llvmpipe | Runs, playable input | 6.4 intro, 1.3-3.0 menu | menu 3.0 with the web helper stopped |
| Geometry Wars: Retro Evolved (8400) | Proton Experimental (ARM64) | WineD3D / Panfrost GL 3.1 | Runs | 4.5 intro | the colour problem was a screenshot artifact |
| Geometry Wars: Retro Evolved (8400) | proton-armv8 11.0-3 (sunshineinabox) | WineD3D / Panfrost (`PROTON_USE_WINED3D=1`, the default) | Runs, correct, full Steam menu round trip | 6-8.6 title | ~1.5-2.5 min to the title screen |
| Geometry Wars: Retro Evolved (8400) | proton-armv8 11.0-3 (sunshineinabox) | DXVK / llvmpipe (`PROTON_USE_WINED3D=0`) | Runs; comes to the front on launch, Steam button menu and back work | 1.4-3.8 menu | ~2 min to the title screen; 441 MB |
| Hotline Miami (219150) | Linux x86 build under FEX (`sxx-fex`) | OpenGL through FEX's GL thunk to Panfrost | Runs: Qt launcher, title screen, first level | 10+ (every sampled frame differed at 10 samples/s) | native 32-bit x86 game; ~3 min to the title screen the first time (FEX translating); keyboard works, pad mapping not checked |
| Eets (6100) | Linux x86-64 build under FEX (`sxx-fex`) | FNA OpenGL through FEX's GL thunk, Mali-G31 (Panfrost) | Runs, in front ~30 s after launch; menu renders | not measured | needs one A press for Steam's on-screen-keyboard hint; the 800x600 window is larger than the 640x480 panel (name box clipped) |

How to test a title: install it from Big Picture, then
`sxx eval 'SteamClient.Apps.SetAppLaunchOptions(<appid>, "DXVK_HUD=fps /usr/local/bin/sxx-wrap %command%")'`
and `sxx eval 'SteamClient.Apps.RunGame("<appid>","",-1,100)'`; the wrapper log is `/tmp/sxx-wrap-<appid>.log`.
