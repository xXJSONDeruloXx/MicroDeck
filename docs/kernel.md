# Kernel: what differs from ROCKNIX

The kernel (`7.2.0-mdeck`, built by `kernel/build.sh` and cached by CI) is kernel.org 7.2 with ROCKNIX's H700 patches and config. Keep
this list in the same change as any edit to `kernel/` (an idea taken from the Handtop project's `docs/kernel.md`).

| Change | Why | Where |
|---|---|---|
| `CONFIG_HIDRAW=y` | Steam talks to controllers through hidraw; ROCKNIX's kernel has none and HID is built in | `kernel/build.sh` |
| `UHID`, `HID_STEAM`, `USBIP_CORE`, `USBIP_VHCI_HCD` as modules | the virtual Steam Deck controller (InputPlumber presents a USB/IP device with Valve's ID); `uhid` for Bluetooth HID | `kernel/build.sh` |
| `ZRAM_TRACK_ENTRY_ACTIME`, `DAMON`, `DAMON_VADDR/PADDR/SYSFS`, `DAMON_RECLAIM`, `DAMON_LRU_SORT` built in | memory experiments (idle-time recompression; DAMON reclaim measured no gain and is left off) | `kernel/build.sh` |
| `CONFIG_LOCALVERSION="-mdeck"` | modules for this kernel sit beside ROCKNIX's `7.2.0` ones, so either can boot | `kernel/build.sh` |
| `rocknix-singleadc-joypad` built out of tree with `DEVICE=H700` | the gamepad driver for the H700 handhelds (ROCKNIX ships it as a module list we do not use) | `kernel/build.sh`, pinned by commit and SHA-256 |
| `kernel/patches/joypad-rumble-no-mutex.patch` | ff-memless calls the rumble play callback from a timer (atomic context); the driver took a mutex there, which can sleep and deadlock against the PWM work item. Found by the Handtop project on the RG35XX-H (same driver) | applied after the joypad archive is unpacked |
| ROCKNIX's initramfs and firmware built in | the image has no module-loading initramfs of its own for the kernel; our own tiny initramfs (`debug/initramfs/init`) is loaded beside it | `kernel/extract-initramfs.py`, `tools/fetch-rocknix.sh` |

Not changed: the DTBs (ROCKNIX's `sun50i-h700-anbernic-rg40xx-*.dtb`), the device patches, the IOMMU settings.

## The virtual-device kernel
`tools/qemu/build-kernel.sh` and `tools/qemu/ci.sh` build a second, unrelated kernel: kernel.org 7.2 `defconfig` plus virtio disk, network
and GPU, ext4 and FAT built in, for the QEMU virtual device (`tools/vm.sh`). It has no H700 support and never ships.

## Ideas not done yet
A `boot-abi` stamp (kernel release and a hash of `KERNEL`) checked before installing a kernel-modules update, so a mismatched module set is
refused instead of half-installed; Cedrus video decode (Handtop's patches); the video-engine DTB overlay. See `docs/roadmap.md`.
