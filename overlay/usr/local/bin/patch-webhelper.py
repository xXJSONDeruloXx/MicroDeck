#!/usr/bin/env python3
"""Rewrites Valve's steamwebhelper.sh for this device, keeping its byte size.

- drops `taskset 0x7c` (Steam Deck cores 2-6; leaves 2 of 4 cores here)
- adds --disable-hang-monitor (renderers on an A53 with software raster are
  slow enough that Steam kills them as unresponsive)
Steam checks executable checksums after an unclean shutdown and re-extracts the whole client when this file
differs, so run-steam.sh restores the stock file before Steam starts (--restore) and patches again once the
updater's verification is done, just before the client launches the web helper.
"""
import os
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
path = args[0] if args else os.path.expanduser(
    "~/.local/share/Steam/steamrtarm64/steamwebhelper.sh")
marker = b"--disable-hang-monitor"
stock = os.path.expanduser("~/.cache/mdeck/steamwebhelper.sh.stock")
orig = open(path, "rb").read()
# a card from before the rename keeps the saved original under the old state directory: without it the patched wrapper could not be
# restored, and Steam would re-extract the whole client after an unclean shutdown
legacy = os.path.expanduser("~/.cache/" + "sx" + "x/steamwebhelper.sh.stock")
if not os.path.exists(stock) and os.path.exists(legacy):
    os.makedirs(os.path.dirname(stock), exist_ok=True)
    os.replace(legacy, stock)
if "--restore" in sys.argv:
    if marker in orig and os.path.exists(stock):
        mode = os.stat(path).st_mode
        open(path, "wb").write(open(stock, "rb").read())
        os.chmod(path, mode)
        print("patch-webhelper: restored", path)
    sys.exit(0)
if marker in orig:
    sys.exit(0)
os.makedirs(os.path.dirname(stock), exist_ok=True)
open(stock, "wb").write(orig)
extra = os.environ.get("WEBHELPER_EXTRA_ARGS", "").encode()
new = (b'#!/bin/bash\n'
       b'cd "$(dirname -- "${BASH_SOURCE[0]}")"\n'
       b'[ -n "$DISPLAY" ] || export DISPLAY=:0\n'
       b'export LIBGL_KOPPER_DISABLE=true\n'
       b'exec $(pwd)/steamwebhelper "$@" ' + marker + (b" " + extra if extra else b"") +
       b' &> ~/.steam/steam/logs/steamwebhelper.log\n')
pad = len(orig) - len(new)
if pad < 2:
    sys.exit(f"patch-webhelper: new wrapper is {-pad} bytes too long")
new += b"#" * (pad - 1) + b"\n"
mode = os.stat(path).st_mode
open(path, "wb").write(new)
os.chmod(path, mode)
print("patch-webhelper: patched", path)
